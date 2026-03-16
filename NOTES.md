# Git-a-Day: Project Notes

## Project 1: Shadowbroker
**Repo:** https://github.com/BigBodyCobain/Shadowbroker
**Cloned:** 2026-03-11
**Category:** OSINT / Intelligence Dashboard

### What It Is
A real-time, multi-domain open-source intelligence (OSINT) dashboard. Tracks 25,000+ vessels, 2,000+ satellites, 5,000+ aircraft simultaneously across a unified map interface. Despite the name suggesting a simple API, it's a full-stack intelligence platform.

### Tech Stack
- **Backend:** Python 3.10 / FastAPI / APScheduler / SGP4 / Playwright / BeautifulSoup
- **Frontend:** Next.js 16 / React 19 / TypeScript / MapLibre GL / Tailwind CSS 4
- **Infra:** Docker Compose, pre-built GHCR images, SQLite for CCTV cache
- **Key libs:** yfinance, feedparser, sgp4, pystac-client, cloudscraper, hls.js, satellite.js

### Architecture
```
Frontend (Next.js :3000) --> FastAPI Backend (:8000) --> 23+ Public Data Sources
                                  |
                          APScheduler (fast 60s / slow 30min tiers)
                          ETag caching + Gzip compression
                          ThreadPoolExecutor for parallel fetches
```

### Data Sources (23+)
| Domain | Sources |
|--------|---------|
| Aviation | OpenSky Network (OAuth2), adsb.lol (public), Plane-Alert DB |
| Maritime | AIS Stream (WebSocket, API key required) |
| Space | CelesTrak TLE + SGP4 propagation |
| Geopolitics | GDELT, DeepState Map (Ukraine frontline), LiveUAMap (4 regions) |
| Environment | USGS Earthquakes, NASA FIRMS fires, NOAA space weather, IODA internet outages |
| Imagery | NASA GIBS MODIS, Esri World Imagery, Sentinel-2 (MS Planetary Computer) |
| Surveillance | TfL JamCams, TxDOT Austin, NYC DOT, Singapore LTA cameras |
| Radio/SDR | KiwiSDR nodes, Broadcastify, OpenMHz |
| Financial | Yahoo Finance (defense stocks + oil) |
| Navy | GDELT-based carrier position OSINT |

### API Endpoints
- `GET /api/live-data/fast` — flights, ships, satellites (60s poll)
- `GET /api/live-data/slow` — news, stocks, weather, geopolitics (120s poll)
- `GET /api/region-dossier?lat=&lng=` — right-click country intel
- `GET /api/sentinel2/search?lat=&lng=` — satellite imagery search
- `GET /api/route/{callsign}` — flight route lookup
- `GET /api/radio/*` — radio scanner feeds
- `PUT /api/settings/api-keys` — manage API keys via UI

### Required API Keys
- **AIS_API_KEY** (aisstream.io) — mandatory for maritime tracking
- **OPENSKY_CLIENT_ID/SECRET** — optional, higher rate limits
- **LTA_ACCOUNT_KEY** — optional, Singapore cameras

### Notable Engineering
- **Dual polling tiers:** Fast (60s) for position data, slow (30min) for enrichment
- **ETag caching:** MD5-based HTTP 304 responses avoid redundant transfers
- **Gzip compression:** ~92% payload reduction (11.6MB -> 915KB)
- **Viewport culling:** Only renders features within visible bounds + 20% buffer
- **Position interpolation:** 10s smooth animation between data refreshes
- **Network fallback:** Python requests -> bash curl with TLS features on failure
- **GPS jamming detection:** NAC-P value analysis from ADS-B data
- **Holding pattern detection:** >300deg cumulative turn flags aircraft as circling
- **Plane-Alert DB:** 20K+ ICAO hex codes mapped to operators/owners
- **Non-root containers**, CORS whitelist, API key obfuscation

### Setup Status
- [x] Backend running at :8000 (Python venv, no Docker needed)
- [x] Frontend running at :3000 (Node.js version warning but functional)
- [ ] AIS API key configured (only 11 ships without it — need aisstream.io key for 25K+)
- [x] Frontend accessible at http://localhost:3000
- [x] Data flowing: 7K flights, 166 military, 550 satellites, 1.9K CCTVs, 982 GDELT events, 5K fires, 34 earthquakes

