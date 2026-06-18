#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${RUNPOD_API_KEY:?}"
: "${ENDPOINT_ID:?Run ./deploy.sh first}"

API="https://api.runpod.io/graphql"

QUERY=$(cat <<JSON
{"query":"query { myself { endpoints { id name workersMin workersMax idleTimeout gpuIds } } }"}
JSON
)

curl -fsS -X POST "$API" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$QUERY" | jq --arg id "$ENDPOINT_ID" '.data.myself.endpoints[] | select(.id == $id)'

echo
echo "Health URL: https://api.runpod.ai/v2/$ENDPOINT_ID/health"
echo "Live health check:"
curl -fsS "https://api.runpod.ai/v2/$ENDPOINT_ID/health" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" | jq .
