#!/bin/bash
# overnight.sh — Karpathy-style hill-climbing loop for Claw-Empire prompts
#
# Modifies: prompts.json (system prompt, routing hint)
# Measures: vibe-check eval pass rate (0-3)
# Budget:   5 min per iteration
# Memory:   git commit/revert + results.tsv
#
# Usage: ./overnight.sh [max_iterations]
# Default: loops forever (Ctrl+C to stop)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MAX_ITER="${1:-999999}"
RESULTS="results/overnight-results.tsv"
PROMPTS="prompts.json"
OLLAMA="http://localhost:11434"
CLAW_API="http://127.0.0.1:8790"
PROJECT_ID="02935290-0d63-4d29-b895-f31396dd661f"
EVAL_TIMEOUT=300  # 5 min per eval cycle
BRANCH="overnight-$(date +%Y%m%d-%H%M%S)"

mkdir -p results

# Initialize git branch for experiments
cd "$SCRIPT_DIR/.."
git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH" 2>/dev/null
cd "$SCRIPT_DIR"

# Header for results
if [ ! -f "$RESULTS" ]; then
  echo -e "iteration\ttimestamp\tcommit\tpass_rate\ttotal\tpassed\tfailed\tstatus\tdescription" > "$RESULTS"
fi

# ═══════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════

get_claw_session() {
  curl -s -c /tmp/claw-overnight.txt "$CLAW_API/api/auth/session" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('csrf_token',''))" 2>/dev/null
}

clean_tasks() {
  local csrf="$1"
  curl -s -b /tmp/claw-overnight.txt "$CLAW_API/api/tasks" 2>/dev/null | python3 -c "
import sys, json
for t in json.load(sys.stdin).get('tasks', []):
    print(t['id'])
" 2>/dev/null | while read -r tid; do
    curl -s -b /tmp/claw-overnight.txt -X DELETE "$CLAW_API/api/tasks/$tid" \
      -H "x-csrf-token: $csrf" > /dev/null 2>&1
  done
  # Clean worktrees
  cd /Users/sam/Documents/Projects/gitaday/claw-sandbox
  git worktree prune 2>/dev/null
  rm -rf .climpire-worktrees 2>/dev/null
  cd "$SCRIPT_DIR"
}

send_directive() {
  local csrf="$1"
  local content="$2"
  curl -s -b /tmp/claw-overnight.txt \
    -X POST "$CLAW_API/api/directives" \
    -H "Content-Type: application/json" \
    -H "x-csrf-token: $csrf" \
    -d "{\"content\": \"$content\", \"project_id\": \"$PROJECT_ID\"}" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('ok','false'))" 2>/dev/null
}

