# Codex MCP Fallback Protocol

**Applies to:** All skills that use `mcp__codex__codex` or `mcp__codex__codex-reply` for external LLM review, brainstorming, or evaluation.

When Codex MCP is unavailable, skills fall back to a Claude subagent reviewer. When implementing changes based on review feedback, skills consult NotebookLM for domain accuracy.

---

## 1. Detection (run once at skill startup)

### Auto-detection (default)

1. Attempt a lightweight Codex MCP probe (e.g., `mcp__codex__codex` with a trivial prompt like `"ping"`).
2. If the tool responds successfully → set `REVIEWER_BACKEND = codex`.
3. If the tool errors, times out, or is not found → set `REVIEWER_BACKEND = subagent`.
4. Log the result: `"Reviewer backend: codex"` or `"Reviewer backend: subagent (Codex MCP unavailable)"`.

### Manual override

Users can force the backend via argument:

```
/skill-name "args" — reviewer: subagent
/skill-name "args" — reviewer: codex
```

---

## 2. Single-Shot Fallback

For skills that call Codex once (e.g., novelty-check, result-to-claim, ablation-planner, training-check):

### If backend = `codex`

Use the existing Codex call as-is:

```
mcp__codex__codex:
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [skill-specific prompt]
```

### If backend = `subagent`

Spawn a Claude subagent with the same prompt. **`model: "opus"` is REQUIRED — never omit it; omitting it silently inherits the parent's Sonnet model.**

```
Agent:
  description: "[skill-name] external review"
  model: "opus"
  prompt: |
    [same prompt that would go to Codex — persona, instructions, context, output format]
```

The subagent must receive the **complete prompt** including persona, context, and output format instructions. Do not abbreviate.

---

## 3. Multi-Round Fallback

For skills with iterative review loops (e.g., research-refine, auto-review-loop, method-derive, auto-paper-improvement-loop):

### Round 1

- **Codex**: Use `mcp__codex__codex`. Save the `threadId`.
- **Subagent**: Use `Agent` tool. Save the **full review response text**.

### Round 2+

- **Codex**: Use `mcp__codex__codex-reply` with saved `threadId` to maintain conversation context.
- **Subagent**: Spawn a **new** Agent with the full prior review embedded in the prompt:

```
Agent:
  description: "[skill-name] review round N"
  model: "opus"
  prompt: |
    [reviewer persona]

    ## Context: You previously reviewed this work in Round N-1.

    ### Your Round N-1 Review (verbatim):
    [paste full prior review text]

    ### Changes Implemented Since Round N-1:
    1. [change 1]
    2. [change 2]
    ...

    [round N review instructions]
```

### State persistence

When persisting state to JSON (e.g., `REVIEW_STATE.json`, `REFINE_STATE.json`, `DERIVE_STATE.json`):
- Add `"reviewer_backend": "codex"` or `"reviewer_backend": "subagent"` field.
- `threadId` is only populated for `codex` backend. Set to `null` for `subagent`.

---

## 4. NotebookLM Consultation

**When:** Before implementing any **CRITICAL or MAJOR** fix/revision based on reviewer feedback.

**Why:** Grounds changes in established theory and project-specific knowledge, preventing introduction of new errors while fixing old ones.

### Notebooks

| Notebook | ID | Use For |
|----------|----|---------|
| ML for Recurrent Events | `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` | Pseudo-observation theory, recurrent event methodology, competing risks, C-index, landmark analysis |
| Interpretable AI | `fea2207b-7ec1-463c-b73f-58c0c4febb41` | ML model assumptions, interpretability claims, method comparisons, random forest theory |

### Query pattern

```
mcp__notebooklm__notebook_query:
  notebook_id: "0bf80af5-8b8d-423d-b7ef-94b13ad48f7b"
  query: "[targeted question derived from the reviewer's criticism and proposed fix]"

mcp__notebooklm__notebook_query:
  notebook_id: "fea2207b-7ec1-463c-b73f-58c0c4febb41"
  query: "[targeted question about ML methodology or interpretability]"
```

### Query strategy

- Formulate a **targeted question** based on the reviewer's criticism and the proposed fix.
- Query the notebook whose domain matches the fix (query both if the fix spans domains).
- Use the response to verify theoretical soundness, find correct citations, and avoid introducing errors.

### Fallback

If NotebookLM MCP is unavailable (tool errors or not configured), **skip silently** and proceed with fixes using available knowledge. Log: `"NotebookLM unavailable — changes applied without notebook consultation"`.

### Logging

When a notebook query informs a fix, note it in the skill's output log:

```
Fix grounded in NotebookLM: [notebook name] — [key finding]
```

---

## 5. Logging Conventions

All skills using this protocol should record in their output documents:

1. **Reviewer backend used** (`codex` or `subagent`)
2. **NotebookLM availability** (`available` or `unavailable`)
3. **Per-fix notebook grounding** (when applicable)
4. **Full raw review text** from either backend — never summarize or truncate

---

## 6. Required `allowed-tools` Updates

Skills adopting this protocol must include in their `allowed-tools`:

- `Agent` — for subagent fallback
- `mcp__notebooklm__notebook_query` — for NotebookLM consultation
- Existing `mcp__codex__codex` and `mcp__codex__codex-reply` — retained for when Codex is available

---

## 7. Skills Using This Protocol

| Skill | Codex Pattern | Notes |
|-------|---------------|-------|
| `research-refine` | Multi-round | Iterative GPT review loop |
| `auto-review-loop` | Multi-round | Autonomous review loop |
| `auto-paper-improvement-loop` | Multi-round | Paper writing quality loop (has inline fallback) |
| `method-derive` | Multi-round | Math review loop |
| `research-review` | Multi-round | Interactive external review |
| `idea-creator` | Single-shot | Brainstorming + review |
| `novelty-check` | Single-shot | Cross-model verification |
| `result-to-claim` | Single-shot | Result evaluation |
| `ablation-planner` | Single-shot | Ablation design |
| `training-check` | Single-shot | Ambiguous case judgment |
| `paper-plan` | Single-shot | Outline review |
| `paper-write` | Single-shot | Section review |
| `paper-figure` | Single-shot | Figure review |
| `paper-slides` | Single-shot | Slide review |
| `paper-poster` | Single-shot | Poster review |
| `paper-illustration` | Single-shot | Illustration review |
| `grant-proposal` | Single-shot | Proposal review |
| `rebuttal` | Multi-round | Rebuttal drafting |
| `idea-discovery` | Orchestrator | Delegates to sub-skills |
| `idea-discovery-robot` | Orchestrator | Delegates to sub-skills |
| `research-refine-pipeline` | Orchestrator | Delegates to sub-skills |
| `research-pipeline` | Orchestrator | Delegates to sub-skills |
| `paper-writing` | Orchestrator | Delegates to sub-skills |
| `experiment-bridge` | Orchestrator | Delegates to sub-skills |
