#!/bin/bash
# Claw-Empire Eval Harness
# Inspired by vibe-check + superpowers patterns
# Tests the directive → meeting → subtask → execution pipeline
# with a local 7B model (qwen2.5:7b via Ollama)
#
# Pattern: RED (expect failure) → DEBUG (root cause) → GREEN (repair) → DOCUMENT

set -euo pipefail

API="http://127.0.0.1:8790"
PROJECT_ID="02935290-0d63-4d29-b895-f31396dd661f"
RESULTS_DIR="$(dirname "$0")/results"
mkdir -p "$RESULTS_DIR"
RUN_ID="eval-$(date +%Y%m%d-%H%M%S)"
LOG="$RESULTS_DIR/${RUN_ID}.log"

# Auth
get_session() {
  CSRF=$(curl -s -c /tmp/claw-cookies.txt "$API/api/auth/session" | python3 -c "import sys,json; print(json.load(sys.stdin)['csrf_token'])")
  echo "$CSRF"
}

# Send directive and return message ID
send_directive() {
  local content="$1"
  curl -s -b /tmp/claw-cookies.txt \
    -X POST "$API/api/directives" \
    -H "Content-Type: application/json" \
    -H "x-csrf-token: $CSRF" \
    -d "{\"content\": \"$content\", \"project_id\": \"$PROJECT_ID\"}" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',{}).get('id','FAILED'))"
}

# Poll task status until terminal or timeout
wait_for_task() {
  local title_match="$1"
  local timeout_s="${2:-180}"
  local interval=10
  local elapsed=0

  while [ $elapsed -lt $timeout_s ]; do
    local result=$(curl -s -b /tmp/claw-cookies.txt "$API/api/tasks" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for t in d.get('tasks', []):
    title = t.get('title','')
    if '$title_match' in title.lower():
        status = t['status']
        tid = t['id']
        print(f'{status}|{tid}')
        break
" 2>/dev/null)

    local status=$(echo "$result" | cut -d'|' -f1)
    local task_id=$(echo "$result" | cut -d'|' -f2)

    if [ -z "$status" ]; then
      sleep $interval
      elapsed=$((elapsed + interval))
      continue
    fi

    echo "$status|$task_id"

    case "$status" in
      done|review|cancelled|failed)
        return 0
        ;;
    esac

    sleep $interval
    elapsed=$((elapsed + interval))
  done

  echo "timeout|"
  return 1
}

# Check if expected file exists in any worktree
check_artifact() {
  local filename="$1"
  find /Users/sam/Documents/Projects/gitaday/claw-sandbox -name "$filename" -not -path '*/.git/*' 2>/dev/null | head -1
}

# Collect subtask info for a task
get_subtasks() {
  curl -s -b /tmp/claw-cookies.txt "$API/api/subtasks" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for s in d.get('subtasks', d.get('items', [])):
    print(f'{s.get(\"status\",\"?\")}|{str(s.get(\"title\",\"?\"))[:80]}')
" 2>/dev/null
}

# Check Ollama activity
check_ollama() {
  curl -s http://localhost:11434/api/ps | python3 -c "
import sys, json
d = json.load(sys.stdin)
models = d.get('models', [])
print(f'{len(models)}')
" 2>/dev/null
}

# ═══════════════════════════════════════════════════
# EVAL CASES
# ═══════════════════════════════════════════════════

declare -a EVAL_NAMES=(
  "hello-script"
  "readme-update"
  "simple-function"
)

declare -a EVAL_DIRECTIVES=(
  "Create a file called hello.py with a Python script that prints 'Hello from Claw-Empire!' and the current date. Keep it simple - just the print statements, no classes."
  "Update the README.md to include a section called 'About' with one sentence: 'This is the Claw-Empire agent sandbox.'"
  "Create a file called math_utils.py with a function called 'add' that takes two numbers and returns their sum. Include a simple test at the bottom that prints add(2, 3)."
)

