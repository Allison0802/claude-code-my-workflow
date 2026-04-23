# Plan — paper-stress-test: Sequential Reviewer → 3×3 Parallel Lens Dispatch

## Context

The `paper-stress-test` skill (`.claude/skills/paper-stress-test/SKILL.md`, 1888 lines) currently runs a single Reviewer subagent that walks sequentially through 9 adversarial "lenses" (identification, ML, validity, etc.), debating a persistent Author-surrogate subagent lens-by-lens. This is the bottleneck for interactive paper reads — most of the wall-clock time is one sequential Reviewer working through lens 0 → lens 8 with full depth-2 debates.

**Change:** Dispatch **3 parallel group-agents, each owning 3 lenses**, preserving per-lens Reviewer↔Author dialectic with depth 1–2. The Moderator (the skill itself) waits for all 3 groups to return, merges their partial state files, and synthesizes the top-5 killer questions + recommendation at the end.

**Goal:** ~50% wall-clock reduction on a typical stress-test run while preserving all five hollow-run gates (G-3a/b/c, G-4a, G-5a) and the existing briefing output contract.

## Approach

- **3 group-agents, fixed lens assignment**
  - Group A: lenses 0, 1, 2 (statistical/identification)
  - Group B: lenses 3, 4, 5 (ML/generalization)
  - Group C: lenses 6, 7, 8 (validity; isolates lens-7 thematic_query complexity to one group)
- **Each group-agent** iterates its 3 lenses internally. For each lens: spawn a Reviewer sub-subagent → spawn an Author sub-subagent for retrieval → Reviewer judges → if `depth=2` and judgment ∈ {evaded, handwaved}, second round.
- **Partial state files.** Each group writes `${OUT_ROOT}/state/${FULL_SLUG}_group_${N}.json` atomically. Moderator merges after all 3 return. Avoids concurrent-write race on the canonical state file.
- **Pattern 8** added to the Parsing Contract: JSON return payload from each group-agent (`{group_id, lens_records: [...], local_gate_results, partial_state_path}`). Moderator buffers by `group_id` until all 3 arrive.
- **G-3a split** into G-3a-local (run inside each group-agent between its 3 lenses) and G-3a-aggregate (run by Moderator post-merge). Defense-in-depth.
- **G-3c spawn_count formula updated**: `spawn_count >= 3 + sum(2·depth)` (3 group-agents + per-lens Reviewer/Author pairs).
- **Resumability coarsened** to group-level: on resume, re-dispatch any group whose partial file is missing or has < 3 records. No mid-group resume.
- **`reviewer.md` and `author.md` unchanged** — both are already stateless per spawn and reused inside each group-agent.

## Files to modify

| File | Change | Approx lines |
|------|--------|--------------|
| `SKILL.md` | Phase 3 refactor: parallel dispatch, Pattern 8, G-3a split, G-3c formula, Resumability rewrite, anti-rationalization table | Rewrites L736–1471 and L1845–1886 |
| `agents/group_moderator.md` | **NEW**. Group-agent persona: input contract, 3-lens loop, Reviewer/Author sub-subagent calls, lens-7 thematic branch, local gates, JSON return | ~200 lines |
| `agents/reviewer.md` | No changes (reused as-is) | — |
| `agents/author.md` | No changes (reused as-is) | — |
| `templates/briefing.md` | No changes (operates on final merged state) | — |
| `scripts/validate_state.py` | Update G-3c formula; add `--partial-group N` validation mode; add merge-consistency check (9 lens_ids = union of 3 partials, no duplicates) | ~30 lines |
| `tests/fixtures/group_payload_valid.json` | **NEW** — Pattern 8 positive fixture | ~60 lines |
| `tests/fixtures/group_payload_missing_lens.json` | **NEW** — Pattern 8 negative (2 records, not 3) | ~40 lines |
| `tests/fixtures/merged_state_from_3_groups.json` | **NEW** — merge-consistency fixture | ~120 lines |
| `tests/test_parsing.sh` | Extend with 3 new assertions for Pattern 8 + merge-consistency | ~15 lines |

## Implementation order

