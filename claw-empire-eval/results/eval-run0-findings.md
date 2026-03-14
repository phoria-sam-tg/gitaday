# Claw-Empire Eval: Run 0 Findings
**Date:** 2026-03-14
**Model:** qwen2.5:7b via Ollama (local)
**Harness:** Manual + API monitoring

## Pipeline Trace

```
directive (CEO)
  → classifyIntent → auto-create task (status: inbox → planned)
  → kickoff meeting: 14 agents get one-shot prompts via Ollama
  → meeting responses: 10-15 logs generated, ~500-900 bytes each
  → subtask delegation: model returns JSON with assignments
  → subtask execution: agents marked "done"
  → task moves to "review"
  → NO code artifacts produced
```

## Findings

### 1. Pipeline Functional
The full orchestration pipeline (directive → meeting → delegation → execution → review) runs
end-to-end with a 7B model. Ollama loads on-demand, processes meeting prompts, unloads after
timeout. No crashes, no hangs — just slow and imprecise.

### 2. Empty Responses (Intermittent)
~30% of meeting one-shot calls return empty responses (59 bytes = header only, no content).
The model receives the prompt but produces nothing. Likely caused by:
- Prompt length exceeding effective context for 7B
- Multi-language prompts (Korean + English) confusing the model
- Complex JSON schema in system prompt overwhelming small model

### 3. Null Department Routing (Critical)
When the model DOES respond, it routes all subtasks to `target_department_id: null` (stays in
planning). The expected behavior is routing to `dev`, `design`, `qa` etc. Without dev routing,
no agent spawns code execution — the task "completes" with empty output.

**Example from meeting log:**
```json
{
  "subtask_id": "d9e437c8-...",
  "target_department_id": null,
  "reason": "This subtask involves finalizing the task sequence...",
  "confidence": 0.9
}
```

### 4. No Verification Gate
The system marks tasks as "review" even when zero artifacts are produced. There's no
verification-before-completion check — the orchestration trusts that if subtasks are "done",
the work is done. With a small model producing empty/null responses, this means false completion.

### 5. Task Titles Leak Provider Metadata
Subtask titles include raw provider info:
```
[Plan Item] [api:ollama] Provider: Ollama Local, Model: qwen2.5:7b...
```
The model's response gets used as the title without sanitization.

## Strengths

- Ollama integration works seamlessly (on-demand loading, SSE streaming)
- Meeting system generates diverse agent responses (different departments acknowledge)
- Worktree isolation is created correctly
- WebSocket real-time updates function properly
- The system is remarkably resilient — doesn't crash on bad model output

## Repair Candidates

1. **Simpler prompts**: Strip Korean, reduce prompt length, use simpler JSON schemas
2. **Department hints**: Pre-assign task to dev department, skip the routing step
3. **Fallback routing**: If model returns null department, default to dev (not planning)
4. **Output verification**: Check if worktree has new files before marking "done"
5. **Title sanitization**: Strip provider metadata from subtask titles
6. **Timeout increase**: Give 7B model more time per one-shot call
7. **Temperature/params**: Tune Ollama generation parameters for more deterministic output

## Recommendation

For a "soft nerfed business world" that works with 7B models:
- Bypass the meeting system entirely for simple tasks
- Route directly: directive → assign to dev agent → execute via API → verify
- Keep meetings for multi-step tasks but pre-route to departments
- Add artifact verification before "done" status
