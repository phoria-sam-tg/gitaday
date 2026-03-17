#!/bin/bash
# AFrEP — Agent Framework Evaluation Pattern
# Tests Hermes Agent across capability dimensions
#
# Dimensions:
#   1. Basic chat (no tools)
#   2. File operations (read/write/patch)
#   3. Terminal commands (bash execution)
#   4. Coding (generate + run)
#   5. Research (web search + synthesis)
#   6. Multi-step reasoning
#   7. Memory persistence
#   8. Self-improvement (skill creation)
#
# Each test: send query → capture output → judge pass/fail → log result

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

RUN_ID="afrep-$(date +%Y%m%d-%H%M%S)"
LOG="$RESULTS_DIR/${RUN_ID}.log"
TSV="$RESULTS_DIR/${RUN_ID}.tsv"
WORKSPACE="/tmp/hermes-eval-${RUN_ID}"
mkdir -p "$WORKSPACE"

# Create a test file for read tests
echo "Hello from the test workspace." > "$WORKSPACE/test-input.txt"
echo '{"name": "Sam", "role": "engineer"}' > "$WORKSPACE/profile.json"

HERMES="hermes chat -Q -q"
PASS=0
FAIL=0
PARTIAL=0
TOTAL=0
TIMEOUT_S=120

echo -e "test_id\tdimension\tname\tstatus\tduration_s\tdetails" > "$TSV"

log() {
  echo "$@" | tee -a "$LOG"
}

run_test() {
  local test_id="$1"
  local dimension="$2"
  local name="$3"
  local query="$4"
  local judge_pattern="$5"  # grep pattern for pass
  local judge_file="${6:-}"  # optional: check this file exists

  TOTAL=$((TOTAL + 1))
  log ""
  log "━━━ [$test_id] $dimension: $name ━━━"
  log "  Query: ${query:0:80}..."

  local start=$(date +%s)

  # Run Hermes with timeout
  local output
  output=$(cd "$WORKSPACE" && $HERMES "$query" 2>&1) || true

  local end=$(date +%s)
  local duration=$((end - start))

  log "  Duration: ${duration}s"
  log "  Output (first 200): ${output:0:200}"

  # Judge
  local status="fail"
  local details=""

  # Check for output at all
  if [ -z "$output" ]; then
    details="empty response"
  elif echo "$output" | grep -qi "error\|traceback\|exception\|refused"; then
    details="error in output"
  else
    # Pattern match
    if [ -n "$judge_pattern" ] && echo "$output" | grep -qi "$judge_pattern"; then
      status="pass"
      details="pattern matched: $judge_pattern"
    elif [ -n "$judge_pattern" ]; then
      # Check if it's a reasonable response even without exact match
      local len=${#output}
      if [ $len -gt 50 ]; then
        status="partial"
        details="response present ($len chars) but pattern not matched"
      else
        details="short response ($len chars), pattern not matched"
      fi
    fi

    # File existence check
    if [ -n "$judge_file" ]; then
      if [ -f "$WORKSPACE/$judge_file" ] || [ -f "$judge_file" ]; then
        if [ "$status" = "fail" ]; then
          status="partial"
        fi
        details="${details}; file exists: $judge_file"
      else
        if [ "$status" = "pass" ]; then
          status="partial"
        fi
        details="${details}; file NOT found: $judge_file"
      fi
    fi
  fi

  case "$status" in
    pass) PASS=$((PASS + 1)); log "  ✓ PASS — $details" ;;
    partial) PARTIAL=$((PARTIAL + 1)); log "  ~ PARTIAL — $details" ;;
    fail) FAIL=$((FAIL + 1)); log "  ✗ FAIL — $details" ;;
  esac

  echo -e "${test_id}\t${dimension}\t${name}\t${status}\t${duration}\t${details}" >> "$TSV"
}

# ═══════════════════════════════════════════════════
# TEST SUITE
# ═══════════════════════════════════════════════════

