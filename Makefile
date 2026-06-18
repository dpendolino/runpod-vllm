.PHONY: help init deploy test chat status logs destroy clean check

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

help:
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Copy .env.example to .env (won't overwrite)
	@if [[ -f .env ]]; then \
		echo ".env already exists — not overwriting"; \
	else \
		cp .env.example .env && echo "Created .env — edit it before running 'make deploy'"; \
	fi

check: ## Verify .env is filled in
	@if [[ ! -f .env ]]; then echo "Run 'make init' first"; exit 1; fi
	@set -a; source .env; set +a; \
		missing=""; \
		for v in RUNPOD_API_KEY MODEL_NAME ENDPOINT_NAME GPU_IDS; do \
			[[ -n "$${!v:-}" ]] || missing="$$missing $$v"; \
		done; \
		if [[ -n "$$missing" ]]; then echo "Missing in .env:$$missing"; exit 1; fi; \
		echo "Config OK"

deploy: check ## Create or update the serverless endpoint
	@./deploy.sh

test: ## Send a test prompt (cold start: 30-90s)
	@./test.sh

chat: ## Interactive streaming chat
	@test -d .venv || (python3 -m venv .venv && .venv/bin/pip install -q openai); \
		.venv/bin/python3 chat.py

status: ## Show endpoint config and live health
	@./status.sh

logs: ## Open RunPod console for this endpoint (Workers tab has logs)
	@set -a; source .env; set +a; \
		[[ -n "$$ENDPOINT_ID" ]] || { echo "No ENDPOINT_ID — run 'make deploy' first"; exit 1; }; \
		url="https://console.runpod.io/serverless/$$ENDPOINT_ID"; \
		echo "$$url"; \
		command -v xdg-open >/dev/null && xdg-open "$$url" || true

destroy: ## Delete the endpoint (prompts for confirmation)
	@./destroy.sh

clean: ## Remove .env, .venv, and any local artifacts (DANGEROUS)
	@read -rp "Delete .env and .venv? This loses ENDPOINT_ID. [y/N] " c && [[ "$$c" == "y" ]] && rm -rf .env .env.bak .venv || echo "aborted"
