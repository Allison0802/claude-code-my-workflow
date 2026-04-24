# Plan: Flatten `paper-stress-test` dispatch to single-level sequential

**Status:** DRAFT — awaiting user approval
**Date:** 2026-04-24
**Author:** Claude (Opus 4.7, 1M ctx)
**Depends on:** [2026-04-23_paper-stress-test-skill-refactor.md](2026-04-23_paper-stress-test-skill-refactor.md) (prior refactor — schema, runbooks, validator, Lens 7 rewrite). This plan should be executed AFTER that refactor is committed.

---

## 1. Problem

The Apr-23 parallel-dispatch refactor (session S217) specified a 3×3 architecture: top-level Moderator spawns 3 group moderator subagents; each group moderator spawns Reviewer + Author sub-subagents. **This architecture cannot execute in Claude Code.**

### Evidence

**Authoritative Claude Code docs** (confirmed 2026-04-24 via claude-code-guide):

> Subagents cannot spawn other subagents. This is an architectural restriction, not a permissions issue. Even if you add `tools: Agent` to a custom subagent's frontmatter, the Agent tool is stripped at runtime. The restriction applies uniformly — there's no override or workaround via tool declaration.

**Empirical evidence from three stress-test runs** (all post-S217):

| Run | Fallback the skill improvised at runtime |
|-----|------------------------------------------|
| Wager 2018 | Moderator impersonated Author as `moderator_notebook_proxy` (v1 hollow-run pattern) |
| Schenk 2024 | Moderator held the thematic notebook and did the Lens 7 query itself (I-5 violation) |
| Cui 2023 | Moderator gave up on group topology entirely; ran 27 flat Reviewer+Author calls with no transcript recording. State file contains `invocation.degradation_mode: "flat_in_moderator_dispatch"` self-describing the failure |

Every invocation since S217 has been hitting the same wall and inventing a new workaround. The drift patterns we debugged in the Apr-23 refactor are *symptoms*; the architecture itself is the root cause.

---

## 2. Goal

Specify and implement a **flat, single-level dispatch**: the top-level Moderator owns the per-lens debate loop directly. No group moderators. No nested subagents. No partial state files.

**Non-goal:** preserving wall-clock parallelism across groups. It's not achievable in this runtime; accept the ~3× wall-clock increase. Per-lens work is still parallelized where it makes sense (Reviewer + Author within a round can't overlap because the Author needs the Reviewer's question).

---

## 3. Architecture (target)

```
Top-level Moderator (skill execution context, has Agent access)
  │
  ├── Phase 0–2: input, NotebookLM setup, classification, plan  (unchanged)
  │
  └── Phase 3: lens loop
       │
       for lens in active_lenses:
         │
         for round in 1..lens.depth:
           ├── Agent(subagent_type="general-purpose", model="opus",    prompt=reviewer_prompt)
           └── Agent(subagent_type="general-purpose", model="sonnet",  prompt=author_prompt)
         │
         Moderator reads turns in-context, appends canonical turn_records
         and one moderator_assessments entry per round.
         │
       Persist state.json after each lens closes.
```

**Everything the Apr-23 refactor specified about shape still holds:**
- Canonical `turn_record` (`role`, `round`, `content`, `timestamp_iso`, `lens_id`, optional `model` + `notebooks_granted`)
- Five invariants (I-1..I-5)
- Seven gates (G-3a, G-3b, G-3c, G-3-schema, G-3-model, G-3-notebook, G-3-mod-content, G-4a, G-5a)
- JSON Schema `state.schema.json` (schema_version=2)
- Lens 7 design (Reviewer owns thematic notebook)

Only the *dispatcher* changes.

---

## 4. Files to modify

### Delete (2 files)

- `.claude/skills/paper-stress-test/agents/group_moderator.md` — architecture this describes cannot execute.
- `.claude/skills/paper-stress-test/runbooks/phase-3-merge.md` — nothing to merge in flat dispatch. The content about `abort_run` and budget enforcement moves into `phase-3-debate.md`.

### Rewrite (2 files)