### Observations
- **Way more than advertised:** The opensourceprojects.dev post called it "a unified API for tracking aircraft and satellites" — it's actually a full OSINT intelligence platform with 23+ sources
- **Works mostly without API keys:** Only AIS Stream is mandatory; everything else runs on public APIs
- **Massive data_fetcher.py:** 2,233 lines — the single-file god-module that orchestrates everything. Ripe for a refactor but clearly functional
- **Node version mismatch:** Requires >=20.9.0, we have 20.2.0 — works but may have edge case issues
- **Impressive engineering:** ETag caching, gzip compression, viewport culling, position interpolation, GPS jamming detection, holding pattern detection
- **Plane-Alert DB:** 20K+ aircraft ICAO codes pre-mapped to operators — can track billionaire jets out of the box
- **Carrier OSINT:** Estimates US Navy carrier positions from GDELT news scraping + geographic mapping — creative approach
- **Security-conscious:** Non-root containers, API key obfuscation, CORS whitelist, no classified data

### Ideas to Explore
- Add more CCTV sources (Australian traffic cams?)
- Try the Sentinel-2 satellite imagery search endpoint
- Test the radio scanner / Broadcastify integration
- Look at the GPS jamming detection in conflict zones
- Explore the region dossier feature (right-click intel)

---

## Project 2: Holi-Spatial
**Repo:** https://github.com/Visionary-Laboratory/holi-spatial
**Cloned:** 2026-03-12
**Category:** 3D Vision / Spatial AI Research
**Verdict:** Paper-only — no runnable code yet

### What It Is
Research project that converts egocentric video streams into 3D spatial intelligence. Automated pipeline: raw video -> 3D Gaussian Splatting -> depth/grounding -> spatial QA pairs for VLM training. No human annotation needed for geometry.

### Scale
- 12,000 3DGS scenes, 1.3M 2D masks, 320K 3D bounding boxes
- 1.2M spatial QA pairs across 10 question types (camera motion, object distance, rotation, etc.)
- Benchmarked on ScanNet, ScanNet++, DL3DV

### What's Released
- [x] Project page with interactive Three.js 3D viewers
- [x] Paper on arXiv (2603.07660)
- [ ] Code (not released)
- [ ] Dataset subset (not released)
- [ ] Model checkpoints (not released)

### Why It's Interesting (for later)
- Fully automated spatial annotation pipeline — no manual labeling
- Would need GPU resources (ada-1?) when code drops
- Relevant to 3DGS/NeRF work (spl.samtg.xyz, nerfstudio)
- 10-type spatial QA benchmark could be useful for evaluating vision models

### Setup Status
Nothing to set up — repo is just a README and a project page branch.

---

## Project 3: GenCAD
**Repo:** https://github.com/ferdous-alam/GenCAD
**Cloned:** 2026-03-13
**Category:** Generative AI for CAD
**Verdict:** GPU-only, interesting concept, needs dataset download

### What It Is
Image-conditioned 3D CAD generation. Feed it a 2D sketch, get a parametric STEP/STL solid via a 3-stage pipeline:
1. **CSR** — Transformer autoencoder learns bidirectional CAD representations (256-dim latent)
2. **CCIP** — CLIP-style contrastive model aligns images with CAD embeddings
3. **Diffusion Prior** — ResNetDiffusion denoises image embeddings into CAD latents

### Tech Stack
Python 3.10 / PyTorch / pythonocc-core 7.9.0 (OpenCASCADE) / transformers / x_clip / Docker

### Setup Status
Not set up — requires CUDA GPU (hardcoded), pretrained checkpoints from Google Drive, Docker recommended

---

## Project 4: Mobile-GS
**Repo:** https://github.com/xiaobiaodu/Mobile-GS
**Cloned:** 2026-03-13
**Category:** 3D Gaussian Splatting Compression
**Verdict:** Heavy GPU requirements, training-only (no mobile viewer)

### What It Is
Compresses 3DGS models for real-time mobile rendering via teacher-student distillation + neural compression + vector quantization. Gets models down to ~10-50MB.

### Notable Techniques
- View-dependent opacity via MLP, spatial contraction to unit sphere
- Knowledge distillation (teacher guides compressed student)
- Three custom CUDA rasterizers, RAPIDS/cuML GPU KMeans for codebooks
- Apache 2.0 license (commercial-friendly)

