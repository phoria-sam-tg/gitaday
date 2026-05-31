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
`chat_completion_source: "custom"`, `custom_url: "http://localhost:8800/v1"`,
`custom_model: "qwen3.5"`. The API key is in `data/default-user/secrets.json` as
`api_key_custom` (your samcloud token). To switch model (e.g. to `agi` once ticket
#63 lands), set `oai_settings.custom_model` and restart. Never touch `api_key_custom`,
`custom_url`, or `chat_completion_source`.

## Add a character (the main twiddle)
Character cards are JSON in `data/default-user/characters/<Name>.json`
(Character Card V2). Minimal valid card:
```json
{ "spec": "chara_card_v2", "spec_version": "2.0",
  "data": { "name": "Fleet Sage", "description": "...", "personality": "...",
    "scenario": "...", "first_mes": "Greetings, traveller.", "mes_example": "",
    "creator_notes": "", "system_prompt": "", "post_history_instructions": "",
    "tags": [], "alternate_greetings": [], "character_book": null } }
```
Write the file, refresh the UI — it shows in the character list.

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
