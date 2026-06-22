# RunPod Serverless vLLM

Scripts to deploy, test, and tear down a serverless vLLM endpoint on RunPod.

## Prereqs

- RunPod account with credit ($10 minimum)
- API key from https://www.runpod.io/console/user/settings
- `jq`, `curl`, `python3` installed locally

## Setup

```bash
make init           # creates .env from template
$EDITOR .env        # add RUNPOD_API_KEY, HF_TOKEN
make deploy         # create the endpoint + run canary test
make test           # send a test prompt (cold start: 30-90s)
make chat           # interactive chat
make destroy        # tear it down when done
```

Run `make` (no args) for the full target list.

## Files

- `Makefile` — task runner (`make help` for targets)
- `.env.example` — config template
- `deploy.sh` — creates/updates the serverless endpoint (idempotent)
- `test.sh` — sends a sample prompt
- `chat.py` — interactive streaming chat (OpenAI SDK)
- `status.sh` — show endpoint config and health
- `destroy.sh` — deletes the endpoint

## Safeguards

These prevent runaway billing from worker crash loops (model fails to load,
worker restarts, bills GPU time, repeats).

- **`EXECUTION_TIMEOUT_MS`** — hard cap on request execution time (default
  600000ms = 10min). Workers stuck in a crash loop are killed instead of
  billing GPU time indefinitely. Set to 0 for no timeout.
- **`SPEND_LIMIT_ALERT`** — warns before deploying if your account balance is
  below this threshold (default $5). Set to 0 to disable.
- **Canary test** — `make deploy` automatically runs a test request with a 3min
  timeout. If the model can't load, you get a warning and a link to the worker
  logs immediately. Use `make deploy-skip-canary` to skip (CI/scripting).

## Costs

- Idle: $0
- Active: ~$1.10/hr per worker on RTX 4090 (serverless rate)
- Storage: free if you use the bundled image (model loads from HF on cold start)

## Privacy notes

See parent conversation. Same trust boundary as any cloud provider. RunPod can theoretically inspect VMs but doesn't train on your data.
