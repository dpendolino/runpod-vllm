#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${RUNPOD_API_KEY:?}"
: "${ENDPOINT_ID:?Run ./deploy.sh first}"

URL="https://api.runpod.ai/v2/$ENDPOINT_ID/openai/v1/chat/completions"

echo "Sending test prompt to $URL"
echo "(First request triggers cold start — expect 30-90s)"
echo

curl -fsS --connect-timeout 15 --max-time 180 "$URL" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL_NAME\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"In one sentence, what is vLLM?\"}
    ],
    \"max_tokens\": 100
  }" | jq .
