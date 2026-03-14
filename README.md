# gitaday

A playground for exploring interesting open-source repos — clone, assess, set up, pull apart, sometimes deploy.

## Structure

```
gitaday/
├── README.md              ← you are here
├── NOTES.md               ← per-project assessment notes (7 projects documented)
├── SYNTHESIS.md            ← cross-project synthesis and patterns
├── SAMCLOUD-WORK.md        ← infra work requests (port registry, routing)
├── repos.json              ← manifest of all cloned repos
├── claw-empire-eval/       ← eval harness + results for Claw-Empire
│   ├── run-eval.sh         ← bash eval runner
│   ├── results/            ← run findings (3-run repair arc)
│   └── vibe-check/         ← vibe-check config + eval cases
└── [cloned repos]/         ← .gitignored, see repos.json for URLs
```

Cloned repos are listed in `repos.json` with upstream URLs. They're .gitignored because they contain local modifications (patches, configs) that are experiment-specific. The scaffolding — notes, synthesis, eval results — is what gets tracked.

## What's Running

| Service | Port | URL | Model |
|---------|------|-----|-------|
| Ollama | 11434 | localhost only | qwen2.5:7b, llava:7b |
| BitNet 2B | 8081 | localhost only | bitnet-b1.58-2B-4T (1-bit) |
| Claw-Empire | 8800/8790 | claw.samtg.xyz | 14 agents via Ollama |
| SillyTavern | 3005 | tavern.samtg.xyz | Ollama backend |
| Shadowbroker | 3002 | exp.samtg.xyz/osint | — |

## Research Arc (2026-03-14)

Four parallel experiments exploring local AI agent stacks:

1. **Claw-Empire** — multi-agent office sim patched for 7B models (3-run repair arc)
2. **Autoresearch** (Karpathy) — autonomous ML experiment loop patterns
3. **OpenCode** — open-source CLI coding agent with Ollama
4. **Vibe-check** — test harness for evaluating agent pipelines

Key finding: **7B models can do the work if the scaffolding compensates** — prompt nudges, decision locks, format extraction, fixed budgets, git rollback.

See [SYNTHESIS.md](SYNTHESIS.md) for the full cross-project analysis.

## Repo Manifest

See [repos.json](repos.json) for all 14 cloned repos with URLs, categories, and status. To reproduce:

```bash
cat repos.json | python3 -c "
import sys, json
for r in json.load(sys.stdin)['repos']:
    print(f\"git clone --depth 1 {r['url']} {r['dir']}\")
"
```
