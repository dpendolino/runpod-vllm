#!/usr/bin/env python3
import os
import sys
from pathlib import Path

try:
    from openai import OpenAI
except ImportError:
    sys.exit("pip install openai")


def load_env(path: Path) -> dict:
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env


env = load_env(Path(__file__).parent / ".env")
api_key = env.get("RUNPOD_API_KEY") or os.environ.get("RUNPOD_API_KEY")
endpoint_id = env.get("ENDPOINT_ID")
model = env.get("MODEL_NAME")

if not endpoint_id:
    sys.exit("ENDPOINT_ID not set in .env — run ./deploy.sh first")

client = OpenAI(
    api_key=api_key,
    base_url=f"https://api.runpod.ai/v2/{endpoint_id}/openai/v1",
)

print(f"Chat with {model} (Ctrl-C to exit)")
print("First message may take 30-90s if cold")
messages = []
try:
    while True:
        user = input("\nyou> ").strip()
        if not user:
            continue
        messages.append({"role": "user", "content": user})
        stream = client.chat.completions.create(
            model=model,
            messages=messages,
            stream=True,
        )
        print("ai>  ", end="", flush=True)
        reply = ""
        for chunk in stream:
            delta = chunk.choices[0].delta.content or ""
            reply += delta
            print(delta, end="", flush=True)
        print()
        messages.append({"role": "assistant", "content": reply})
except KeyboardInterrupt:
    print("\nbye")