declare -a EVAL_ARTIFACTS=(
  "hello.py"
  "README.md"
  "math_utils.py"
)

declare -a EVAL_PATTERNS=(
  "Hello from Claw-Empire"
  "About"
  "def add"
)

# ═══════════════════════════════════════════════════
# RUN LOOP
# ═══════════════════════════════════════════════════

echo "╔════════════════════════════════════════════╗" | tee "$LOG"
echo "║  Claw-Empire Eval Run: $RUN_ID  ║" | tee -a "$LOG"
echo "╚════════════════════════════════════════════╝" | tee -a "$LOG"
echo "" | tee -a "$LOG"

CSRF=$(get_session)
echo "[auth] Session established" | tee -a "$LOG"

PASS=0
FAIL=0
TOTAL=${#EVAL_NAMES[@]}

for i in "${!EVAL_NAMES[@]}"; do
  name="${EVAL_NAMES[$i]}"
  directive="${EVAL_DIRECTIVES[$i]}"
  artifact="${EVAL_ARTIFACTS[$i]}"
  pattern="${EVAL_PATTERNS[$i]}"

  echo "" | tee -a "$LOG"
  echo "━━━ Test $((i+1))/$TOTAL: $name ━━━" | tee -a "$LOG"
  echo "[directive] $directive" | tee -a "$LOG"

  # Send directive
  msg_id=$(send_directive "$directive")
  echo "[sent] message=$msg_id" | tee -a "$LOG"

  # Wait for task to reach terminal state
  echo "[wait] Polling for task completion (timeout: 180s)..." | tee -a "$LOG"
  result=$(wait_for_task "$artifact" 180 || echo "timeout|")
  status=$(echo "$result" | cut -d'|' -f1)
  task_id=$(echo "$result" | cut -d'|' -f2)
  echo "[result] status=$status task=$task_id" | tee -a "$LOG"

  # Subtask summary
  echo "[subtasks]" | tee -a "$LOG"
  get_subtasks | while IFS='|' read -r st title; do
    echo "  [$st] $title" | tee -a "$LOG"
  done

  # Verification (superpowers pattern: evidence before claims)
  artifact_path=$(check_artifact "$artifact")
  if [ -n "$artifact_path" ]; then
    echo "[artifact] FOUND: $artifact_path" | tee -a "$LOG"
    # Pattern match
    if grep -q "$pattern" "$artifact_path" 2>/dev/null; then
      echo "[pattern] PASS: '$pattern' found in $artifact" | tee -a "$LOG"
      echo "[verdict] PASS" | tee -a "$LOG"
      PASS=$((PASS + 1))
    else
      echo "[pattern] FAIL: '$pattern' not found in $artifact" | tee -a "$LOG"
      echo "[content] $(cat "$artifact_path" 2>/dev/null | head -10)" | tee -a "$LOG"
      echo "[verdict] PARTIAL (file exists, wrong content)" | tee -a "$LOG"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "[artifact] NOT FOUND: $artifact" | tee -a "$LOG"
    echo "[verdict] FAIL (no artifact produced)" | tee -a "$LOG"
    FAIL=$((FAIL + 1))
  fi

  # Ollama state
  echo "[ollama] models_loaded=$(check_ollama)" | tee -a "$LOG"
done

# ═══════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════

echo "" | tee -a "$LOG"
echo "╔════════════════════════════════════════════╗" | tee -a "$LOG"
echo "║  RESULTS: $PASS/$TOTAL passed, $FAIL failed  ║" | tee -a "$LOG"
echo "╚════════════════════════════════════════════╝" | tee -a "$LOG"

# Log count
LOG_COUNT=$(ls /Users/sam/Documents/Projects/gitaday/claw-empire/logs/*.log 2>/dev/null | wc -l | tr -d ' ')
echo "[logs] $LOG_COUNT meeting/execution logs generated" | tee -a "$LOG"
echo "[run] Complete: $RESULTS_DIR/${RUN_ID}.log" | tee -a "$LOG"
