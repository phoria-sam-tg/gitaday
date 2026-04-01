# Samcloud Work Requests

## OPEN: Central Port & Route Registry
**Filed:** 2026-03-14
**Priority:** High
**Triggered by:** SillyTavern (port 3005) overwrote yoto.samtg.xyz (port 3004) during gitaday setup

### Issue Report
- Port 3004 was allocated to `yoto.samtg.xyz` (Yoto Factory) in the live Caddyfile
- SillyTavern was assigned port 3004 without checking existing allocations
- Result: all traffic to yoto.samtg.xyz hit SillyTavern instead of Yoto Factory
- No mechanism exists to prevent this — ports are claimed ad-hoc across sessions

### Additional Risks Found
- Port 3003 has an unidentified Next.js v16 process running — no Caddy route, no record of what it is
- exp.samtg.xyz handle blocks are added manually with no validation
- Multiple Claude sessions or scripts could edit Caddyfile simultaneously (last-write-wins)
- No dry-run or rollback capability for Caddy changes

### Proposed Solution
A `ports.json` registry + enrollment script with:
1. **Canonical registry** at `/var/lib/caddy/ports.json` — all port allocations with service name, owner, date
2. **Port ranges** — web 3000-3099, API 8700-8899, tunnels 18000-18099
3. **flock-based locking** — parallel-safe atomic read-claim-write
4. **Triple-check on enroll** — registry + Caddyfile parse + live `lsof` scan
5. **Append-only Caddy edits** — never rewrite/delete existing handle blocks
6. **`caddy validate`** before reload — abort if config is invalid
7. **Claude skill** (`/exp-add`) — safe, dry-run-capable, testable from any session
8. **Audit log** — who claimed what port, when, from which session

### Current Port Map (2026-03-14)
| Port | Service | Caddy Route | Owner |
|------|---------|-------------|-------|
| 3000 | Console | hme.samtg.xyz | samcloud |
| 3001 | srv | srv.samtg.xyz | samcloud |
| 3002 | Shadowbroker | exp.samtg.xyz/osint | gitaday |
| 3003 | ??? (Next.js v16) | none | unknown |
| 3004 | Yoto Factory | yoto.samtg.xyz | samcloud |
| 3005 | SillyTavern | exp.samtg.xyz/tavern (broken) | gitaday |
| 3006 | KittenTTS | exp.samtg.xyz/tts | gitaday |
| 3007 | Higgs Audio v2 | exp.samtg.xyz/voice | gitaday |
| 3008 | Pascal Editor | exp.samtg.xyz/pascal | gitaday |
| 8000 | llama-server (Qwen3-32B Q6_K) | none (local only) | gitaday |
| 8188 | ComfyUI (SDXL) | none (local only) | gitaday |
| 8081 | BitNet llama-server | none (local only) | gitaday |
| 8443 | Caddy HTTPS | — | samcloud |
| 8765 | Splat converter | splat.samtg.xyz | samcloud |
| 8790 | Claw-Empire API | none yet | gitaday |
| 8800 | Claw-Empire frontend | none yet | gitaday |
| 11434 | Ollama | none (local only) | samcloud |
| 18003 | nerfstudio API tunnel | spl.samtg.xyz | samcloud |
| 18004 | ML pipeline tunnel | mlp.samtg.xyz | samcloud |
| 18005 | splat dev tunnel | spl-dev.samtg.xyz | samcloud |
| 18006 | viser tunnel | ns.samtg.xyz | samcloud |
| 18007 | 4DGS tunnel | dgs.samtg.xyz | samcloud |
| 21118-21119 | RustDesk | rdk.samtg.xyz | samcloud |

---

## OPEN: Identify Port 3003 Process
**Filed:** 2026-03-14
**Priority:** Medium

Unknown Next.js v16 process (PID 32815) listening on port 3003 with no Caddy route. Need to identify what this is, whether it should be registered, and if it needs a route.

---

## OPEN: Fix exp.samtg.xyz/tavern Route
**Filed:** 2026-03-14
**Priority:** Low

SillyTavern doesn't support basePath so the `/tavern` prefix strip approach only serves the initial HTML — all JS/CSS/image assets break. Options:
1. Give SillyTavern its own subdomain (tavern.samtg.xyz)
2. Accept it's local-only (localhost:3005) and remove the broken exp route
3. Look for a SillyTavern basePath PR/config option

---

## OPEN: Add Claw-Empire to exp.samtg.xyz
**Filed:** 2026-03-14
**Priority:** Medium

Claw-Empire (frontend :8800, API :8790) needs an exp route. Same basePath challenge as SillyTavern — it's a Vite SPA. May need its own subdomain or a working asset rewrite strategy.

---

## OPEN: Deploy KittenTTS Web Demo
**Filed:** 2026-03-20
**Priority:** Medium

KittenTTS (github.com/KittenML/KittenTTS) — lightweight CPU-friendly TTS library. 8 voices, ONNX models (15-80MB). Needs a FastAPI wrapper + simple web UI for text input and audio playback. Should run fine on Slice CPU. Target: exp.samtg.xyz/tts

---

## OPEN: Evaluate ZeroBoot
**Filed:** 2026-03-20
**Priority:** Low

ZeroBoot (github.com/zerobootdev/zeroboot) — sub-millisecond sandboxes via CoW fork() + Linux namespaces/seccomp-bpf. Linux-only, won't run on Slice (macOS). Interesting for agent sandboxing if workloads move to ada-1 or a Linux box. Clone and evaluate when relevant.

---

## DONE: KittenTTS Web Demo Deployed
**Filed:** 2026-03-20 | **Completed:** 2026-04-02