- `.claude/skills/paper-stress-test/SKILL.md`
  - §Workflow: collapse "Phase 3a/b/c/d" rows into two: "Phase 3 (lens loop)" and "Phase 3 (Lens 7 — special case)".
  - §Entry sequence: remove the merge step.
  - §What moved where: update pointers.
  - §Anti-rationalization/MUST-NOTs: the "MUST dispatch 3 group-agents in parallel" rule is replaced with "MUST dispatch Reviewer and Author via Agent within the Moderator's own context; MUST NOT attempt nested subagents — the runtime strips Agent from subagents".
  - Target: stay ≤ 300 lines (currently 216, likely becomes ~200).

- `.claude/skills/paper-stress-test/runbooks/phase-3-debate.md`
  - Remove: "parallel 3×3 group dispatch" architecture section, `Step 3.4` group-dispatch block, `Step 3.4.5` aggregate-vs-local gate distinction (only aggregate remains), anti-rationalization rows about sequential dispatch being wrong.
  - Add: a short section on the Claude Code nested-subagent restriction, citing the official docs. "This is why we use flat dispatch."
  - The per-lens loop (current §3.5) stays as-is — it was always the canonical spec; it just runs in the Moderator now.
  - Merge step: reduced to "persist state.json after each lens", which the per-lens loop already does.
  - Budget gates: absorb from phase-3-merge.md (`check_budgets_before_dispatch` becomes `check_budgets_before_lens`, called at top of each lens iteration).
  - Target: ≤ 250 lines (currently 318; will shrink after dropping group content).

### Minor edits (2 files)

- `.claude/skills/paper-stress-test/runbooks/phase-3-lens7.md`
  - Change "group-2 partial" references to "lens record in state.lenses_completed".
  - Clarify that the Moderator is the dispatcher, not a group moderator.
  - Everything about the Reviewer-owns-thematic design is unchanged — that's a shape rule.
  - Target: stays ~200 lines.

- `.claude/skills/paper-stress-test/scripts/validate_state.py`
  - Remove `--partial-group` mode (no partials exist in flat dispatch).
  - Remove `--check-merge` mode (same reason).
  - Keep all gate functions (`check_g3a`, `g3b`, `g3c`, `g3_schema`, `g3_model`, `g3_notebook`, `g3_mod_content`, `g4a`, `g5a`) — they all operate on the merged/flat state file, which is now the only state file.
  - Adjust `check_g3c`'s spawn_count floor: was `3 + 2*depth_sum` (3 group dispatches + 2 per depth unit); becomes `2*depth_sum + 1` (2 per depth unit + 1 Phase-2a classification; no group dispatches).
  - Target: drop from 385 → ~280 lines.

### Unchanged (5 files)

- `schema/state.schema.json` — shape rules are dispatch-agnostic.
- `templates/transcript-slice.json` — ditto.
- `parsing/transcript-patterns.md` — ditto; Pattern 8 (group-moderator return payload) becomes dead code but keeping it in docs as "deprecated in 2026-04-24 flat-dispatch refactor" is fine.
- `runbooks/phase-0-input.md`, `phase-1-notebooklm.md`, `phase-2-classify-plan.md` — no group references.
- `runbooks/phase-3-compaction.md` — token-based compaction applies regardless of dispatcher.
- `runbooks/phase-4-synthesis.md`, `phase-5-artifacts.md`, `phase-6-cleanup.md` — unchanged.
- `agents/reviewer.md`, `agents/author.md` — they were already dispatched from the Moderator in the current broken architecture's fallback; the rewrite just makes this official.
- `scripts/enforce_schema.py` — unchanged.

### Net delta

- **-2 files** (group_moderator.md, phase-3-merge.md)
- **-400 lines** (conservatively, from rewrites + validator trim)
- **0 new behavior** (the skill already does this under the fallback path)

---

## 5. Migration steps (ordered, reversible)

Each step is an isolated commit. `git revert` undoes any single step cleanly.

