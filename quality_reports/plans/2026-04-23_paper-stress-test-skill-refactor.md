# Plan: Refactor `paper-stress-test` skill to stop drifting mid-run

**Status:** REVISED 2026-04-23 — user answered Q2, Q3, Q4; Q1 (invariants) still open
**Date:** 2026-04-23
**Author:** Claude (Opus 4.7, 1M ctx)
**Motivation:** SKILL.md has grown to 2,012 lines / 113 KB. The `wager_2018_estimation_inference_2026-04-23_state.json` run exhibited the classic "long-skill drift" signature: lenses 0–5 followed one set of rules, lenses 6–8 followed a different set (different `transcript_slice` shape, moderator impersonating the Author, missing `moderator_assessments` entries, disposable notebook never cleaned up).

---

## 1. Goal

Shrink the *single file Claude must hold in working memory at once* to ~300 lines without losing any skill behavior. Move detail into lazily-loaded runbooks and into a strict validator. The model should never have to keep nine lenses × three roles × two phase shapes coherent in its head — the validator and the runbook structure should enforce coherence.

**Non-goal:** changing the skill's externally visible behavior (same arguments, same artifacts, same lens plan). This is pure refactor.

---

## 2. Evidence of drift in the Wager run

From `master_supporting_docs/supporting_papers/stress_tests/state/wager_2018_estimation_inference_2026-04-23_state.json`:

| Symptom | Location in state | Root cause in current SKILL.md |
|---|---|---|
| Two different `transcript_slice` schemas within one run | Lens 0–5 use `{role, round, content, timestamp_iso}`; lens 6–8 use `{turn, role, content}` with no timestamp | Schema not authoritative; scattered across Phase 3.5 and Phase 3.6 with no single reference |
| Author role filled by `moderator_notebook_proxy` for lenses 6–8 | `transcript[]` entries for lens 6/7/8 have `"model": "moderator_notebook_proxy"` | Lens 7 triangulation path (Step 3.6) was bolted on later; the "Author is always a Sonnet subagent" invariant is documented in prose but not gated |
| `moderator_assessments` empty stub for lens 7, missing for lens 6 and 8 | `{"lens_id": 7, "round": null, "content": "", "timestamp_iso": ""}` | Per-lens assessment-emission logic duplicated across Steps 3.5 and 3.6 |
| `notebooks.disposable.disposition: "pending"` on a completed run | Root of state.json | Phase 6 Step 6.4 cleanup path conditioned on user prompt that apparently didn't fire |
| Hollow-run gate G-3a exists but didn't trigger for lenses 6–8 | `scripts/validate_state.py` checks `len(transcript_slice) ≥ 3` but not shape uniformity or Author-role provenance | Gate design checks counts, not schema identity or role identity |

None of these symptoms are random; all five are "the second code path forgot a rule the first code path followed." That is the signature of instructions too long to enforce consistently.

---

## 3. Proposed architecture

```
.claude/skills/paper-stress-test/
├── SKILL.md                      (≤ 300 lines — orchestration only)
├── schema/
│   └── state.schema.json         (authoritative JSON Schema for state.json)
├── runbooks/
│   ├── phase-0-input.md          (≤ 150 lines)
│   ├── phase-1-notebooklm.md     (≤ 150 lines)
│   ├── phase-2-classify-plan.md  (≤ 200 lines)
│   ├── phase-3-debate.md         (≤ 200 lines — dispatch + debate only)
│   ├── phase-3-lens7.md          (≤ 150 lines — positioning lens, isolated)
│   ├── phase-4-synthesis.md      (≤ 150 lines)
│   ├── phase-5-artifacts.md      (≤ 100 lines)
│   └── phase-6-cleanup.md        (≤ 100 lines)
├── agents/
│   ├── reviewer.md               (unchanged)
│   ├── author.md                 (unchanged)
│   └── group_moderator.md        (trimmed — move parsing rules to runbooks)
├── parsing/
│   └── transcript-patterns.md    (the 8 regex patterns, moved out of SKILL.md)
├── templates/
│   ├── briefing.md               (unchanged)
│   └── transcript-slice.json     (NEW — the canonical transcript record)
├── scripts/
│   ├── validate_state.py         (extended — see §5)
│   └── enforce_schema.py         (NEW — runs state through JSON Schema)
└── tests/                        (unchanged)
```

### 3.1 What stays in SKILL.md (≤ 300 lines)

1. Frontmatter + description (so skill discovery still works).
2. Arguments table.
3. The 9-lens list (name, weight default, depth default).
4. The phase dispatch table — six rows, each pointing to `runbooks/phase-N-*.md` with a one-line summary of what that phase produces.
5. The four global invariants (stated once, bold):
   - **I-1.** Every Author turn is produced by a Sonnet Author-surrogate subagent. No exceptions. No proxies. A failed spawn → lens marked `skipped`, never proxied.
   - **I-2.** Every `transcript_slice` record conforms to `templates/transcript-slice.json`. No alternative shapes.
   - **I-3.** Every closed lens emits exactly one `moderator_assessments` entry per round where the moderator spoke.
   - **I-4.** Before Phase 6 exits, `notebooks.disposable.disposition ∈ {deleted, kept, promoted}` — never `pending`.
   - **I-5.** (Role-notebook isolation.) Reviewer has paper + thematic notebook. Author has paper + disposable notebook only. Moderator has neither notebook. Thematic findings appear only in Reviewer turn content.
