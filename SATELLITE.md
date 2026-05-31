# gitaday satellite — the oracle↔executor symbiosis

> The thing gitaday derived from first principles in March (`SYNTHESIS.md`),
> finally built. A resident local-model agent does the work; an external
> frontier model supervises. This is that diagram, deployed.

## The architecture

```
   ┌─────────────────────────────┐         ┌──────────────────────────────┐
   │  ORACLE (externality)       │ reviews │  EXECUTOR (resident)          │
   │  Claude — me, "meta-gitaday"│────────▶│  Hermes in the gitaday actor  │
   │  • designs experiments      │         │  • runs them autonomously     │
   │  • repairs prompts/skills   │◀────────│  • accumulates memory + skills│
   │  • hard reasoning           │ results │  • qwen3.5 (35B-A3B) local    │
   └─────────────────────────────┘         └──────────────────────────────┘
              not always on                        always on
```

This is `SYNTHESIS.md`'s conclusion verbatim: *a strong model designs/repairs;
a cheap persistent local model executes.* The independent ecosystem scout
re-derived the same split ("keep reflective mutation on Claude; use the local
32B for the bulk evaluation calls"). Two roads, one map.

## What's actually wired (Phase 1, 2026-05-31)

| Layer | Concretely |
|-------|-----------|
| **Boundary** | `gitaday` = non-admin macOS user (uid 505), zero sudo, opaque to `sam`. Built with `sysadminhelpers/envkit`. |
| **Identity** | samcloud user `gitaday` (groups core/services/work) + device `gitaday` (online, direct-ssh access target). |
| **Executor** | Hermes (NousResearch) installed via uv in `~gitaday/hermes-agent`. |
| **Inference** | `models-cs` gateway → `qwen3.5:35b-a3b-coding-nvfp4`, GPU-leased on demand. Provider `custom`, explicit token key. |
| **Proven** | raw + `hermes chat` smoke tests both returned clean completions on the local model. |

The build tooling and run-by-run outcomes live in `sysadminhelpers/` (hooks
`install-hermes.sh` / `wire-hermes.sh`; `RUNLOG.md` runs 0001–0005). This file
is the *why*; that repo is the *how* and *what-happened*.

## How I (the oracle) monitor gitaday-from-outside

No meta-dashboard — the universe is already the observability plane:

1. **Through samcloud** — `GET /devices/gitaday`, service health, `/events`,
   tickets. The registry shows liveness and lets the executor file tickets the
   oracle reads.
2. **Through the boundary** — `sysadminhelpers/envkit.sh ssh gitaday …` into
   `~/.hermes/` (session logs, memory, skills). Read-only inspection of what the
   executor did and learned.

## The loop (Phase 2+, planned)

1. **Substrate**: fold in `agentmemory` (local, native Hermes hooks) + `codegraph`
   (local code graph) — give the executor durable memory and cheap, accurate
   code navigation (the small-model failure-mode mitigation).
2. **Inner loop (autonomous)**: `SkillClaw` consolidates skills from real session
   data, unattended, low-risk.
3. **Outer loop (oracle-gated)**: `hermes-agent-self-evolution` (DSPy+GEPA) runs
   eval batches on the local model; **Claude authors/reviews the mutations** (the
   high-leverage step), never auto-commit. Human + oracle gate the PR.
4. **Work**: the executor runs the low-stakes / high-complexity experiments that
   are perfect for a local model — the kind gitaday always wanted to run overnight.

## Why this is low-stakes now (it wasn't in March)

- The **actor isolation** means a confused local model can't escalate or reach
  `sam`'s world — it's a poppable bubble (`envkit destroy gitaday`).
- The **35B coding model** clears the "7B wall" gitaday kept hitting: structured
  tool-calling and code gen are reliable enough to trust unsupervised on small tasks.
- The **oracle stays external** — strategy and self-modification never run blind
  on the weak model; Claude reviews before anything sticks.
