# Phase 5 — Write artifacts

**Preconditions:** `state.synthesis` populated (complete mode) OR `state.abort_reason != null` (partial mode).

**Postconditions:**
- `${OUT_ROOT}/briefing/${FULL_SLUG}_briefing.md` written (complete or partial).
- `${OUT_ROOT}/transcripts/${FULL_SLUG}_transcripts.md` written (rendered view of `state.lenses_completed[*].transcript_slice`).
- `state.run_status` unchanged here — Phase 6 transitions to `completed`.

---

## Step 5.1 — Render briefing

Use `templates/briefing.md` as the skeleton. Every placeholder MUST be read from
`state.json` — never hardcode values. Required substitutions:

| Placeholder | Source of truth |
|---|---|
| `{{PAPER_TITLE}}` / `{{PAPER_AUTHORS}}` / `{{PAPER_YEAR}}` / `{{PAPER_SOURCE}}` | `state.paper.*` |
| `{{STRESS_TEST_DATE}}` | derived from `state.paper.slug` trailing date |
| `{{DETECTED_TYPE}}` | `state.detected_type` |
| `{{DEPTH}}` | `state.invocation.depth` (integer only; no parenthetical) |
| `{{WEIGHTS_LIST}}` | `"/".join(lens.weight for lens in state.lens_plan)` in lens_id order 0..8 |
| `{{REVIEWER_MODEL}}` / `{{AUTHOR_MODEL}}` | SKILL.md Constants (`REVIEWER_MODEL`, `AUTHOR_MODEL`) |
| `{{VERDICT}}` | `state.synthesis.verdict` — MUST be ≤ 150 words; compress if synthesis produced more |
| `{{TOP_KILLER_QUESTIONS}}` | enumerated from `state.synthesis.top_killer_questions` |
| `{{NOVELTY_SECTION}}` | collapsed if `state.novelty_check.status != "completed"` |
| `{{SEVERITY_TABLE}}` | built from `state.lenses_completed[*]` (one row per lens) |
| `{{PER_LENS_FINDINGS}}` | per-lens block: `one_line_finding`, `why_it_didnt_hold`, plus a brief quote from the terminal Reviewer turn (drawn from `transcript_slice`) |
| `{{SKIPPED_LENSES}}` | lens names with `severity=="skipped"` |
| `{{SUBPROJECT_RELEVANCE}}` | `state.synthesis.subproject_relevance` |
| `{{RECOMMENDATION}}` | `state.synthesis.recommendation` (exact enum string) |
| `{{RECOMMENDATION_RATIONALE}}` | `state.synthesis.recommendation_rationale` |
| `{{DISPOSABLE_NOTEBOOK_NAME}}` / `{{DISPOSABLE_NOTEBOOK_ID}}` | `state.notebooks.disposable.{name,id}` |
| `{{DISPOSABLE_NOTEBOOK_DISPOSITION}}` | `state.notebooks.disposable.disposition` — MUST match state verbatim (see template comment). The briefing line and state MUST agree (eval E1). |
| `{{PRIOR_TESTS}}` | prior-tests list from Phase 0 scan |

**Hard rules (enforced by template comments + runtime check below):**

1. Never write "deleted after briefing finalized" or similar projected language. Phase 6 decides the disposition. Wait for Phase 6, then render.
2. Label the header weights line as `**Weights:**`, never "lens plan" or "lens plan depths".
3. `{{VERDICT}}` must be ≤ 150 words (check with `python3 -c "import sys,re; print(len(re.findall(r'\w+', sys.stdin.read())))"`). If the synthesis verdict is longer, compress it to 2–4 sentences naming what's right, the single most important gap, and the recommendation keyword.

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

**Run-metadata footer.** At the end of the transcripts file, append a metadata block computed *from state.json*, never hardcoded:

```
## Run metadata

- Total subagent spawns: {{state.spawn_count}}
- Breakdown (computed from state.moderator_assessments + state.lenses_completed):
    - Classification: 1
    - Reviewer R1 spawns: {{count of lenses that opened a round-1 Reviewer}}
    - Author R1 spawns: {{count of lenses that received a round-1 Author turn}}
    - Reviewer R>=2 spawns: {{count of moderator_assessments entries with round >= 2}}
    - Author R>=2 spawns: {{count of transcript turns with role=="author" and round >= 2}}
    - Novelty-check runner: {{1 if state.novelty_check.status in ("completed","running","failed") else 0}}
- Lens 7 thematic triangulation: {{"used" if thematic queries recorded else "skipped"}}
- Phase sequence: 0 (input) -> 1 (notebook + upload) -> 2 (classify + plan) -> 3 (lens loop, flat dispatch) -> 4 (synthesis) -> 5 (artifacts) -> 6 (cleanup)
```

**Hard rules:**

1. The "Total subagent spawns" integer MUST equal `state.spawn_count` verbatim (eval E2).
2. The breakdown line integers MUST sum to the Total (eval E3). If they don't sum, your counts are wrong — go back to state and recount; do not adjust the Total to hide the drift.
3. Never write a sentence of the form "1 + 8 + 8 + 3 + 1 = 21" if your lens_plan has 9 lenses. The minimum count for R1 reviewer and R1 author is equal to the number of lenses with `severity != "skipped"` in `state.lenses_completed`.
4. If you cannot reconcile the breakdown to `state.spawn_count`, **abort with `abort_run("spawn_count_reconcile_failed", detail)`** rather than fudging numbers. This is a real integrity signal: the Moderator either bypassed `spawn_agent` (disabling the counter) or produced turns without spawning, either of which is a hollow-run symptom.

Write to `${OUT_ROOT}/transcripts/${FULL_SLUG}_transcripts.md`.

---

## Step 5.3 — Finalize state.json

Run `scripts/enforce_schema.py` against the final state.json. On failure, log error, fix, re-run. (Failure at this point indicates a Moderator bug, not a runtime data issue.)

No mutation of state.json content here beyond the schema-pass check.

---

## Exit

Both artifacts on disk. Return to SKILL.md, which loads `runbooks/phase-6-cleanup.md`.
