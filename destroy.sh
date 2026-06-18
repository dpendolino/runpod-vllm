#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${RUNPOD_API_KEY:?}"

API="https://api.runpod.io/graphql"

call_api() {
  curl -fsS -X POST "$API" \
    -H "Authorization: Bearer $RUNPOD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$1"
}

if [[ -z "${ENDPOINT_ID:-}" && -z "${TEMPLATE_ID:-}" ]]; then
  echo "Nothing to destroy — neither ENDPOINT_ID nor TEMPLATE_ID set in .env"
  exit 0
fi

read -rp "Delete endpoint=${ENDPOINT_ID:-none} and template=${TEMPLATE_ID:-none}? [y/N] " confirm
[[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "aborted"; exit 0; }

if [[ -n "${ENDPOINT_ID:-}" ]]; then
  echo "==> Deleting endpoint $ENDPOINT_ID"
  Q=$(python3 -c "import json; print(json.dumps({'query': 'mutation { deleteEndpoint(id: \"$ENDPOINT_ID\") }'}))")
  call_api "$Q" | jq .
  sed -i.bak 's|^ENDPOINT_ID=.*|ENDPOINT_ID=|' .env
fi

if [[ -n "${TEMPLATE_ID:-}" ]]; then
  echo "==> Deleting template $TEMPLATE_ID"
  Q=$(python3 -c "import json; print(json.dumps({'query': 'mutation { deleteTemplate(templateName: \"${ENDPOINT_NAME}-tmpl\") }'}))")
  call_api "$Q" | jq . || echo "(template delete failed — likely already gone)"
  sed -i.bak 's|^TEMPLATE_ID=.*|TEMPLATE_ID=|' .env
fi

rm -f .env.bak
echo "Done. IDs cleared from .env"
