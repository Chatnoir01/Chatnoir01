#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="$ROOT/.models/npc/qwen2.5-0.5b-instruct-q4_k_m.gguf"
LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"
if [[ ! -f "$MODEL" ]]; then
  echo "Model missing; run tools/download_npc_llm.py first" >&2
  exit 1
fi
if ! command -v "$LLAMA_SERVER" >/dev/null 2>&1 && [[ ! -x "$LLAMA_SERVER" ]]; then
  echo "llama-server missing; set LLAMA_SERVER=/path/to/llama-server" >&2
  exit 1
fi
exec "$LLAMA_SERVER" \
  --model "$MODEL" \
  --alias grand-bruxelles-npc-qwen \
  --host 127.0.0.1 \
  --port 8089 \
  --ctx-size 2048 \
  --threads "${GB_NPC_LLM_THREADS:-4}" \
  --no-webui
