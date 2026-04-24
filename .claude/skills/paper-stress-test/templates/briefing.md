# Stress-Test Briefing: {{PAPER_TITLE}}

**Authors:** {{PAPER_AUTHORS}}
**Year:** {{PAPER_YEAR}}
**Source:** {{PAPER_SOURCE}}
**Stress-test date:** {{STRESS_TEST_DATE}}
**Detected paper type:** {{DETECTED_TYPE}}
**Depth:** {{DEPTH}}
**Weights:** {{WEIGHTS_LIST}}
**Reviewer model:** {{REVIEWER_MODEL}}
**Author-surrogate model:** {{AUTHOR_MODEL}}

<!--
Substitution rules (enforced by runbooks/phase-5-artifacts.md §Step 5.1):
- {{DEPTH}} is the integer from state.invocation.depth. Do NOT append parenthetical weight lists here.
- {{WEIGHTS_LIST}} is a slash-joined list of per-lens weights from state.lens_plan[*].weight,
  in lens_id order (0..8). Example: `medium/heavy/medium/heavy/medium/light/heavy/heavy/medium`.
- The label MUST be "Weights:" — never "lens plan" or "lens plan depths".
-->

---

## TL;DR verdict

{{VERDICT}}

<!--
{{VERDICT}} MUST be ≤ 150 words. If synthesis produced longer prose, the Moderator
compresses it to ≤ 150 words at artifact-render time (phase-5 Step 5.1). Keep it to
2–4 sentences covering (a) what the paper gets right, (b) the one most important gap,
(c) the recommendation keyword. Push detail into per-lens findings below, not here.
-->

---

## Top 5 killer questions

{{TOP_KILLER_QUESTIONS}}

---

{{NOVELTY_SECTION}}

---

## Severity summary

{{SEVERITY_TABLE}}

---

## Per-lens findings

{{PER_LENS_FINDINGS}}

---

## Skipped lenses

{{SKIPPED_LENSES}}

---

## Relevance to user's sub-projects

{{SUBPROJECT_RELEVANCE}}

---

## Recommendation

**{{RECOMMENDATION}}**

{{RECOMMENDATION_RATIONALE}}

---

## Disposable notebook

- **Name:** {{DISPOSABLE_NOTEBOOK_NAME}}
- **ID:** `{{DISPOSABLE_NOTEBOOK_ID}}`
- **URL:** https://notebooklm.google.com/notebook/{{DISPOSABLE_NOTEBOOK_ID}}
- **Disposition:** {{DISPOSABLE_NOTEBOOK_DISPOSITION}}

<!--
{{DISPOSABLE_NOTEBOOK_DISPOSITION}} MUST be read verbatim from
state.notebooks.disposable.disposition. The allowed terminal values are:
  - "deleted"  — the notebook was deleted in Phase 6.
  - "kept"     — the notebook was retained (default for `flag`; fallback on delete failure).
  - "promoted" — sources were copied to the thematic notebook, then the disposable deleted.
NEVER hardcode "deleted after briefing finalized" or any string that contradicts state.
If disposition is "kept", say "kept (not deleted)". If "promoted", say
"promoted to thematic notebook <name>". If "deleted", say "deleted in Phase 6 cleanup".
The briefing line and the state.json field MUST agree word-for-word (eval E1).
-->


---

## Prior stress-tests of this paper

{{PRIOR_TESTS}}
