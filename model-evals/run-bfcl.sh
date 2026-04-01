#!/bin/bash
# Run BFCL (Berkeley Function Calling Leaderboard) against local model
# Usage: ./run-bfcl.sh [model_name]
#
# Prereqs: llama-server running on localhost:8000

set -e
cd "$(dirname "$0")"
source .venv/bin/activate

MODEL_NAME="${1:-local-qwen3-32b}"
export INSPECT_EVAL_MODEL="openai/local"
export OPENAI_BASE_URL="http://localhost:8000/v1"
export OPENAI_API_KEY="local"

echo "=== BFCL Eval: $MODEL_NAME ==="
echo "Target: $OPENAI_BASE_URL"
echo ""

# Run subset of BFCL categories that matter for agent use
# simple: basic single function calls
# multiple: choosing between multiple available functions
# parallel: calling multiple functions in one turn
# relevance: correctly refusing when no function matches
inspect eval inspect_evals/bfcl \
  --model openai/local \
  -T "categories=['simple','multiple','parallel','relevance']" \
  --log-dir "./results/bfcl/${MODEL_NAME}" \
  --max-connections 1 \
  2>&1

echo ""
echo "Results saved to ./results/bfcl/${MODEL_NAME}/"