### Setup Status
Not set up — requires 24GB+ VRAM (A100-class), COLMAP datasets. Relevant to splat work but no mobile viewer in repo.

---

## Project 5: BitNet (Microsoft)
**Repo:** https://github.com/microsoft/BitNet
**Cloned:** 2026-03-13
**Category:** 1-bit LLM Inference
**Verdict:** WORKING on M1 Max — impressive

### What It Is
Microsoft's official inference framework for ternary/1-bit LLMs. Weights are {-1, 0, 1} (1.58 bits). Optimized SIMD kernels for ARM NEON and x86 AVX2/512. Runs large models on consumer CPUs without GPU.

### Performance (M1 Max, 8 threads)
- **Model:** BitNet-b1.58-2B-4T (2.4B params)
- **Size:** 1.1 GiB RAM (I2_S quantization, 3.91 BPW)
- **Prompt eval:** 18.3 tok/s | **Generation:** 17.6 tok/s
- **Output quality:** Coherent, accurate responses in chat mode

### Supported Models
- microsoft/BitNet-b1.58-2B-4T (2B), Llama3-8B-1.58 (8B)
- Falcon3 family (1B-10B ternary), Falcon-E family (1B-3B)

### Setup (on this Mac)
```bash
# Requires LLVM 22 (/opt/homebrew/opt/llvm/bin), CMake 3.22+
# Download pre-converted GGUF (converter has arch mismatch bug)
huggingface-cli download microsoft/bitnet-b1.58-2B-4T-gguf --local-dir models/BitNet-b1.58-2B-4T
PATH="/opt/homebrew/opt/llvm/bin:$PATH" python setup_env.py -md models/BitNet-b1.58-2B-4T -q i2_s
./build/bin/llama-cli -m models/BitNet-b1.58-2B-4T/ggml-model-i2_s.gguf -p "prompt" -n 200 -t 8
```