1. **Write a session log** documenting the architectural finding (this step is what the user is reviewing now; the content is this plan).
2. **Commit the Apr-23 refactor as-is.** That work stands on its own; it doesn't need the dispatch fix to be correct.
3. **Delete `agents/group_moderator.md`.** The skill no longer references anything it describes (after step 4).
4. **Delete `runbooks/phase-3-merge.md`.** After absorbing its budget-abort content into phase-3-debate.md.
5. **Rewrite `runbooks/phase-3-debate.md`** to describe flat dispatch. Merge in budget gates. Keep per-lens loop.
6. **Update `runbooks/phase-3-lens7.md`** with minor language changes (group → moderator).
7. **Rewrite `SKILL.md` workflow table** and entry sequence.
8. **Update `scripts/validate_state.py`** — remove partial/merge modes, adjust spawn_count floor.
9. **Regression run** on a fresh paper (user-driven). This is Step 8-equivalent for the new architecture.
10. **Log + commit** the dispatch-flattening work as a second commit.

Steps 3–8 are all file edits, no runtime dependencies. Can be done in one ~2-hour session once approved.

---

## 6. Verification criteria

Before committing the dispatch-flattening change:

- [ ] No `.md` file in `.claude/skills/paper-stress-test/` references `group_moderator`, `3×3`, `partial state`, or `group_0/1/2.json` (except in historical change-log notes).
- [ ] SKILL.md ≤ 300 lines; phase-3-debate.md ≤ 250 lines.
- [ ] `validate_state.py` no longer accepts `--partial-group` or `--check-merge`; syntax parses; all existing tests pass.
- [ ] Fresh stress-test run on a new paper produces:
  - `run_status: completed` (not aborted).
  - All 9 lenses in `lenses_completed` with non-empty `transcript_slice` (≥ 3 entries each).
  - `transcript` (flat) has one entry per turn across all lenses.
  - `moderator_assessments` has at least one entry per lens.
  - No `invocation.degradation_mode` field (because there's no broken architecture to degrade from).
  - Content validator: **0 violations**.
  - Schema validator: **schema OK**.
- [ ] Wager 2018 and Schenk 2024 state files still fail the validators (regression guard — the content gates remain tight).

---

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Flat dispatch is ~3× slower wall-clock than the (impossible) 3×3 design. | Accept. Parallelism was aspirational; the skill has never actually run it. User can compare Cui (~40 min under the degraded fallback) to post-fix runs to confirm no real slowdown. |
| `check_budgets_before_lens` firing mid-loop aborts a run in the middle. | Same behavior as current `check_budgets_before_dispatch`. Partial-mode Phase 5 runs before termination; user can `--resume`. |
| Existing state files (Wager, Schenk, Cui) become harder to interpret because they reference deprecated architecture in their `invocation.degradation_mode` etc. | Don't rewrite them. They're historical artifacts. The Apr-23 plan already committed to flagging old files rather than grandfathering. |
| Something else in the Moderator's context overflows during sequential runs (since it now holds 27+ turn records instead of 3 group returns). | The compaction runbook (`phase-3-compaction.md`) already handles this — was written for the group-agent context but applies equally to Moderator context. Verify compaction fires during the regression run. |

---

## 8. Open questions for user

1. **Regression paper for Step 9.** Same `Papers/2411.01381v1.pdf` as before, or a different one? (Cui and Schenk already exercised causal-inference and new-estimator lenses respectively; `2411.01381v1.pdf` would add a third data point.)
2. **Keep deprecated Pattern 8** (group-moderator return payload) in `parsing/transcript-patterns.md`, or delete it? I'd keep it with a deprecation note for audit trail. Your call.
3. **Timing.** Do the dispatch-flattening work in the next session, or after you've had a chance to commit the Apr-23 refactor first and see it in git log?

---

## 9. Approval

Reply with any of:

- **"approved, proceed"** — I'll execute steps 3–8 in the next session (after you commit the Apr-23 refactor) and hand you back a regression-ready skill.
- **"approved, but change X"** — tell me what to change.
- **"hold"** — park the plan; come back to it later.

Or just commit the Apr-23 refactor first and treat this as pre-queued for a future session.
