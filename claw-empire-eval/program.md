# Overnight Hill-Climbing Loop

Inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

## The Arena

| Component | Autoresearch | This |
|-----------|-------------|------|
| Mutable file | `train.py` | `prompts.json` |
| Immutable harness | `prepare.py` | `run-eval.sh` + vibe-check evals |
| Metric | `val_bpb` (lower=better) | eval pass rate (higher=better) |
| Agent | Claude Code / Codex | Ollama qwen2.5:7b |
| Budget | 5 min training | 5 min per eval cycle |
| Memory | git branch + `results.tsv` | git branch + `results/overnight-results.tsv` |

## How It Works

```
LOOP FOREVER:
1. Run 3 eval tests against Claw-Empire
   - hello.py creation (code gen)
   - README.md update (file modification)
   - math_utils.py creation (function + test)
2. Count passing tests (0-3)
3. If improved → git commit (keep)
   If same → note, continue
   If worse → git revert to last good
4. Ask Ollama to suggest ONE prompt improvement
5. Apply the suggestion to prompts.json
6. Go to 1
```

## Running

```bash
# Prerequisites: Claw-Empire running on :8790, Ollama on :11434
cd claw-empire-eval
./overnight.sh        # Loop forever
./overnight.sh 10     # Run 10 iterations
```

## Results

Tab-separated log at `results/overnight-results.tsv`:
```
iteration  timestamp            commit   pass_rate  total  passed  failed  status  description
1          2026-03-14 23:00:00  abc1234  1/3        3      1       2       keep    t1=pass t2=fail t3=fail
2          2026-03-14 23:15:00  def5678  2/3        3      2       1       keep    t1=pass t2=pass t3=fail
```

## What Gets Modified

Only `prompts.json` — two fields:
- `system_prompt`: The system message sent to the model for all API provider calls
- `routing_hint`: The extra instruction added to the subtask routing prompt

The eval harness, judges, and Claw-Empire code are immutable during the run.

## Stopping

Ctrl+C. The git branch preserves all experiments. Results.tsv is untracked.

## After the Run

```bash
# See what changed
git log --oneline overnight-*
git diff main..overnight-* -- claw-empire-eval/prompts.json

# Check results
cat claw-empire-eval/results/overnight-results.tsv | column -t -s$'\t'
```
