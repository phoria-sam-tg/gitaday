# Claw-Empire Eval: Runs 1-3 (Repair Arc)
**Date:** 2026-03-14
**Model:** qwen2.5:7b via Ollama (local, M1 Max)

## The Arc

Three test runs, three repairs. Same task: "Create hello.py that prints Hello from Claw-Empire."

### Run 0: Baseline (no patches)
- Pipeline runs end-to-end but model routes all subtasks to null (planning)
- Dev agents never execute, task marked "done" with zero artifacts
- **Root cause:** 7B model defaults to null department, delegation skips null targets

### Run 1: Prompt nudge + routing lock
**Patches:**
1. Added "IMPORTANT: coding tasks MUST go to dev" to routing prompt
2. Added department routing hints to system prompt
3. Locked routed subtasks — `AND target_department_id IS NULL` filter prevents re-routing

**Result:** 4 subtasks routed to dev and STAYED routed. 3 git worktrees created.
But dev agents produce text responses, not files — API provider is text-only.

### Run 2: Code block extraction
**Patch:** Added `extractAndWriteCodeFiles()` — scans API response for fenced code blocks,
extracts filenames, writes to worktree.

**Result:** 2 hello.py files created! But content was JSON (model's planning response)
not Python. Model embeds code inside `"code_snippet"` JSON fields instead of fenced blocks.
Added `# filename:` hint to system prompt.

### Run 3: JSON snippet extraction
**Patch:** Added fallback extraction from `"code_snippet"` JSON fields — small models
wrap code in structured plans rather than outputting raw blocks.

**Result:** `hello.py` with `print("Hello from Claw-Empire")` — clean, correct, extracted
from the model's JSON plan and written to the git worktree.

## Patches Applied (3 files)

### 1. `server/modules/workflow/agents/subtask-routing.ts`
- Added prompt hint: coding tasks MUST go to "dev"
- Added `AND target_department_id IS NULL` to reroute query (protect existing routing)

### 2. `server/modules/workflow/agents/providers/api-provider-tools.ts`
- Enhanced system prompt with code output format instructions + department routing hints
- Added `extractAndWriteCodeFiles()` function:
  - Extracts fenced code blocks (```python ... ```)
  - Extracts JSON `code_snippet` fields (small model fallback)
  - Detects filenames from comments, context, and prompt mentions
  - Writes extracted code to worktree directory
- Modified `launchApiProviderAgent` to capture response text and run extraction

## Patterns Discovered

### 1. Small models take the path of least resistance
The routing prompt said "set to null if stays in owner dept." 7B models interpret this as
permission to always use null. Fix: explicitly state what MUST go where.

### 2. Don't let second passes undo first passes
The orchestration runs multiple routing passes. The first pass correctly routed to dev,
but the second pass (review) reset everything to null. Fix: skip already-routed subtasks.

### 3. Meet the model where it is
7B models don't output clean fenced code blocks — they wrap code in JSON planning
structures with `code_snippet` fields. Instead of fighting this, extract from the format
the model naturally produces.

### 4. The "ceremony gap"
14-agent meetings, subtask delegation, git worktrees — all this ceremony for
`print("Hello from Claw-Empire")`. But the ceremony IS the product — it's testing
the orchestration pipeline, not the code output. The simple task reveals the system's
behavior under stress.

### 5. Verification gap
Tasks reach "review" and "done" with zero artifacts. The system trusts exit code 0
without checking if files were actually created. A proper verification gate would
check the worktree diff before marking done.

## System Health
- Ollama: loads on-demand, unloads after timeout, no memory waste
- Meeting logs: ~15-20 per directive (one per agent per phase)
- Worktree isolation: works correctly, branches created
- Total RAM for model: ~4.7GB when loaded, 0 when idle
- No crashes across all runs
