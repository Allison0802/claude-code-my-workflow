# Phase 5 — Write artifacts

**Preconditions:** `state.synthesis` populated (complete mode) OR `state.abort_reason != null` (partial mode).

**Postconditions:**
- `${OUT_ROOT}/briefing/${FULL_SLUG}_briefing.md` written (complete or partial).
- `${OUT_ROOT}/transcripts/${FULL_SLUG}_transcripts.md` written (rendered view of `state.lenses_completed[*].transcript_slice`).
- `state.run_status` unchanged here — Phase 6 transitions to `completed`.

---

## Step 5.1 — Render briefing

Use `templates/briefing.md` as the skeleton. Substitute:

- Paper metadata (title, authors, year, slug)
- Severity summary table (one row per lens with `severity` column)
- Top killer questions (from `synthesis.top_killer_questions`)
- Per-lens sections: `one_line_finding`, `why_it_didnt_hold`, plus a brief quote from the terminal Reviewer turn
- External novelty-check summary (collapsed if `status != "completed"`)
- Sub-project relevance blocks (one per active sub-project)
- Recommendation + rationale
- Verdict prose (3–4 sentences, top of briefing)

**Partial mode.** If `state.abort_reason` is non-null:

- Header shows `⚠️ PARTIAL — aborted due to <abort_reason>`.
- For each lens with `severity == "skipped"`, list under "Skipped lenses" with `why_it_didnt_hold`.
- Recommendation is `flag` by default, with rationale noting incomplete run.
- Write to the same path. The partial-mode file is the source of truth for the run; resume produces a new file at `<slug>_<date+1>_briefing.md` if invoked on a different day.

Write to `${OUT_ROOT}/briefing/${FULL_SLUG}_briefing.md`.

---

## Step 5.2 — Render transcripts

For each `lens in state.lenses_completed`, render a section:

```
## Lens {{lens_id}} — {{name}}

**Severity:** {{severity}}
**Finding:** {{one_line_finding}}

### Turn {{turn}} — {{role}} ({{timestamp_iso}})
<verbatim content>

### Turn 2 — author (...)
...
```

`turn` is a display index (1, 2, 3, ...) produced from the array index. **It is NOT stored in the turn_record** — display only. Schema gate G-3c rejects `turn` at the record level.

Write to `${OUT_ROOT}/transcripts/${FULL_SLUG}_transcripts.md`.

---

## Step 5.3 — Finalize state.json

Run `scripts/enforce_schema.py` against the final state.json. On failure, log error, fix, re-run. (Failure at this point indicates a Moderator bug, not a runtime data issue.)

No mutation of state.json content here beyond the schema-pass check.

---

## Exit

Both artifacts on disk. Return to SKILL.md, which loads `runbooks/phase-6-cleanup.md`.