log "╔════════════════════════════════════════════════════╗"
log "║  AFrEP — Agent Framework Evaluation Pattern       ║"
log "║  Run: $RUN_ID                          ║"
log "║  Agent: Hermes v0.2.0 + qwen2.5:7b (Ollama)      ║"
log "║  Sandbox: Docker (Colima)                         ║"
log "╚════════════════════════════════════════════════════╝"
log ""
log "Workspace: $WORKSPACE"
log "Started: $(date)"

# --- Dimension 1: Basic Chat ---
run_test "T01" "chat" "Simple greeting" \
  "Say hello in one sentence. Do not use any tools." \
  "hello\|Hello\|Hi\|hey" ""

run_test "T02" "chat" "Factual question" \
  "What programming language is Python named after? Answer in one sentence, no tools." \
  "Monty\|comedy\|monty" ""

# --- Dimension 2: File Operations ---
run_test "T03" "file-ops" "Read file" \
  "Read the file test-input.txt in the current directory and tell me what it says." \
  "Hello from the test\|test workspace" ""

run_test "T04" "file-ops" "Write file" \
  "Create a file called greeting.txt containing the text: Hermes was here." \
  "creat\|writ\|greeting" "greeting.txt"

run_test "T05" "file-ops" "Parse JSON" \
  "Read profile.json and tell me the person's name and role." \
  "Sam\|engineer" ""

# --- Dimension 3: Terminal Commands ---
run_test "T06" "terminal" "Run command" \
  "Run 'uname -a' and show me the output." \
  "Linux\|Darwin\|linux" ""

run_test "T07" "terminal" "Pip install" \
  "Install the 'cowsay' Python package and then run: python3 -c \"import cowsay; cowsay.cow('moo')\"" \
  "moo\|cow\|___" ""

# --- Dimension 4: Coding ---
run_test "T08" "coding" "Generate script" \
  "Create a Python script called fib.py that prints the first 10 Fibonacci numbers, then run it." \
  "1.*1.*2.*3.*5\|fibonacci\|Fibonacci" "fib.py"

run_test "T09" "coding" "Fix a bug" \
  "Create a file called buggy.py with this content: def add(a, b): return a - b. Then fix the bug so it actually adds." \
  "fix\|correct\|return a + b\|patched" "buggy.py"

# --- Dimension 5: Research ---
run_test "T10" "research" "Web search" \
  "What is the latest version of Python released in 2026? Search the web if needed." \
  "3\.\|python\|Python" ""

# --- Dimension 6: Multi-step ---
run_test "T11" "multi-step" "Chain of operations" \
  "Create a directory called 'chain-test', inside it create three files: a.txt containing 'alpha', b.txt containing 'beta', c.txt containing 'gamma'. Then concatenate them all into combined.txt." \
  "alpha.*beta.*gamma\|combined\|concatenat" "chain-test/combined.txt"

run_test "T12" "multi-step" "Analyze and summarize" \
  "List all .txt files in the current directory, count them, and write a summary to report.txt with the count and filenames." \
  "report\|summar\|files" "report.txt"

# --- Dimension 7: Self-awareness ---
run_test "T13" "self-aware" "Know your tools" \
  "What tools do you have available? List the main categories." \
  "terminal\|file\|web\|search\|tool" ""

run_test "T14" "self-aware" "Know your limits" \
  "Can you access the internet directly, or do you need to use a tool? Explain briefly." \
  "tool\|web_search\|web_extract\|cannot\|need" ""

# ═══════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════

log ""
log "╔════════════════════════════════════════════════════╗"
log "║  RESULTS                                          ║"
log "║  Pass: $PASS  Partial: $PARTIAL  Fail: $FAIL  Total: $TOTAL        ║"
log "╚════════════════════════════════════════════════════╝"
log ""
log "Pass rate: $PASS/$TOTAL ($(( PASS * 100 / TOTAL ))%)"
log "Partial rate: $PARTIAL/$TOTAL"
log "Results: $TSV"
log "Full log: $LOG"
log "Completed: $(date)"

# Cleanup
# rm -rf "$WORKSPACE"  # Keep for inspection

echo ""
echo "Results saved to: $TSV"
cat "$TSV" | column -t -s$'\t'
