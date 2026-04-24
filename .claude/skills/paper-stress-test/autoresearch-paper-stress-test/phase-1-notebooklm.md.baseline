# Phase 1 — NotebookLM setup

**Preconditions (from Phase 0):** `paper.source` points to a valid local PDF, `paper.slug` populated, output directories exist.

**Postconditions:**
- `notebooks.disposable.id` populated; paper uploaded to that notebook.
- `notebooks.thematic.id` resolved or explicitly null (user opted out).
- `state.json` initialized on disk at `${OUT_ROOT}/state/${FULL_SLUG}_state.json` with `schema_version: "2"` and `run_status: "in_progress"`.

---

## Step 1.1 — Create disposable notebook

```
mcp__notebooklm__notebook_create(
  title: "${DISPOSABLE_NOTEBOOK_NAME_PREFIX}${FULL_SLUG}"
)
```

Tool returns `notebook_id`. Save to `notebooks.disposable.id`. Set `notebooks.disposable.disposition = "pending"` and `notebooks.disposable.promoted_to = null`.

On error, retry once after 5s. On second failure, abort with:

> NotebookLM create failed twice. Is the MCP server reachable? Try `nlm login` first.

---

## Step 1.2 — Upload the paper

```
mcp__notebooklm__source_add(
  notebook_id: <disposable_id>,
  source_type: "file",
  file_path: <validated_local_pdf_path>
)
```

Verify return does not indicate failure. On failure, retry once. On second failure, delete the just-created disposable notebook and abort.

---

## Step 1.3 — Resolve thematic cross-check notebook

Decision tree:

1. **If `--cross-check <name>` was provided:**
   - Call `mcp__notebooklm__notebook_list()`, find the match by name or id. Save `notebooks.thematic.{id,name}`.
   - If no match: abort — malformed argument.

2. **If no `--cross-check` flag:**
   - Extract keywords from the paper's abstract (Read page 1, identify abstract block).
   - Case-insensitive match against the "Known thematic notebooks" table in SKILL.md.
   - If exactly one notebook matches: auto-select, print "Auto-selected thematic notebook: <name> (keywords: ...)".
   - If multiple or none match, prompt:
     ```
     No single thematic notebook auto-selected. Choose:
       [1] ML for Recurrent Events
       [2] Interpretable AI
       [3] Machine Learning Fundamentals
       [4] Survival Analysis Fundamentals
       [5] Skip cross-check (Lens 7 falls back to disposable-only, promote disabled)
     ```

3. **If user chose `[5]`**: set `notebooks.thematic = {id: null, name: null}`. Phase 6 promote option will be hidden. Lens 7 runbook must detect this and degrade gracefully.

---

## Step 1.4 — Initialize state.json

Write `${OUT_ROOT}/state/${FULL_SLUG}_state.json` conforming to `schema/state.schema.json` (schema_version=2):

```json
{
  "schema_version": "2",
  "paper": {
    "title": "<extracted from PDF page 1>",
    "authors": ["<first author>", "..."],
    "year": <year>,
    "source": "<original paper-ref argument>",
    "slug": "${FULL_SLUG}"
  },
  "invocation": {
    "depth": <parsed>,
    "type_override": <parsed or null>,
    "cross_check_override": <parsed or null>,
    "skip_novelty": <parsed boolean>,
    "human_checkpoint": <parsed boolean, default true>
  },
  "notebooks": {
    "disposable": {
      "id": "<id>",
      "name": "${DISPOSABLE_NOTEBOOK_NAME_PREFIX}${FULL_SLUG}",
      "created_at": "<ISO 8601>",
      "disposition": "pending",
      "promoted_to": null
    },
    "thematic": {
      "id": "<id>",
      "name": "<name>"
    }
  },
  "detected_type": null,
  "classification_source": null,
  "headline_claim": null,
  "novelty_claims": [],
  "novelty_check": { "status": "pending" },
  "lens_plan": [],
  "lenses_completed": [],
  "synthesis": null,
  "transcript": [],
  "moderator_assessments": [],
  "compaction_history": [],
  "spawn_count": 0,
  "spawn_budget": 80,
  "wall_clock_start": null,
  "wall_clock_budget_s": 1800,
  "abort_reason": null,
  "moderator_own_context_est_chars": 0,
  "run_status": "in_progress",
  "started_at": "<ISO 8601>",
  "completed_at": null
}
```

**Note:** `wall_clock_start` is initialized `null` here and set at the start of Phase 3 (after plan confirmation) to exclude idle user-prompt time from the budget. It is NOT reset on resume.

**Schema validation:** After writing, run `scripts/enforce_schema.py <state_path>` (see runbook §Step 6-validator once implemented). On failure, abort with the JSON Schema error messages inline.

---

## Exit state

Return to SKILL.md, which loads `runbooks/phase-2-classify-plan.md`.
