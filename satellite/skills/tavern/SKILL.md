---
name: tavern
description: "Configure a headless SillyTavern: add characters and personas, manage presets, switch the model, and restart safely. Use when curating the persona playground."
version: 1.0.0
author: gitaday oracle
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [sillytavern, tavern, personas, characters, creative, config]
---

# Configuring SillyTavern (headless)

The tavern lives at `~/SillyTavern`, runs `node server.js` on port **3005** in tmux
session **`tavern`**. Per-user data is under `~/SillyTavern/data/default-user/`.

## Restart after config changes
```bash
tmux kill-session -t tavern 2>/dev/null
tmux new -d -s tavern "cd ~/SillyTavern && exec node server.js"
```
Character cards appear on a browser refresh (no restart). settings.json / personas
changes need a restart.

## Model connection — already wired, DO NOT BREAK
In `data/default-user/settings.json` → `oai_settings`:
`chat_completion_source: "custom"`, `custom_url: "http://localhost:8810/v1"`,
`custom_model: "qwen3.5"`. The API key is in `data/default-user/secrets.json` as
`api_key_custom` (your samcloud token). To switch model (e.g. to `agi` once ticket
#63 lands), set `oai_settings.custom_model` and restart. Never touch `api_key_custom`,
`custom_url`, or `chat_completion_source`.

> **Why :8810, not :8800?** The model-service serves the model LIST at `/models`
> but CHAT at `/v1/chat/completions`, and its `/models` isn't OpenAI-shaped — so ST
> shows "not connected". A tiny forwarding shim (`~/model-shim.py`, tmux `modelshim`)
> normalizes `/v1/models` and forwards the rest to the leased `:8800`. It's pure
> forwarding (no inference). If chat breaks, check the `modelshim` tmux session is up.

## Add a character — MUST import via the API (raw .json is ignored!)
ST only indexes **PNG** cards. Writing a `.json` into `characters/` does **nothing**.
Write the V2 card, then **import** it (which converts to a PNG card). Every API call
needs the CSRF token:
```bash
PW=$(cut -d: -f2 ~/.tavern-creds); J=/tmp/st.cookies
CT=$(curl -s -u "silly:$PW" -c "$J" http://localhost:3005/csrf-token | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s -u "silly:$PW" -b "$J" -X POST http://localhost:3005/api/characters/import \
  -H "X-CSRF-Token: $CT" -F "avatar=@/path/Name.json" -F "file_type=json"
```
Minimal V2 card: `{"spec":"chara_card_v2","spec_version":"2.0","data":{"name":"...",
"description":"...","personality":"...","scenario":"...","first_mes":"...","tags":[]}}`.

## Group chats (characters talk to each other)
Create a group from imported members (avatars are `<Name>.png`):
```bash
curl -s -u "silly:$PW" -b "$J" -X POST http://localhost:3005/api/groups/create \
  -H "Content-Type: application/json" -H "X-CSRF-Token: $CT" \
  -d '{"name":"Maple Court","members":["Marge Plum.png","Dev Okafor.png"],
       "activation_strategy":0,"allow_self_responses":false,"disabled_members":[]}'
```
`activation_strategy: 0` = natural (they chime in on their own).

## Personas (the user side)
User personas live in `settings.json` (`personas`, `persona_descriptions`,
`default_persona`). Add/edit then restart.

## Presets
Chat-completion presets are JSON files in `data/default-user/OpenAI Settings/`.

## Rules
- NEVER edit `api_key_custom`, `custom_url`, or `chat_completion_source` — that's the
  fleet wiring the oracle set up.
- Restart only via the tmux command above (don't blind-kill node).
- Never put secrets/tokens in character cards, presets, or logs.
