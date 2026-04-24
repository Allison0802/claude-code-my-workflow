# Session Log: paper-stress-test SKILL.md refactor

**Date:** 2026-04-23
**Branch:** main
**Plan:** [quality_reports/plans/2026-04-23_paper-stress-test-skill-refactor.md](../plans/2026-04-23_paper-stress-test-skill-refactor.md)

## Goal

Shrink `.claude/skills/paper-stress-test/SKILL.md` from 2,012 lines / 113 KB to ≤ 300 lines by moving phase logic into per-phase runbooks that Claude loads lazily. Prevent the "long-skill drift" failure that produced the hollow-run lenses 6–8 in the Wager 2018 stress-test run.

## Approach

10-step reversible migration, each step an isolated commit. SKILL.md becomes orchestration-only (arguments, lens list, invariants, phase dispatch). Detail lives in `runbooks/`, `schema/`, `templates/`, `parsing/`. Validator extended to catch schema drift and Author-role hollow-run patterns.

## Rationale

Evidence in `master_supporting_docs/supporting_papers/stress_tests/state/wager_2018_estimation_inference_2026-04-23_state.json`:

- Two different `transcript_slice` shapes within one run (lens 0–5 vs 6–8)
- `"model": "moderator_notebook_proxy"` filling the Author role for lenses 6–8 — hollow-run violation
- `moderator_assessments` empty stub for lens 7; missing entries for lens 6 and 8
- `notebooks.disposable.disposition: "pending"` on a completed run
- Existing gate G-3a checks transcript_slice length ≥ 3 but not shape uniformity or Author provenance

All five symptoms are "second code path forgot a rule the first code path followed" — classic signature of instructions too long to enforce consistently.

## Key decisions (confirmed by user)

- **I-1:** Failed Author spawn → lens marked `skipped`, never proxied.
- **I-5:** Reviewer has paper + thematic notebook. Author has paper + disposable only. Moderator has neither. Thematic findings go in Reviewer turn content.
- **Retroactive validation:** Option A — new validator flags existing state files; one-time audit report committed alongside refactor.
- **Regression paper:** `Papers/2411.01381v1.pdf`.

## Session timeline

- [17:50] User flagged wager_2018 state file for review; I identified 5 drift symptoms and diagnosed long-skill cause.
- [18:05] User asked if SKILL.md is too long; I said yes with evidence.
- [18:10] Plan drafted to `quality_reports/plans/2026-04-23_paper-stress-test-skill-refactor.md`.
- [18:20] User answered Q2 (thematic→Reviewer, not Moderator), Q3 (Option A), Q4 (2411.01381v1.pdf). Plan revised.
- [18:25] User confirmed invariants I-1..I-5.
- [18:27] Session started. Step 1 complete. Moving to Step 2.

## Open blockers

None currently.

---

## 2026-04-24 follow-up: architectural flat-dispatch refactor

After the Apr-23 refactor committed its schema/runbook/validator work, two regression runs (Schenk 2024, Cui 2023) exposed that the v1 skill's **3×3 parallel group-agent architecture cannot run in Claude Code**. The top-level Moderator could spawn group moderators, but those group moderators could not themselves spawn Reviewer/Author sub-subagents — Claude Code architecturally strips the `Agent` tool from subagents regardless of `tools:` frontmatter. Confirmed authoritatively via claude-code-guide:

> Subagents cannot spawn other subagents. This is an architectural restriction, not a permissions issue. Even if you add `tools: Agent` to a custom subagent's frontmatter, the Agent tool is stripped at runtime.

Every stress-test since the Apr-23 S217 refactor was hitting this wall and improvising a different fallback each time (Wager proxied Author; Schenk had moderator query thematic; Cui gave up groups entirely). The drift patterns debugged in the Apr-23 refactor were *symptoms*; this architectural issue was the root cause.

### Flat-dispatch refactor (this session)

Plan: [quality_reports/plans/2026-04-24_paper-stress-test-flat-dispatch.md](../plans/2026-04-24_paper-stress-test-flat-dispatch.md)

**File delta:**

- **Deleted:** `agents/group_moderator.md` (154 lines), `runbooks/phase-3-merge.md` (138 lines).
- **Rewritten:** `runbooks/phase-3-debate.md` — removed 3×3 dispatch, added flat per-lens loop, absorbed budget gates from phase-3-merge.md (323 lines).
- **Minor edits:** `runbooks/phase-3-lens7.md` (language tweaks — "group moderator" → "Moderator", "group-2 partial" → "state.lenses_completed").
- **Minor edits:** `SKILL.md` — workflow table collapsed, entry sequence shortened, architectural note added on Claude Code's nested-subagent restriction.
- **Updated:** `scripts/validate_state.py` — removed `check_partial_group`, `check_merge_consistency`, `validate_partial`, `validate_merge` functions and their CLI modes (`--partial-group`, `--check-merge`). Simplified `main()` to single-path dispatch. Adjusted G-3c spawn_count floor from `3 + 2*depth_sum` (3×3) to `2*depth_sum + 1` (flat).

**Verification (2026-04-24 23:30):**

- Validator parses: OK.
- Schenk state: 2 violations (both G-3-notebook on moderator-thematic drift — historical, correctly flagged, cannot be fixed without re-running).
- Wager state: 242 violations (regression guard holds — gates remain tight).
- SKILL.md: 216 lines. phase-3-debate.md: 323 lines. validate_state.py: 446 lines (down from 385 by net).

**What is unchanged from Apr-23:** schema, templates, parsing patterns, phase-0/1/2/4/5/6 runbooks, enforce_schema.py, the five invariants I-1..I-5, Lens 7's Reviewer-owns-thematic design. All those are shape-of-data rules, dispatch-agnostic.

**Next step:** user-driven regression on a fresh paper under flat dispatch. Expect: 0 content violations, 0 schema violations, no `invocation.degradation_mode` field (no broken architecture to fall back from).