### Gotchas
- Apple Clang 15 won't work — need Homebrew LLVM
- Use pre-converted GGUF (converter doesn't support BitNetForCausalLM)
- Chat needs Llama3 template, not raw text
- No conda needed — venv works

### Benchmark vs Ollama Qwen2.5:7b (M1 Max, 8 threads)
| Metric | BitNet 2B (1.58-bit) | BitNet 8B (1.58-bit) | Qwen2.5 7B (Q4) |
|--------|---------------------|---------------------|-----------------|
| RAM | 1.1 GiB | 3.6 GiB | 4.7 GB |
| Generation | 20-42 tok/s | 25-28 tok/s | ~15 tok/s |
| 256 tok wall time | 6-13s | 9-10s | 21-26s |
| Quality | Good, coherent | Gibberish (undertrained) | Excellent |

**Verdict:** BitNet 2B is the sweet spot — 2x faster than Ollama Q4, 1/4 RAM, solid quality. The community 8B (Llama3-8B-1.58-100B-tokens) is fast but undertrained garbage. Wait for Microsoft's official 8B.

### Ideas
- Wait for official Microsoft 8B 1-bit model
- Expose 2B via API for local LLM serving
- Try Falcon3-7B-1.58bit (may be better trained than community Llama3)

---

## Project 6: SillyTavern
**Repo:** https://github.com/SillyTavern/SillyTavern
**Cloned:** 2026-03-14
**Category:** Character/Persona Chat Playground
**Verdict:** WORKING — persona sandbox with local LLM backends

### What It Is
Browser-based character chat interface. Create personas, characters, scenarios. Supports multiple LLM backends including Ollama and OpenAI-compatible APIs.

### Setup (on this Mac)
- Port: 3004 (changed from default 8000 to avoid conflicts)
- Auth: basicAuthMode=true, user=sam
- Backends: Ollama (qwen2.5:7b, llava:7b) on :11434, BitNet 2B on :8081
- Config: `/Users/sam/Documents/Projects/gitaday/SillyTavern/config.yaml`

### Status
- [x] Running on :3004 with basic auth
- [x] Ollama connected as Text Completion backend
- [x] BitNet available as OpenAI-compatible endpoint
- [ ] Not path-routable (no basePath support) — /tavern proxy only works for initial HTML

---

## Project 7: Claw-Empire (AI Office Sim)
**Repo:** https://github.com/GreenSheep01201/claw-empire
**Cloned:** 2026-03-14
**Category:** Multi-Agent AI Office Simulation
**Verdict:** WORKING — best AI sim of the three assessed

### What It Is
AI agent company simulator. Pixel-art office with departments (Planning, Dev, Design, QA, DevSecOps, Ops), agents with roles and personalities, task delegation, git worktree isolation, meeting minutes. CEO (you) orchestrates via web UI.

### Tech Stack
- **Full-stack TypeScript:** Node 22 / Express 5 / React 19 / Vite 7 / PixiJS 8
- **Database:** SQLite (embedded, zero config)
- **LLM:** Supports Ollama, OpenAI, Anthropic, Google, OpenRouter, Together, Groq, custom
- **Build:** pnpm, Tailwind CSS 4, TypeScript 5.9

### Why This One Won (vs AIvilization, ai-civilization)
| | AIvilization | ai-civilization | **Claw-Empire** |
|---|---|---|---|
| Local LLMs | No (GPT-4 only) | No (OpenAI+Pinecone) | **Yes (Ollama native)** |
| UI | CLI only | Web but needs Convex | **Full pixel-art web UI** |
| Cloud deps | OpenAI, Pinecone | 4 cloud services | **None** |
| Status | Prototype | Fork of a16z | **Production v2.0.4** |

### Architecture
- 14 agents across 6 departments, each assignable to different LLM providers
- Workflow packs: development, report, web research, novel, video preprod, roleplay
- Tasks flow: CEO → Planning → Subtasks → Agents → Review → Done
- Agents work in isolated git worktrees for safe parallel execution
- Real-time WebSocket sync for office state

### Setup (on this Mac)
```
Frontend: http://127.0.0.1:8800
API:      http://127.0.0.1:8790
```
- All 14 agents configured to use Ollama qwen2.5:7b
- BitNet 2B also added as alternative provider
- SQLite at `claw-empire/claw-empire.sqlite`
- Node 22.22.1 (upgraded from 20.18.0)
- External: https://claw.samtg.xyz

### Eval Results (3-run repair arc)
Tested directive→meeting→subtask→execution pipeline with qwen2.5:7b. Three repairs applied:
1. **Prompt nudge**: Tell 7B explicitly that coding tasks go to "dev" department
2. **Routing lock**: Prevent second-pass re-routing from undoing correct first-pass decisions
3. **Code extraction**: Extract code from API responses (fenced blocks + JSON `code_snippet` fields) and write to worktree

Run 3 produced `hello.py` with correct content — 14-agent office sim running entirely on local hardware. Full eval results in `claw-empire-eval/results/`.

### Also Cloned (Not Set Up)
- **corca-ai/AIvilization** — Python CLI, GPT-4 only, interesting hierarchy concept but needs OpenAI key
- **kyegomez/ai-civilization** — AI Town fork, needs OpenAI + Pinecone + Convex + Clerk (too many cloud deps)

---

## Project 8: OpenCode
**Repo:** https://github.com/anomalyco/opencode
**Cloned:** 2026-03-14
**Category:** CLI Coding Agent
**Verdict:** INSTALLED — viable Claw-Empire CLI provider, 7B tool calling unreliable

### What It Is
Open-source CLI coding agent (122k stars), similar to Claude Code. Provider-agnostic, ships as single binary via npm. Already wired into Claw-Empire as `cli_provider: "opencode"`.

### Local LLM Support
- Ollama: YES — configured via `opencode.json`, qwen2.5:7b responds to chat
- BitNet 2B: Detected but too small for agentic work
- Tool calling with 7B: Unreliable (malformed arguments, same pattern as Claw-Empire routing)

### Key Insight
The 7B wall is consistent across all agent frameworks — chat works, structured tool calling breaks. Need 32B+ for reliable tool use.

---

## Project 9: Autoresearch (Karpathy)
**Repo:** https://github.com/karpathy/autoresearch
**Cloned:** 2026-03-14
**Category:** Autonomous ML Experimentation
**Verdict:** ASSESSED — patterns stolen for our overnight loop

### What It Is
NOT a research search agent. An autonomous ML experimentation system: give a coding agent a GPU + `train.py`, it modifies code, trains 5 min, checks if loss improved, keeps or reverts, loops overnight. ~31.8k stars.

### Architecture
Three files: `prepare.py` (immutable harness), `train.py` (mutable), `program.md` (agent instructions). The agent is external (Claude Code, Codex, etc.) — the repo contains zero agent/LLM code.

### Patterns We Stole
1. Hill-climbing git loop (commit → run → measure → keep/revert)
2. Fixed budget per iteration (5 min)
3. Single-file scope (agent can ONLY modify one file)
4. program.md as the new source code
5. results.tsv as structured memory
6. NEVER STOP directive (loop until interrupted)
7. Simplicity criterion (simpler wins ties)

### Local Feasibility
Training code needs CUDA. macOS forks exist (autoresearch-mlx, autoresearch-macos). The patterns are the real value — we applied them to Claw-Empire eval.

---

## Project 10: Skills & Tooling
**Repos:** anthropics/skills, obra/superpowers, poofdotnew/vibe-check
**Cloned:** 2026-03-14
**Category:** Agent Evaluation & Development Skills

### anthropics/skills (17 official skills)
Templates for Claude Code: pdf, docx, skill-creator, webapp-testing, etc. Good reference for skill structure.

### obra/superpowers (14 dev skills)
Battle-tested: TDD, systematic-debugging, verification-before-completion, writing-plans, code-review, git-worktrees. The methodology patterns more valuable than the code.

### poofdotnew/vibe-check (eval framework)
Full test harness for AI agents. We built a Claw-Empire wrapper with 3 eval cases + 4 custom judges:
- `basic-directive` — task creation smoke test (PASS)
- `routing-to-dev` — department routing verification (PASS)
- `code-gen-hello` — artifact creation (TIMING-SENSITIVE)

Built-in learning system that proposes prompt improvements from failures (uses LLM judge).

---

## Project 11: Hermes Agent (NousResearch)
**Repo:** https://github.com/NousResearch/hermes-agent
**Cloned:** 2026-03-15
**Category:** Persistent Autonomous Agent
**Verdict:** CLONED — interesting persistent memory + skill generation patterns

### What It Is
Persistent server-side agent with multi-platform I/O (Telegram, Discord, Slack, CLI). Python, model-agnostic. Grows over time via memory accumulation and skill generation.

### Why It's Interesting
Persistent memory + autonomous skill generation patterns overlap with what we're building. The agent lives on a server and develops capabilities over time rather than starting fresh each session.

---

## Overnight Hill-Climbing Loop

### Setup
Applied Karpathy's autoresearch pattern to Claw-Empire prompt optimization:
- **Mutable file:** `prompts.json` (system prompt + routing hint)
- **Immutable harness:** 3 eval tests (hello.py, README.md, math_utils.py)
- **Metric:** pass rate (0-3)
- **Agent:** Ollama qwen2.5:7b (local)
- **Budget:** ~15 min per iteration cycle

### Run 1 Results (2026-03-14, crashed after 1 iteration)
- 1/3 pass (hello.py passed, README partial, math_utils failed)
- System crash due to resource contention (too many services running)
- Python syntax error in overnight script (bash/python string escaping)

### Run 2 Results (2026-03-16, 12 iterations over ~2 hours)
| Iter | Pass Rate | Status | Notes |
|------|-----------|--------|-------|
| 1 | 0/3 | same | Cold start |
| **2** | **2/3** | **keep** | Peak — hello.py + math_utils.py passed |
| 3 | 1/3 | revert | Ollama's prompt change regressed |
| 4-11 | 0/3 | revert | Stuck — model can't find improvements |

### Key Findings
1. **The arena works.** Hill-climbing + git keep/revert is solid. Correctly reverts regressions.
2. **Peak 2/3 on base config.** The original prompts (with our manual patches) are already near-optimal for 7B.
3. **7B can't self-improve.** Every prompt suggestion from qwen2.5:7b made things worse. The model can execute (write code) but can't reason about its own prompts.
4. **The right architecture:** Use a stronger model (Claude/32B) as the improvement oracle, keep 7B as the executor. Different models for different roles.
5. **README "partial" is the stubborn test.** File exists but content never matches — the model updates it but doesn't include the exact "About" section text.

---