6. The defer-tool preamble.
7. A "Read the runbook for the current phase before executing it" instruction at the top.

Everything else moves to runbooks.

### 3.2 What the runbooks contain

Each runbook is phase-scoped and assumes the invariants above are already in Claude's context (because SKILL.md loaded them). Runbooks can be opened/closed as Claude traverses phases — they don't all need to be resident at once.

### 3.3 The canonical `transcript_slice` record

`templates/transcript-slice.json`:

```json
{
  "role": "reviewer|author|moderator",
  "round": 1,
  "content": "<verbatim turn content>",
  "timestamp_iso": "2026-04-23T20:33:43Z",
  "lens_id": 0
}
```

No `turn` field. No `close_lens_mode` side-channel. No `moderator_notebook_query` role. If a lens needs notebook consultation, that happens *inside* the moderator's turn and is summarized *in the content*, not recorded as a separate role.

This is the single place future drift is prevented: the validator rejects any record that doesn't match this shape.

---

## 4. Lens 7 (positioning) — special-case, cleanly

Lens 7 is currently the worst offender because it needs (a) a Reviewer question, (b) a thematic-notebook query, (c) an Author defense, (d) a confrontation round. The current skill puts all four into the main debate loop with conditional branches.

**Proposed split (revised 2026-04-23 per user):**

- Lens 7 runs through `runbooks/phase-3-lens7.md`, not the standard debate loop.
- The thematic-notebook query is **the Reviewer's responsibility**, not the moderator's. The Reviewer subagent is given access to the thematic notebook (via its prompt) and formulates the positioning question using that context. The result summary + verbatim quote are logged inside the **Reviewer's** turn `content`, not as a separate role.
- **Role boundaries are bright-line:**
  - *Reviewer* = has the paper + thematic notebook (external context, prior work).
  - *Author* = has the paper + disposable notebook *only*. Never sees thematic findings. The Author speaks for the Author.
  - *Moderator* = has neither notebook; synthesizes from the turns themselves.
- If the Reviewer subagent spawn fails, Lens 7 is marked `"evidence": "unavailable"`, `"severity": "skipped"`. **No proxy.**
- If the Author subagent spawn fails, same rule — skipped, never proxied.
- This asymmetry (Reviewer has external context, Author does not) is intentional and mirrors real adversarial peer review: the reviewer brings outside knowledge; the author defends only what's in the paper.

---

## 5. Extended validator (`validate_state.py`)

Add these gates to the existing file:

- **G-3c: schema uniformity.** Every `transcript_slice[i]` must match `templates/transcript-slice.json` field-for-field. Reject `turn`, `close_lens_mode`, `moderator_notebook_query`, `moderator_thematic_query`, `moderator_notebook_proxy`, `moderator_direct`, `action`, `notebook_id`, `query`, `result_summary`, `result_verbatim` at the record level. (Those belong *inside* `content`.)
- **G-3d: Author provenance.** For each lens, there must exist at least one `transcript[]` record with `role: "author"` AND `"model"` matching the Sonnet Author-surrogate model string. Reject `moderator_notebook_proxy` anywhere as an Author.
- **G-3d-bis: Reviewer provenance and notebook isolation.** For each lens, the Reviewer turn must have `"model"` matching the Opus Reviewer model string. Author turns must never reference the thematic notebook id in their prompt trace — enforce by storing a per-subagent `notebooks_granted` field in the transcript and rejecting any Author record where `thematic_notebook_id ∈ notebooks_granted`.
- **G-3e: moderator_assessments completeness.** For each lens in `lenses_completed`, count moderator turns in `transcript_slice`; `moderator_assessments` for that lens must have exactly that many entries, none with empty `content`.
- **G-3f: notebook disposition resolved.** If `run_status == "completed"`, then `notebooks.disposable.disposition ∈ {deleted, kept, promoted}`.

