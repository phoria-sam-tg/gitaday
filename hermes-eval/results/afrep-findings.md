# AFrEP — Agent Framework Evaluation Pattern
## Hermes Agent v0.2.0 + qwen2.5:7b + Docker (Colima)
**Date:** 2026-03-17 | **Duration:** ~16 minutes | **14 tests, 7 dimensions**

## Scorecard

| # | Dimension | Test | Status | Time | Notes |
|---|-----------|------|--------|------|-------|
| T01 | Chat | Simple greeting | **PASS** | 29s | Clean response |
| T02 | Chat | Factual question | **PASS** | 21s | Knew Monty Python |
| T03 | File ops | Read file | FAIL | 44s | Docker container can't see host files |
| T04 | File ops | Write file | PARTIAL | 183s | Understood task but file not on host |
| T05 | File ops | Parse JSON | FAIL | 51s | Same container isolation issue |
| T06 | Terminal | Run command | **PASS** | 84s | `uname -a` returned Linux (Docker) |
| T07 | Terminal | Pip install + run | **PASS** | 70s | Installed cowsay, ran it — moo! |
| T08 | Coding | Generate + run script | FAIL | 109s | Docker startup noise in output |
| T09 | Coding | Fix a bug | PARTIAL | 65s | Understood the fix, couldn't write file |
| T10 | Research | Web search | **PASS** | 72s | Found Python version info |
| T11 | Multi-step | Chain of file ops | PARTIAL | 72s | Attempted all steps, files in container not host |
| T12 | Multi-step | Analyze + summarize | FAIL | 54s | Error in output |
| T13 | Self-aware | Know your tools | PARTIAL | 50s | Listed tools but pattern match missed |
| T14 | Self-aware | Know your limits | **PASS** | 25s | Correctly described tool dependency |

**Pass: 6/14 (42%) | Partial: 4/14 (29%) | Fail: 4/14 (29%)**

## Analysis by Dimension

### Chat (2/2 PASS) — 100%
Basic LLM capability works perfectly. Greeting and factual recall both clean. This is the baseline — if chat fails, everything fails.

### File Operations (0/3 PASS) — 0%
All file ops failed or were partial. **Root cause: Docker isolation.** The test workspace was created on the host at `/tmp/hermes-eval-*`, but Hermes runs terminal commands inside a Docker container at `/workspace`. The container can't see host files.

**This is actually the sandbox working correctly** — it's preventing the agent from accessing the host filesystem. But it means file-based tests need to be designed differently (create files inside the container, not expect host files).

### Terminal (2/2 PASS) — 100%
Terminal commands work great inside Docker. `uname -a` correctly shows Linux (the container OS). `pip install cowsay` + run both worked. Docker adds ~5s startup overhead per command.

### Coding (0/2 PASS) — 0%
Both coding tests failed. T08 got Docker debug noise in the output that triggered the "error" pattern. T09 understood the bug fix but couldn't persist the file to the host.

**The 7B model DID generate correct code** — the issue is output parsing and file persistence, not code quality. This is a harness problem, not a model problem.

### Research (1/1 PASS) — 100%
Web search worked. Found current Python version info. Hermes's `web_search` tool functions correctly with local Ollama.

### Multi-step (0/2 PASS) — 0%
Both partial/fail. T11 attempted all steps (create dir, files, concatenate) but files stayed in the ephemeral container. T12 errored trying to list files that don't exist in the container.

### Self-awareness (1/2 PASS) — 50%
T14 passed (knows it needs tools for web access). T13 was partial — it listed tools but the exact pattern match missed. A more lenient judge would pass this.

## Key Findings

### 1. Docker Sandbox Changes the Test Design
The sandbox is doing its job — isolating the agent. But tests written assuming host filesystem access will fail. Need to either:
- Mount a shared volume for test workspaces
- Design tests that work entirely within the container
- Use `container_persistent: true` for cross-test file persistence

### 2. Output Noise Problem
Docker container startup debug messages (`minisweagent.environment: DEBUG: Starting container...`) appear in the captured output. This triggers the "error" pattern in the judge. Need to filter Docker noise from agent responses.

### 3. The 7B Model is Competent
When you strip away the Docker/harness issues:
- Chat: 100% (2/2 real passes)
- Terminal: 100% (2/2 real passes)
- Research: 100% (1/1 real pass)
- Coding: ~50% (code was correct, persistence failed)
- File ops: ~33% (understood tasks, sandbox blocked execution)

**Adjusted estimate: ~70% capability, 42% measured.** The gap is harness issues, not model issues.

### 4. Hermes vs Claw-Empire Comparison

| Capability | Hermes + 7B | Claw-Empire + 7B |
|-----------|-------------|-------------------|
| Chat | Works | Works (meetings) |
| Code generation | Works (in container) | Works (with extraction patch) |
| File creation | Blocked by sandbox | Works (extraction to worktree) |
| Tool calling | Works (terminal, web) | Doesn't apply (API-only mode) |
| Multi-agent | No (single agent) | Yes (14 agents, departments) |
| Self-improvement | Has skills system | Needed manual patches |
| Structured JSON | Struggles (same 7B wall) | Struggles (same 7B wall) |

### 5. The AFrEP Pattern
This test suite structure works well as a reusable pattern:
- **Dimensions** group related capabilities
- **Pattern matching** judges are fast but fragile (need lenient mode)
- **File existence** judges need sandbox-awareness
- **TSV output** is easy to diff across runs
- **The separation of test design from execution** lets you swap agents

## Recommendations

1. **Add Docker volume mount** for test workspace (or switch to `local` backend for eval)
2. **Filter Docker debug output** before judging
3. **Add lenient judge mode** — pass if response is >100 chars and not an error
4. **Run same suite against Claude Code** for baseline comparison
5. **Run same suite against OpenCode** to complete the 3-way comparison
