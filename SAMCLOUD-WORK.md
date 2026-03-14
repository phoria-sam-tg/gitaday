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