The validator runs at the end of Phase 3 (blocking — can't proceed to Phase 4 with drift) and again at end of Phase 6.

A companion `enforce_schema.py` does a pure JSON Schema check against `schema/state.schema.json` — both validators must pass.

---

## 6. Migration plan (ordered)

Each step is small, verifiable, and reversible by `git revert`.

1. **Extract invariants.** Write the four global invariants into a scratch note and confirm with me they are correct before any file moves.
2. **Create `schema/state.schema.json`** by inferring from existing working state files (the five good lenses in `wager_2018`, plus any prior clean runs). Test by running it against a known-good run.
3. **Create `templates/transcript-slice.json`** and `parsing/transcript-patterns.md`. Verify they match what the current group_moderator produces.
4. **Split phases into runbooks**, phase by phase, *without* changing logic. Each runbook is a literal cut-paste from SKILL.md with inbound/outbound contracts stated at the top (what state fields exist when the runbook starts, what it must set before returning).
5. **Rewrite SKILL.md** to the 300-line skeleton + phase dispatch table.
6. **Extend `validate_state.py`** with gates G-3c..G-3f.
7. **Rewrite Lens 7** as `runbooks/phase-3-lens7.md` with no `moderator_notebook_proxy` anywhere. Delete the code path that produced it.
8. **Run regression**: re-stress-test *one* paper (not Wager — a fresh one) end-to-end. Inspect the state file against the new schema. Require: no validator gate fires, all 9 lenses have real Author turns, disposition resolved.
9. **Update tests** in `tests/` to cover the four invariants.
10. **Log in `quality_reports/session_logs/`** and commit.

---

## 7. Files that will change

- `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md` — shrink from 2012 → ~300 lines
- `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/scripts/validate_state.py` — extend
- `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/agents/group_moderator.md` — trim parsing blocks out
- `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/tests/*` — add invariant tests

## 8. Files that will be created

- `.claude/skills/paper-stress-test/schema/state.schema.json`
- `.claude/skills/paper-stress-test/runbooks/phase-0-input.md`
- `.claude/skills/paper-stress-test/runbooks/phase-1-notebooklm.md`
- `.claude/skills/paper-stress-test/runbooks/phase-2-classify-plan.md`
- `.claude/skills/paper-stress-test/runbooks/phase-3-debate.md`
- `.claude/skills/paper-stress-test/runbooks/phase-3-lens7.md`
- `.claude/skills/paper-stress-test/runbooks/phase-4-synthesis.md`
- `.claude/skills/paper-stress-test/runbooks/phase-5-artifacts.md`
- `.claude/skills/paper-stress-test/runbooks/phase-6-cleanup.md`
- `.claude/skills/paper-stress-test/parsing/transcript-patterns.md`
- `.claude/skills/paper-stress-test/templates/transcript-slice.json`
- `.claude/skills/paper-stress-test/scripts/enforce_schema.py`

## 9. Verification criteria (done-definition)

- [ ] SKILL.md ≤ 300 lines.
- [ ] No runbook > 200 lines.
- [ ] Fresh end-to-end stress-test run produces a state file that passes both `validate_state.py` and `enforce_schema.py` with zero warnings.
- [ ] Re-running the validator against the *existing* `wager_2018...state.json` reports the exact drift we identified (sanity check that gates catch known bugs).
- [ ] Every lens in the fresh run has a real Sonnet Author subagent in its `transcript[]` provenance.
- [ ] Disposable-notebook disposition is never `pending` at end of run.
- [ ] Existing tests in `tests/` still pass.

---

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Refactor breaks mid-way and leaves skill in worse state | Each migration step in §6 is an isolated commit; revert is one command. |
| Moving parsing rules out of SKILL.md breaks the group_moderator's ability to produce correctly-shaped output | Before Step 4, run the existing agent against a fixture paper and snapshot its output; after Step 4, diff. |
| Gate G-3d rejects legitimate runs that used the old proxy path | Intended — those runs *were* broken. We can retroactively mark old state files `schema_version: "0"` and skip them for validation. |
| User wants different invariants than the four I picked | Step 1 blocks on confirmation before any file moves. |

---

## 11. Open questions for user

1. **Are the four invariants (I-1 .. I-4) correct?** In particular: is there *any* legitimate scenario where a lens should close without a real Author subagent? (If yes, the right answer is `"severity": "skipped"`, not a proxy — but confirm.)
2. ~~Scope of Lens 7 change~~ — **Resolved 2026-04-23.** Author speaks only for the Author; thematic-notebook findings are routed to the Reviewer. Role boundaries are bright-line (see §4).
3. ~~Retroactive validation~~ — **Resolved 2026-04-23.** Option A: new validator flags existing state files, and a one-time audit report is committed alongside the refactor listing which prior stress-tests were hollow-run-contaminated and should be re-run.
4. ~~Regression paper~~ — **Resolved 2026-04-23.** `Papers/2411.01381v1.pdf`.

---

## 12. Rough time/effort estimate

- Step 1 (invariants): 10 min (conversation).
- Step 2 (schema): 30 min.
- Step 3 (templates, patterns): 30 min.
- Step 4 (split into runbooks): 60–90 min.
- Step 5 (rewrite SKILL.md): 45 min.
- Step 6 (extend validator): 60 min.
- Step 7 (rewrite Lens 7): 45 min.
- Step 8 (regression run): variable — depends on how long one stress-test takes, plus inspection.
- Step 9 (tests): 30 min.
- Step 10 (commit + log): 10 min.

Total ~5–6 hours of focused work, spread across however many sessions you prefer.

---

## 13. Approval

Reply with any of:

- **"approved, proceed"** — I'll run the migration in order, pausing at Step 1 to confirm invariants.
- **"approved, but change X"** — tell me what to change.
- **"hold"** — I'll park the plan and we can discuss.
