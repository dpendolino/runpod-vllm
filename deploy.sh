#!/usr/bin/env bash
# Deploy a serverless vLLM endpoint on RunPod.
# Idempotent: reuses TEMPLATE_ID and ENDPOINT_ID from .env if set.
# Flow: saveTemplate -> saveEndpoint(templateId)
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found. Run 'make init' first." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${RUNPOD_API_KEY:?RUNPOD_API_KEY is required}"
: "${MODEL_NAME:?MODEL_NAME is required}"
: "${ENDPOINT_NAME:?ENDPOINT_NAME is required}"
: "${GPU_IDS:?GPU_IDS is required (e.g. ADA_24, AMPERE_24)}"

API="https://api.runpod.io/graphql"
REST="https://rest.runpod.io/v1"

# Pin worker image — bump intentionally, not automatically
IMAGE="${IMAGE:-runpod/worker-v1-vllm:v2.20.0}"
TEMPLATE_NAME="${ENDPOINT_NAME}-tmpl"

redact() {
  python3 - <<'PY'
import json, re, sys
data = sys.stdin.read()
patterns = [
    (r'"value"\s*:\s*"hf_[^"]*"', '"value": "<REDACTED_HF_TOKEN>"'),
    (r'Bearer\s+[A-Za-z0-9_\-\.]+', 'Bearer <REDACTED>'),
]
for pat, repl in patterns:
    data = re.sub(pat, repl, data)
print(data)
PY
}

