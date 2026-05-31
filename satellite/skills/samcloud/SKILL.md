---
name: samcloud
description: "Operate the samcloud registry: services, devices, tickets, leases, the token model, and the model gateway. Read this whenever a samcloud API call 401s or you need to register/discover services."
version: 1.0.0
author: gitaday oracle
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [samcloud, services, devices, tickets, infrastructure, auth]
---

# samcloud operations

You are user + device **gitaday** on samcloud. API base `https://cloud.samtg.xyz/api/v1`.
Certs are self-signed → **always `curl -sk`**. Your token is at `~/.samcloud/token`.
Your live guide (source of truth) is `GET /users/me/guide`.

## Auth & token model — READ FIRST (this is what usually breaks)
- Your `~/.samcloud/token` is a **user/device token** — use it for discovery,
  creating services on your device, tickets, and leases.
- **Tokens ROTATE** on scope changes and then 401 `{"detail":"Invalid token"}` —
  from BOTH the registry and the model gateway (so your inference dies too).
  **If anything 401s, your token rotated. Refresh it:**
  ```bash
  PASS=$(cat ~/.samcloud/password)
  NEW=$(curl -sk -X POST https://cloud.samtg.xyz/api/v1/auth/login \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"gitaday\",\"password\":\"$PASS\"}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
  printf '%s' "$NEW" > ~/.samcloud/token
  # also update ~/.hermes/config.yaml: set model.api_key to $NEW
  ```
  (The envkit `refresh-samcloud-token.sh` hook does exactly this, idempotently.)
- **Service tokens** (`sc_service_…`) are returned at service registration and are
  scoped to THAT service — use them for that service's health/metadata, not the user token.

## Register a service (on your OWN device only)
```bash
TOKEN=$(cat ~/.samcloud/token)
curl -sk -X POST https://cloud.samtg.xyz/api/v1/services \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"my-service","device_id":"gitaday","port":8080,"health_endpoint":"/health","subdomain":"my-service-stg"}'
```
Returns a **service token**. Report health with it (every ~60s):
`POST /services/gitaday/my-service/health` with `Authorization: Bearer <service token>`.

## Discovery (public — no auth needed)
`GET /services` · `GET /devices` · `GET /routes` · `GET /devices/gitaday/guide`

## Tickets
```bash
curl -sk -X POST https://cloud.samtg.xyz/api/v1/tickets \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"type":"enhancement","priority":"low","summary":"clear one-line problem"}'
```
⚠ Do **NOT** include a `source` field — it's derived from your token (sending it → 422 `extra_forbidden`).
Types: `bug` | `enhancement` | `question`. Priorities: `low|medium|high|critical`.

## Inference (governance — see SOUL.md)
Never self-host inference. Use the model-service gateway `https://models-cs.samtg.xyz/v1`
(it leases the GPU). To use a model it lacks: `POST /models/load` or file a ticket.

## Rules
- **Search before create** — `GET /services`/`/devices` before registering anything.
- Only register services on your own device (`gitaday`).
- Self-signed certs → always `-sk`. The guide at `/users/me/guide` is authoritative.