1. Write `agents/group_moderator.md` first — defines the contract everyone else references.
2. Insert Pattern 8 at `SKILL.md:~165` (end of Parsing Contract section).
3. Rewrite `SKILL.md` Phase 3 intro (L736–745) + lens-loop skeleton (L803–835) for parallel dispatch.
4. Split G-3a into local + aggregate; replace body of Steps 3.5/3.6 (L856–1230) with one-paragraph pointer to `group_moderator.md`.
5. Rewrite Step 3.8 (L1344–1402) persistence → partial-file pattern; update G-3c formula at L1404–1471.
6. Rewrite Resumability section (L1845–1886) for group-level semantics.
7. Update `scripts/validate_state.py` (G-3c formula, partial-group mode, merge check).
8. Add 3 test fixtures + extend `tests/test_parsing.sh`.
9. Run `validate_state.py` against the Lin 2021 and Loe 2025 sabotage fixtures to confirm no regressions.

## Anti-rationalization table (to add in SKILL.md §Phase 3 intro)

| Rationalization | Counter |
|-----------------|---------|
| "I'll dispatch sequentially to stay under the spawn budget." | Budget is group-aware (3 + 2·Σdepth); sequential saves zero tokens. |
| "One group failed — I'll run the other 2 sequentially to be safe." | Retry the failed group. Never silently degrade to sequential. |
| "I'll merge partial state inside a group-agent." | Group-agents write their own partial only. Moderator is the sole merger. |
| "I'll use 9 parallel lens-agents for more parallelism." | User explicitly chose 3×3. 9-way fan-out triples persona-prompt tokens and fragments budget gates. |

## Writing-skills TDD (Iron Law: test before edit)

**RED — baseline test:** Prompt a subagent with the current `SKILL.md` + a paper + an 8-minute wall-clock budget. Assert the first Phase 3 tool call is a single message with **3 concurrent Task dispatches**. Expected failure: current main dispatches one Task for lens 0 and waits. This is the RED bar — run and record verbatim rationalizations ("I'll start with lens 0 since they need to go in order").

**GREEN — minimal edit:** Three MUST-NOT callouts in Phase 3 intro + Pattern 8 + anti-rationalization table. Rerun RED scenario → pass.

**REFACTOR — close loopholes:** Capture any new rationalizations from GREEN re-run (e.g., "I'll dispatch 3 but wait between groups") and add corresponding rows to the anti-rationalization table. Iterate until bulletproof.

## Verification (end-to-end)

1. **Unit:** `bash tests/test_parsing.sh` — 7 existing patterns + 3 new Pattern-8/merge assertions.
2. **Validator:** `python scripts/validate_state.py --partial-group 0 <fixture>` for all 3 groups; `python scripts/validate_state.py <merged_state>` for aggregate gates.
3. **Live run:** Re-run paper-stress-test against Lin 2021 (already done sequentially on 2026-04-23, state archived at `master_supporting_docs/supporting_papers/stress_tests/state/lin_2021_state.json`). Compare briefing.md output: top-5 questions and recommendation must match within dialectic noise (same recommendation enum; same severity distribution ±1 per bucket).
4. **Timing:** Record wall-clock from Phase 3 start to Phase 4 start. Expect ≥40% reduction vs. sequential baseline.

## Session logging + plan duplication

Per project `CLAUDE.md` and `.claude/rules/session-logging.md`:
- Copy this plan to `quality_reports/plans/2026-04-23_paper-stress-test-parallel-dispatch.md` at start of implementation.
- Append incremental entries to `quality_reports/session_logs/2026-04-23_paper-stress-test-loe-2025.md` as edits land.

## Open items to confirm at approval

- **Group C load-balancing.** Lens 7 (thematic NotebookLM query) is the slowest lens. Current assignment puts it in Group C alongside 6 and 8. If empirical timing shows Group C dominates wall-clock, consider swapping lens 8 (cheap) with lens 0 to rebalance. Deferred until after first live run.
- **No per-lens resume.** Coarsening resume to group-level is a real regression for users who crash 4 hours in. Documented prominently in §Resumability; accepted per user's architectural choice.
