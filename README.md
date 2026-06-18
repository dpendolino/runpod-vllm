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
make deploy         # create the endpoint
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

## Costs

- Idle: $0
- Active: ~$0.00019/sec on RTX 4090 (~$0.68/hr only when running)
- Storage: free if you use the bundled image (model loads from HF on cold start)

## Privacy notes

See parent conversation. Same trust boundary as any cloud provider. RunPod can theoretically inspect VMs but doesn't train on your data.
