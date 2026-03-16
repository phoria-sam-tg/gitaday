# Gitaday Synthesis: Local AI Agent Stack
**Date:** 2026-03-14

Four parallel experiments, one through-line: **what does it take to run autonomous AI agents on local hardware?**

## The Experiments

| # | Project | What it tests | Verdict |
|---|---------|--------------|---------|
| 1 | **Claw-Empire** (3-run repair arc) | Multi-agent office sim with 7B model | Works after 3 patches — routing nudge, decision lock, code extraction |
| 2 | **Autoresearch** (Karpathy) | Autonomous experiment loops | Best patterns: hill-climbing git loop, fixed budget, program.md as source |
| 3 | **OpenCode** | CLI coding agent with local LLMs | Installs in 10s, chat works, tool calling breaks on 7B |
| 4 | **Vibe-check** | Test harness for agent evaluation | 2/3 evals passing, custom judges work, confirms patches hold |

## The 7B Wall

Every experiment hit the same wall: **7B models can chat and produce code, but structured tool calling / JSON schema compliance is unreliable.**

| Capability | 7B Performance |
|-----------|---------------|
| Free-form text generation | Good |
| Code generation (in response body) | Good |
| JSON with simple schema | Sometimes |
| JSON with complex schema (nested, enums) | Unreliable |
| Tool calling (structured arguments) | Breaks often |
| Multi-step reasoning in structured format | Poor |
| Department routing (pick from enum list) | Needs explicit nudging |

**Implication:** The scaffolding around the model must compensate. Don't fight the model — design the arena so the model's natural output format works.

## Patterns That Work

### 1. Nudge, Don't Enforce
Small models take the path of least resistance. Instead of complex schemas, add explicit hints:
- "coding tasks MUST go to dev" (not "pick from: dev, design, qa, null")
- "output code in fenced blocks with filename" (not "use tool_call with file_write")

### 2. Protect Good Decisions
If the model makes a correct decision on pass 1, don't let pass 2 undo it.
Our routing lock (`AND target_department_id IS NULL`) prevented re-routing.
Autoresearch's git keep/revert does the same — good commits stay on the branch.

### 3. Meet the Model Where It Is
7B models embed code in JSON `code_snippet` fields instead of fenced blocks.
Instead of retraining, extract from the format they naturally produce.
Same principle: if the model outputs plans with embedded code, parse the plans.

### 4. Fixed Budget + Single Metric (Karpathy)
Every attempt gets the same time/resources. One number decides keep/revert.
Makes all attempts directly comparable. Prevents runaway loops.
Applied to our eval: 180s timeout per directive, pass/fail on artifact existence.

### 5. Git as Memory (Karpathy)
No vector databases. No RAG. Just commits and branches.
Claw-Empire already does this (worktree per task, branch per agent).
Autoresearch does it (commit per experiment, revert on failure).
It's the right primitive for agent work.

### 6. program.md as Source Code (Karpathy)
The human's job is to design the arena, not write the code.
Superpowers skills are the same pattern — markdown files that define agent behavior.
The `.md` file is the primary artifact. Code is substrate.

### 7. Bounded Retry with Graceful Degradation
If an experiment crashes, read the trace, try to fix, move on after N attempts.
Don't infinite loop. Log the failure and advance.
Our eval harness does this: 180s timeout, then record the state and move on.

## The Stack (What We Built Today)

```
                    ┌─────────────────────┐
                    │    samtg.xyz DNS     │
                    │   (23 A records)     │
                    └────────┬────────────┘
                             │
                    ┌────────▼────────────┐
                    │   Caddy (port 8443) │
                    │   claw.samtg.xyz    │
                    │   tavern.samtg.xyz  │
                    │   exp.samtg.xyz     │
                    └────────┬────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼──────┐   ┌────────▼────────┐  ┌────────▼──────┐
│ Claw-Empire  │   │  SillyTavern    │  │  Shadowbroker │
│ :8800/:8790  │   │  :3005          │  │  :3002        │
│ 14 agents    │   │  personas/chat  │  │  OSINT        │
└───────┬──────┘   └────────┬────────┘  └───────────────┘
        │                   │
        └─────────┬─────────┘
                  │
         ┌────────▼────────┐
         │  Ollama (:11434)│
         │  qwen2.5:7b     │
         │  llava:7b       │
         │  (on-demand)    │
         └────────┬────────┘
                  │
         ┌────────▼────────┐
         │ BitNet 2B (:8081│
         │ 1-bit, 1.1GB   │
         │ always-resident │
         └─────────────────┘
```

## Eval Infrastructure

```
vibe-check harness
  ├── basic-directive.eval.json  → PASS (task creation)
  ├── routing-to-dev.eval.json   → PASS (department routing)
  └── code-gen-hello.eval.json   → PARTIAL (artifact creation, timing-sensitive)

Custom judges: task-created, artifact-exists, department-routing, task-status
```

## What's Next

### Immediate
- [x] Run overnight hill-climbing loop (2 runs, peak 2/3 pass)
- [ ] Run the loop with Claude as improvement oracle (7B executes, Claude suggests)
- [ ] Set up OpenCode as Claw-Empire CLI provider (switch agents from api to opencode)
- [ ] Add verification gate to Claw-Empire (check worktree diff before marking done)

### Medium-term
- [ ] Build the port registry (samcloud Issue #6)
- [ ] Create /add-service skill for safe Caddy + DNS enrollment
- [ ] Try 5090 gateway with fixed streaming (32B for both execution and improvement)
- [ ] Explore Hermes Agent persistent memory patterns

### The Big Idea
Compose the hill-climbing git loop (autoresearch) with the multi-agent office (Claw-Empire)
and the test harness (vibe-check): agents propose changes, vibe-check evaluates, git keeps
or reverts, loop overnight. The arena runs itself.

## Overnight Results (2026-03-16)

**We ran the loop. Here's what we learned.**

The Karpathy pattern works mechanically — hill-climbing + git keep/revert is solid. Over 12
iterations, the system correctly kept improvements and reverted regressions. Peak: 2/3 tests
passing (hello.py + math_utils.py created with correct content by the 14-agent office sim).

But the self-improvement loop failed: **7B can't improve its own prompts.** Every suggestion
from qwen2.5:7b made things worse. The model can write code (executor role) but can't reason
about prompt engineering (oracle role).

### The Two-Model Architecture

This reveals the right architecture for local agent stacks:

```
┌─────────────────────┐     ┌──────────────────────┐
│   Oracle Model      │     │   Executor Model     │
│   (Claude / 32B+)   │     │   (7B / local)       │
│                     │     │                      │
│   • Prompt design   │────▶│   • Code generation  │
│   • Strategy        │     │   • Task execution   │
│   • Improvement     │     │   • Meeting responses │
│     suggestions     │     │   • JSON formatting  │
└─────────────────────┘     └──────────────────────┘
         ▲                           │
         │         ┌─────────┐       │
         └─────────│  Eval   │◀──────┘
                   │ Harness │
                   └─────────┘
```

The oracle doesn't need to run continuously — it reviews results and suggests changes
between iterations. The executor runs the actual workload. This maps perfectly to:
- **Overnight:** Claude reviews morning results, suggests 1-2 changes, 7B executes all day
- **Realtime:** 32B on 5090 as oracle (when gateway streaming is fixed), 7B as executor
- **Hybrid:** Claude for strategy, local models for execution, vibe-check as the judge