wait_for_terminal() {
  local timeout="$1"
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    local status=$(curl -s -b /tmp/claw-overnight.txt "$CLAW_API/api/tasks" 2>/dev/null | python3 -c "
import sys, json
tasks = [t for t in json.load(sys.stdin).get('tasks',[]) if t['status'] not in ('inbox',)]
if tasks:
    # Check if any non-inbox task reached terminal
    for t in tasks:
        if t['status'] in ('review','done','cancelled'):
            print('terminal')
            break
    else:
        print('running')
else:
    print('waiting')
" 2>/dev/null)
    if [ "$status" = "terminal" ]; then
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  return 1  # timeout
}

check_artifact() {
  local filename="$1"
  local pattern="$2"
  local path=$(find /Users/sam/Documents/Projects/gitaday/claw-sandbox -name "$filename" -not -path '*/.git/*' 2>/dev/null | head -1)
  if [ -n "$path" ] && grep -q "$pattern" "$path" 2>/dev/null; then
    echo "pass"
  elif [ -n "$path" ]; then
    echo "partial"
  else
    echo "fail"
  fi
}

run_eval_suite() {
  local csrf=$(get_claw_session)
  local passed=0
  local failed=0
  local total=3

  # Test 1: hello.py creation
  clean_tasks "$csrf"
  send_directive "$csrf" "Create hello.py that prints Hello from Claw-Empire. Dev coding task." > /dev/null
  wait_for_terminal $EVAL_TIMEOUT
  local t1=$(check_artifact "hello.py" "Hello")
  [ "$t1" = "pass" ] && passed=$((passed+1)) || failed=$((failed+1))

  # Test 2: README update
  clean_tasks "$csrf"
  send_directive "$csrf" "Update README.md to add an About section saying This is the Claw-Empire sandbox. Dev task." > /dev/null
  wait_for_terminal $EVAL_TIMEOUT
  local t2=$(check_artifact "README.md" "About")
  [ "$t2" = "pass" ] && passed=$((passed+1)) || failed=$((failed+1))

  # Test 3: math_utils.py
  clean_tasks "$csrf"
  send_directive "$csrf" "Create math_utils.py with a function called add that takes two numbers and returns their sum. Dev coding task." > /dev/null
  wait_for_terminal $EVAL_TIMEOUT
  local t3=$(check_artifact "math_utils.py" "def add")
  [ "$t3" = "pass" ] && passed=$((passed+1)) || failed=$((failed+1))

  clean_tasks "$csrf"
  echo "$passed $failed $total $t1 $t2 $t3"
}

ask_ollama_for_improvement() {
  local pass_rate="$1"
  local details="$2"

  # Use a temp file to avoid bash/python string escaping hell
  python3 - "$OLLAMA" "$PROMPTS" "$pass_rate" "$details" << 'PYEOF'
import sys, json, urllib.request

ollama_url = sys.argv[1]
prompts_path = sys.argv[2]
pass_rate = sys.argv[3]
details = sys.argv[4]

with open(prompts_path) as f:
    current = f.read()

prompt = f"""You are optimizing prompts for a multi-agent AI office simulator.
Current pass rate: {pass_rate}/3
Test results: {details}

Current prompts.json:
{current}

The system sends these prompts to a 7B language model (qwen2.5:7b) via Ollama.
The model needs to:
1. Route coding subtasks to department "dev" (not null)
2. Output code in fenced blocks with # filename: comments
3. Return valid JSON when asked for structured data

Suggest ONE small, specific change to the system_prompt or routing_hint that might improve the pass rate.
Return ONLY valid JSON in this exact format:
{{"field": "system_prompt or routing_hint", "new_value": "the improved text", "reasoning": "why this might help"}}"""

body = json.dumps({
    "model": "qwen2.5:7b",
    "messages": [{"role": "user", "content": prompt}],
    "stream": False,
    "format": "json"
}).encode()

try:
    req = urllib.request.Request(
        f"{ollama_url}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())
        content = data.get("message", {}).get("content", "{}")
        change = json.loads(content)
        print(json.dumps(change))
except Exception as e:
    print("{}")
PYEOF
}

apply_change() {
  local change="$1"
  python3 -c "
import json, sys
change = json.loads('$change')
if not change or 'field' not in change or 'new_value' not in change:
    sys.exit(1)
with open('$PROMPTS') as f:
    prompts = json.load(f)
field = change['field']
if field in prompts:
    prompts[field] = change['new_value']
    with open('$PROMPTS', 'w') as f:
        json.dump(prompts, f, indent=2)
    print(f'Applied: {field} updated')
    print(f'Reason: {change.get(\"reasoning\",\"none\")}')
else:
    print(f'Skipped: unknown field {field}')
    sys.exit(1)
" 2>/dev/null
}

# ═══════════════════════════════════════════
# Main loop
# ═══════════════════════════════════════════

echo "╔══════════════════════════════════════════╗"
echo "║  Overnight Hill-Climbing Loop            ║"
echo "║  Branch: $BRANCH              ║"
echo "║  Max iterations: $MAX_ITER                  ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "$(date): Starting. Ctrl+C to stop."
echo ""

BEST_PASS=0

for iter in $(seq 1 $MAX_ITER); do
  TS=$(date '+%Y-%m-%d %H:%M:%S')
  echo "━━━ Iteration $iter [$TS] ━━━"

  # Run eval suite
  echo "  [eval] Running 3 tests..."
  EVAL_RESULT=$(run_eval_suite)
  PASSED=$(echo "$EVAL_RESULT" | awk '{print $1}')
  FAILED=$(echo "$EVAL_RESULT" | awk '{print $2}')
  TOTAL=$(echo "$EVAL_RESULT" | awk '{print $3}')
  DETAILS=$(echo "$EVAL_RESULT" | awk '{print $4, $5, $6}')

  echo "  [result] $PASSED/$TOTAL passed ($DETAILS)"

  # Commit current state
  cd "$SCRIPT_DIR/.."
  git add "$SCRIPT_DIR/$PROMPTS" 2>/dev/null
  COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
  cd "$SCRIPT_DIR"

  # Decide: keep or try improvement
  if [ "$PASSED" -gt "$BEST_PASS" ]; then
    echo "  [keep] Improvement! $BEST_PASS → $PASSED"
    BEST_PASS=$PASSED
    STATUS="keep"
    cd "$SCRIPT_DIR/.."
    git add -A "$SCRIPT_DIR/$PROMPTS" 2>/dev/null
    git commit -m "overnight: pass rate $PASSED/$TOTAL ($DETAILS)" --allow-empty 2>/dev/null
    COMMIT=$(git rev-parse --short HEAD 2>/dev/null)
    cd "$SCRIPT_DIR"
  elif [ "$PASSED" -eq "$BEST_PASS" ]; then
    STATUS="same"
    echo "  [same] No change ($PASSED/$TOTAL)"
  else
    STATUS="revert"
    echo "  [revert] Regression $BEST_PASS → $PASSED, reverting"
    cd "$SCRIPT_DIR/.."
    git checkout -- "$SCRIPT_DIR/$PROMPTS" 2>/dev/null
    cd "$SCRIPT_DIR"
  fi

  # Log result
  DESC="t1=$(echo $DETAILS | awk '{print $1}') t2=$(echo $DETAILS | awk '{print $2}') t3=$(echo $DETAILS | awk '{print $3}')"
  echo -e "$iter\t$TS\t$COMMIT\t$PASSED/$TOTAL\t$TOTAL\t$PASSED\t$FAILED\t$STATUS\t$DESC" >> "$RESULTS"

  # If not perfect, ask Ollama for improvement
  if [ "$PASSED" -lt "$TOTAL" ]; then
    echo "  [improve] Asking Ollama for prompt suggestion..."
    CHANGE=$(ask_ollama_for_improvement "$PASSED" "$DETAILS")
    if [ -n "$CHANGE" ] && [ "$CHANGE" != "{}" ]; then
      echo "  [apply] $(apply_change "$CHANGE" 2>&1)"
    else
      echo "  [skip] No valid suggestion from model"
    fi
  else
    echo "  [perfect] 3/3 — nothing to improve!"
    # Still loop to verify stability
  fi

  echo ""
  # Brief pause between iterations
  sleep 5
done
