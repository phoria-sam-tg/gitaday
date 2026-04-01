#!/bin/bash
# Quick sanity eval — 10 practical tool-calling tests
# Tests the model's ability to: pick the right tool, format args, handle edge cases
# Usage: ./run-quick.sh [model_name]

set -e
cd "$(dirname "$0")"
source .venv/bin/activate

MODEL_NAME="${1:-local-qwen3-32b}"
export OPENAI_BASE_URL="http://localhost:8000/v1"
export OPENAI_API_KEY="local"

echo "=== Quick Tool-Call Eval: $MODEL_NAME ==="
python3 quick_eval.py --model "$MODEL_NAME" --output "./results/quick/${MODEL_NAME}.json"