FastAPI wrapper (`KittenTTS/server.py`) with browser UI. CPU-based TTS, 8 voices. Running on port 3006, exposed at `exp.samtg.xyz/tts`. Relative fetch URLs for Caddy subpath compatibility.

---

## DONE: Higgs Audio v2 Voice Clone Demo Deployed
**Filed:** 2026-03-20 | **Completed:** 2026-04-02

FastAPI wrapper (`higgs-audio-v2/server.py`) for voice cloning. 16 character voices (inc. Shrek cast). 3B model on MPS. Running on port 3007, exposed at `exp.samtg.xyz/voice`.

---

## DONE: SillyTavern + ComfyUI Image Gen Fixed
**Filed:** 2026-04-02 | **Completed:** 2026-04-02

Root cause: `Char_Avatar_Comfy_Workflow.json` referenced `ETN_LoadImageBase64` (uninstalled custom node). Fix: switched to `Default_Comfy_Workflow.json`, replaced char avatar workflow with built-in-only nodes, set resolution to 1024 (SDXL native).

---

## SESSION: Local LLM Infrastructure (2026-04-02)

### Model Inventory
| Model | File | Size | Where | Status |
|-------|------|------|-------|--------|
| Qwen3.5-35B-A3B (MoE) | Q4_K_M | 21GB | M1 Max | available |
| Qwen3-32B (dense) | Q6_K | 25GB | M1 Max | **active on :8000** |
| SDXL Base 1.0 | safetensors | ~7GB | M1 Max | active on :8188 |

### Model Eval Results — Qwen3-32B Q6_K (dense, 32B active)

**Quick tool-calling eval (10 tests):**

| Category | Pass | Notes |
|----------|------|-------|
| Simple (single tool) | 5/5 | Perfect: selection, args, enum, types, ambiguity |
| Parallel calls | 0/1 | Timeout (120s) — model too slow for multi-call |
| Multi-step | 0/1 | Timeout (120s) — same issue |
| Relevance (no tool) | 2/2 | Correctly refuses irrelevant + no-match prompts |
| **Total** | **8/10 (80%)** | |

**Critical finding:** Custom chatml.jinja template (used for SillyTavern `/no_think`) breaks all tool calling — model scored 2/10 (20%) with it. Must use native Qwen3 Jinja template with `--jinja --reasoning-format none` for agent workloads.

**Speed:** ~30-110s per request (32B dense on M1 Max). Functional but slow for interactive agent loops. The MoE 35B-A3B was much faster (only 3B active).

### Two-Machine Architecture
| Machine | Chip | RAM | Role |
|---------|------|-----|------|
| **M1 Max (slice)** | M1 Max | 64GB | Always-on backbone: services, ComfyUI, lightweight LLM |
| **M4 Max (new)** | M4 Max | 48GB | Burst workstation: agent loops, evals, experiments |

**M4 Max advantages:** 546 GB/s memory bandwidth (vs 400 on M1), ~35% faster inference at same model size. Best for sporadic intensive work.

**M1 Max advantages:** More RAM (64 vs 48GB), can run larger models. Best as persistent service host.

### Eval Infrastructure Setup

**Location:** `/Users/sam/Documents/Projects/gitaday/model-evals/`

| Layer | Tool | Purpose |
|-------|------|---------|
| Function calling | Inspect AI + BFCL | Standardized tool-calling benchmark |
| Agent workflows | vibe-check | End-to-end agent task completion (Hermes vs Claude Code) |
| Quick comparison | `quick_eval.py` | 10-test rapid sanity check against local models |

Scripts: `run-quick.sh [model_name]`, `run-bfcl.sh [model_name]`

### Issues Found

1. **Template conflict:** SillyTavern needs `/no_think` suppression (custom template), Hermes/agent work needs native tool-calling template. Cannot use both simultaneously — must restart llama-server with different template per use case.

2. **Parallel/multi-step timeouts:** 32B dense is too slow for complex multi-tool scenarios within 120s. MoE models (3B active) are faster but less capable. Need to benchmark the tradeoff.

3. **Hermes config was pointing at dead Ollama:** Was set to `localhost:11434` (qwen2.5:7b). Updated to `localhost:8000` (Qwen3-32B via llama-server).

### Opportunities

1. **Hermes on Qwen3-32B:** Now configured. Full agent loop with file ops, terminal, web search, skills, delegation — all running on local model. Need to test actual agentic tasks (not just tool-calling format).

2. **BFCL standardized benchmark:** Installed via Inspect AI. Can produce comparable scores against published leaderboard. Run with `./run-bfcl.sh`.

3. **Model A/B testing workflow:** Swap GGUF, restart llama-server, re-run eval. Compare Qwen3-32B Q6_K vs Qwen3.5-35B-A3B vs future models.

4. **M4 Max as agent burst machine:** Run Hermes or similar agent frameworks with higher-quality models, offload from always-on M1.

### References Noted
- [TurboQuant (Google Research, ICLR 2026)](https://arxiv.org/abs/2504.19874) — 6x KV-cache compression, 8x attention speedup. Concepts already in llama.cpp (`--cache-type-k q4_0`). No code yet.
- [Strands Agents](https://strandsagents.com/blog/steering-accuracy-beats-prompts-workflows/) — steering accuracy beats prompts/workflows

### Next Steps

- [ ] Benchmark Qwen3.5-35B-A3B (MoE) on same eval for comparison
- [ ] Run BFCL standardized benchmark on both models
- [ ] Test Hermes agent loop on real tasks (not just format compliance)
- [ ] Set up M4 Max: install llama-server, register in samcloud
- [ ] Resolve template conflict (tool-calling vs no-think) — possibly two llama-server instances on different ports
- [ ] Register ComfyUI in samcloud service registry
- [ ] DNS records still missing for home-nerf-stg and ai-stg (ticket #28)