call_api() {
  local resp http body
  resp=$(curl -sS -w '\n%{http_code}' -X POST "$API" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$1")
  http="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [[ "$http" != "200" ]]; then
    echo "HTTP $http" >&2
    echo "Request: $(echo "$1" | redact)" >&2
    echo "Response: $body" >&2
    return 1
  fi
  echo "$body"
}

# Worker env var reference: https://github.com/runpod-workers/worker-vllm
build_template_input() {
  python3 - <<'PY'
import json, os
env = [
    {"key": "MODEL_NAME", "value": os.environ["MODEL_NAME"]},
    {"key": "MAX_MODEL_LEN", "value": os.environ.get("MAX_MODEL_LEN", "8192")},
    {"key": "GPU_MEMORY_UTILIZATION", "value": os.environ.get("GPU_MEMORY_UTILIZATION", "0.9")},
    {"key": "HF_HUB_ENABLE_HF_TRANSFER", "value": "1"},
    {"key": "HF_HUB_DOWNLOAD_TIMEOUT", "value": "120"},
]
if os.environ.get("HF_TOKEN"):
    env.append({"key": "HF_TOKEN", "value": os.environ["HF_TOKEN"]})
inp = {
    "name": os.environ["TEMPLATE_NAME"],
    "imageName": os.environ["IMAGE"],
    "containerDiskInGb": int(os.environ.get("CONTAINER_DISK_GB", "20")),
    "volumeInGb": 0,
    "isServerless": True,
    "dockerArgs": "",
    "env": env,
}
if os.environ.get("TEMPLATE_ID"):
    inp["id"] = os.environ["TEMPLATE_ID"]
if os.environ.get("REGISTRY_AUTH_ID"):
    inp["containerRegistryAuthId"] = os.environ["REGISTRY_AUTH_ID"]
print(json.dumps(inp))
PY
}

build_endpoint_input() {
  python3 - <<'PY'
import json, os
inp = {
    "name": os.environ["ENDPOINT_NAME"],
    "templateId": os.environ["TEMPLATE_ID"],
    "gpuIds": os.environ["GPU_IDS"],
    "workersMin": int(os.environ.get("MIN_WORKERS", "0")),
    "workersMax": int(os.environ.get("MAX_WORKERS", "1")),
    "idleTimeout": int(os.environ.get("IDLE_TIMEOUT", "30")),
    "scalerType": "QUEUE_DELAY",
    "scalerValue": 4,
}
if os.environ.get("ENDPOINT_ID"):
    inp["id"] = os.environ["ENDPOINT_ID"]
print(json.dumps(inp))
PY
}

wrap_query() {
  python3 - <<'PY'
import json, os
mutation = os.environ["MUTATION"]
field = os.environ["FIELD"]
required = "!" if os.environ.get("MUTATION_REQUIRED", "1") == "1" else ""
inp = json.loads(os.environ["INPUT"])
print(json.dumps({
    "query": "mutation Save($input: " + mutation + required + ") { " + field + "(input: $input) { id name } }",
    "variables": {"input": inp},
}))
PY
}

# Create or reuse a Docker Hub registry auth on RunPod.
# Requires DOCKER_USERNAME and DOCKER_PASSWORD env vars in .env.
ensure_registry_auth() {
  if [[ -z "${DOCKER_USERNAME:-}" || -z "${DOCKER_PASSWORD:-}" ]]; then
    echo "  (skip — set DOCKER_USERNAME and DOCKER_PASSWORD in .env to avoid Docker Hub rate limits)"
    return 0
  fi
  if [[ -n "${REGISTRY_AUTH_ID:-}" ]]; then
    echo "  (reusing REGISTRY_AUTH_ID=$REGISTRY_AUTH_ID)"
    return 0
  fi
  local resp
  resp=$(curl -sS -X POST "$REST/containerregistryauth" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"dockerhub\",\"username\":\"$DOCKER_USERNAME\",\"password\":\"$DOCKER_PASSWORD\"}" 2>/dev/null)
  REGISTRY_AUTH_ID=$(echo "$resp" | jq -r '.id // empty' 2>/dev/null)
  if [[ -z "$REGISTRY_AUTH_ID" ]]; then
    echo "  (skip — registry auth unavailable, continuing without it)"
    return 0
  fi
  upsert_id_in_env REGISTRY_AUTH_ID "$REGISTRY_AUTH_ID"
  echo "  (created REGISTRY_AUTH_ID=$REGISTRY_AUTH_ID)"
}

upsert_id_in_env() {
  local key="$1" value="$2"
  if grep -q "^$key=" .env; then
    sed -i.bak "s|^$key=.*|$key=$value|" .env
  else
    echo "$key=$value" >> .env
  fi
  rm -f .env.bak
}

export IMAGE TEMPLATE_NAME REGISTRY_AUTH_ID

echo "==> Setting up Docker Hub registry auth"
ensure_registry_auth

echo "==> Saving template ($TEMPLATE_NAME)"
INPUT=$(build_template_input)
export INPUT MUTATION="SaveTemplateInput" MUTATION_REQUIRED="0" FIELD="saveTemplate"
QUERY=$(wrap_query)
RESP=$(call_api "$QUERY")
echo "$RESP" | jq .
TEMPLATE_ID=$(echo "$RESP" | jq -r '.data.saveTemplate.id // empty')
if [[ -z "$TEMPLATE_ID" ]]; then
  echo "ERROR: template save failed" >&2
  exit 1
fi
upsert_id_in_env TEMPLATE_ID "$TEMPLATE_ID"
export TEMPLATE_ID

echo "==> Saving endpoint ($ENDPOINT_NAME -> $TEMPLATE_ID)"
INPUT=$(build_endpoint_input)
export INPUT MUTATION="EndpointInput" MUTATION_REQUIRED="1" FIELD="saveEndpoint"
QUERY=$(wrap_query)
RESP=$(call_api "$QUERY")
echo "$RESP" | jq .
NEW_ID=$(echo "$RESP" | jq -r '.data.saveEndpoint.id // empty')
if [[ -z "$NEW_ID" ]]; then
  echo "ERROR: endpoint save failed" >&2
  exit 1
fi
upsert_id_in_env ENDPOINT_ID "$NEW_ID"

echo
echo "Template ID: $TEMPLATE_ID"
echo "Endpoint ID: $NEW_ID"
echo "Endpoint URL: https://api.runpod.ai/v2/$NEW_ID"
echo "OpenAI-compat URL: https://api.runpod.ai/v2/$NEW_ID/openai/v1"
echo
echo "Test it: make test"
