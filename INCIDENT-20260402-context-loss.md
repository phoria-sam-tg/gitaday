# Incident: Samcloud Staging Context Lost on Compaction

**Date:** 2026-04-02
**Severity:** Medium
**Status:** Open

## What happened

During a long gitaday session, the conversation context was compacted. The compaction summary preserved local LLM infra details (models, eval results, llama-server flags) but **dropped all samcloud staging context** — the API URL, auth credentials, agent identity, ticketing system, and the resource/lease model.

The session then tried to write a model registry planning ticket into `SAMCLOUD-WORK.md` (the old markdown approach) instead of filing it via the actual samcloud ticketing API at `stg.samtg.xyz`.

## What was lost

- Auth token / credentials for the `gitaday` user (user:8) on `stg.samtg.xyz`
- Knowledge that `stg.samtg.xyz` is the staging samcloud instance with a full REST API
- Knowledge of the ticketing system (`POST /api/v1/tickets`)
- Knowledge of the resource & lease system (for model GPU allocation)
- Knowledge of the existing `ollama-manager` service (user:17 `claude-services`, port 8800, `models-stg.samtg.xyz`)

## What was rediscovered

### API: `https://stg.samtg.xyz/api/v1`

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /services` | public | List all registered services |
| `GET /resources` | public | List hardware resources (GPU, etc.) |
| `GET /users` | public | List users and agents |
| `GET /status` | public | Full system status (devices, services, resources) |
| `POST /tickets` | auth required | Create tickets |
| `PATCH /tickets/{id}` | auth required | Update tickets |
| `POST /tickets/{id}/comments` | auth required | Comment on tickets |
| `POST /services` | scoped auth | Register services |
| `POST /resources` | scoped auth | Register resources |
| `POST /resources/{id}/leases` | auth required | Request resource lease |
| `POST /auth/login` | — | Login (username/password) |

### Existing model infrastructure already in samcloud

The `ollama-manager` service is already registered:
```
id: slice-test/ollama-manager
port: 8800
subdomain: models-stg.samtg.xyz
capabilities: [llm-inference, model-management, resource-leasing, ollama, llama-cpp, openai-compatible]
created_by: user:17 (claude-services)
status: online (last health: 2026-04-02T08:58:37)
```

This means model management may already be partially built. Need to check what `models-stg.samtg.xyz` exposes before designing a new system.

### Users / identities

| ID | Username | Role | Scopes |
|----|----------|------|--------|
| 1 | admin | admin | `["*"]` |
| 2 | claude | admin | `[]` |
| 8 | gitaday | user | `["device:slice-test"]` |
| 16 | inference | agent | `["device:slice-test"]` |
| 17 | claude-services | agent | `["device:slice-test"]` |

### Hardware resource registered

```
id: slice-test/gpu-0
type: gpu
model: Apple M1 Max
specs: { unified_memory_mb: 65536, gpu_cores: 32, neural_engine_cores: 16, cpu_cores: 10 }
utilisation: { memory_used_mb: 48449, memory_pct: 73.9%, compute_pct: 51% }
```

## Blocked on

**Auth** — need a token for `gitaday` (or any ticket-capable user) to:
1. File the model registry planning ticket via `POST /api/v1/tickets`
2. Register the tested models as resources via `POST /api/v1/resources`
3. Check what `ollama-manager` already provides before duplicating work

## Original task (pending)

File a planning ticket for **Model Registry & Provider Service** — centralise model storage, register tested models (Qwen3-32B Q6_K, Qwen3.5-35B-A3B), and create a request system for agents to request new models to be spun up. The detailed spec was drafted in `SAMCLOUD-WORK.md` but should be filed as a samcloud ticket instead.

## Lessons

1. Samcloud API context (URL, auth, identity) should be in `CLAUDE.md` or a durable location so it survives compaction
2. The old `SAMCLOUD-WORK.md` ticketing approach is superseded by the staging API — new tickets go to `stg.samtg.xyz/api/v1/tickets`
3. The `ollama-manager` service already exists — check it before building from scratch
