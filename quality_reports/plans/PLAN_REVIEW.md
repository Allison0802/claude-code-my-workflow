# Plan Review Log: paper-stress-test Skill Implementation Plan

**Started:** 2026-04-22 21:08 EDT
**Backend:** claude-subagents (Codex MCP not available)
**Plan source:** `quality_reports/plans/2026-04-22_paper-stress-test-implementation.md`
**Working copy:** `quality_reports/plans/FINAL_PLAN.md`
**HUMAN_CHECKPOINT:** true — user approves each round before rewrite

## Context Summary

A 3189-line implementation plan for the `paper-stress-test` Claude Code skill. The skill:
- Uploads a paper to NotebookLM
- Runs a transcript-relay adversarial debate: fresh Opus Reviewer + Sonnet Author spawned synchronously per round (amended from persistent subagents + SendMessage)
- Fires a concurrent `novelty-check` sub-call as a background Agent
- Delivers a structured briefing with cite/build-on/flag/skip recommendation

The plan has 21 tasks (T0, T1, T1.5, T2–T19) covering 4 output files (SKILL.md, agents/reviewer.md, agents/author.md, templates/briefing.md). A key Architecture Amendment (2026-04-22 evening, status: ACCEPTED) redesigned the debate loop from persistent subagents to fresh-spawn-per-round with a per-round Moderator meta-assessment (progressing/stalling/converging → continue/inject_steer/close_lens). All 6 affected tasks (T7, T8, T9, T10, T15, T16) had their original bodies replaced inline.

## Review Criteria (default rubric)

1. Goal clarity
2. Scope control
3. Sequencing
4. Actionability
5. Verification
6. Risk handling
7. Completeness
8. Efficiency

---

## Round 1 (2026-04-22 21:09 EDT)

### Verdict

- Overall: **REVISE**
- Failed criteria: none (but 3 criteria borderline: Actionability, Risk handling, Completeness)
- Passed criteria: Goal clarity, Scope control, Sequencing, Actionability, Verification, Risk handling, Completeness, Efficiency

### Key blockers

1. **No isolated verification of the 7 parsing regexes (T1.5)** — parsing contract is cross-referenced by 5 downstream tasks; a bad regex discovered only at T19 smoke forces expensive task-trace-back. Fix: add T1.6 with 7 fixture strings + test_parsing.sh. Land before T4.
2. **No global spawn/wall-clock budget** — worst case 64+ Agent calls per run. A hanging lens or infinite steer loop has no hard-abort. Fix: add spawn_count + wall_clock_budget_s to state.json in T11/T11.5; abort check at top of each lens iteration.
3. **Moderator context exhaustion ≠ transcript compaction** — T10 compacts prompts sent to subagents; main Claude accumulates all turns + assessments in its own context across 50+ spawns. No mechanism prevents main Claude from hitting its context ceiling mid-run. Fix: either add Moderator self-compact trigger or document explicitly in T18 + caveats.

### Potential pitfalls

1. 4-char/token heuristic in T10 underestimates for JSON-heavy content; log actual vs. estimated at compaction events.
2. Lens 7's Moderator thematic query template is unspecified — T9 says the Moderator queries but not with what prompt structure.
3. T5 background-mode "lazy collection" has no deadline distinguishing "still working" from "silently dead."
4. Sonnet-vs-Opus asymmetry: "conceded" Author severity (→ `critical`) may reflect premature Sonnet capitulation, not real paper flaw. No mitigation.
5. T2 same-slug detection doesn't distinguish abandoned vs. active run — worth ruling out concurrent runs in T18.
6. Resume correctness: `maybe_compact` determinism unspecified — if LLM-based, two resumes from same state produce different running_ctx.
7. T19 smoke paper (Wager & Athey) is a causal-inference paper; 9-lens taxonomy not shown, can't verify all lenses exercisable.
8. T1 SKILL.md frontmatter missing `allowed-tools` declaration for Agent (required per codex-fallback-protocol).

### Reviewer Raw Response

<details>
<summary>Click to expand full Round 1 reviewer response</summary>

## Per-Criterion Assessment

### 1. Goal clarity — **PASS**
The goal states a concrete deliverable (pure-markdown skill, ~700 lines, 4 files) with four clear behaviors (upload to NotebookLM, transcript-relay debate, concurrent novelty-check, structured briefing). Success condition is operationalized through the T19 smoke test with a 15-check pass predicate on a pinned paper.

### 2. Scope control — **PASS**
Scope is bounded to skill scaffolding, persona files, template, and smoke test. No drift into unrelated subprojects (`comparisons/`, `Missing Types/`) or paper revisions. Runtime outputs are properly scoped to `master_supporting_docs/supporting_papers/stress_tests/`. Known caveats list (4 items) is appropriately narrow.

### 3. Sequencing — **PASS**
DAG is explicit and sensible: T0 (probe) → T1 → T1.5 (parsing contract lands *before* T4 consumes it) → T2–T14 linear phase build → T15–T17 parallel persona/template feeders into T7/T12 → T18–T19 last. T1.5 preceding T4 is a non-obvious correctness requirement and is called out. One minor concern (see Pitfalls): T18 resumability depends on state shape finalized in T11 — the DAG shows T11 before T18, which is correct, but dependency is implicit rather than annotated.

### 4. Actionability — **PASS** (borderline)
Most tasks specify files, section placements, cross-references to spec sections, and exit conditions. T8/T9/T10/T11 each name the function to implement and its signature. T19 pins a paper and a verifier script. However, several tasks lean on "spec §N" cross-references (T1.5 cites §3, §9.1.1, etc.) without the spec being visible in the plan — an executor without the spec handy has guesswork. T8's "Moderator read/reason/decide in-context (4 steps)" is slightly hand-wavy; the 4 steps are named but their output schema (what fields land in `moderator_entry`) is only partly specified in the pseudocode.

### 5. Verification — **PASS**
Strong: T19's 15-check `.smoke_verify.sh` with machine-verifiable predicates, two-run matrix (--skip-novelty + full path), and Step 19.6 fix-and-re-run-until-exit-0 loop. Per-task `git commit` checkpoints. Self-review checklist includes placeholder scan and type-consistency sweep. T7 has a specific anti-verification ("no state.author_subagent / state.reviewer_subagent / READY handshake anywhere") which guards against regression to the old architecture.

### 6. Risk handling — **PASS** (borderline)
T18 error table is comprehensive (15 error modes). T9 has a 4-row degradation table for Lens 7. T5 has a fallback from background to synchronous. Fallback semantics for Reviewer/Author spawn failures (retry once → errored lens) are specified. **Gap:** no explicit budget/limit on total Agent spawns or wall-clock — a runaway debate could spawn dozens of subagents before the operator notices. **Gap:** no handling for the case where the Moderator's in-context reasoning itself drifts or the transcript blows past the context window *before* the 80K-char compaction trigger (main Claude's context ≠ transcript char count).

### 7. Completeness — **PASS** (borderline)
Covers upload, debate, novelty, synthesis, write, cleanup, resume, smoke. Missing or under-specified:
- **No unit test layer** between T1 (scaffold) and T19 (end-to-end smoke). Parsing regex correctness is load-bearing (7 patterns in T1.5) but has no isolated verification.
- **Model-name contract** (`model="opus"`, `model="sonnet"`) is asserted but there is no step validating these strings against currently-available Claude Code Agent tool values.
- **No step** addresses what happens if the skill is invoked while another `paper-stress-test` run for the same slug is in progress.

### 8. Efficiency — **PASS**
Fresh-spawn-per-round is intrinsically more expensive than persistent subagents, but the plan acknowledges why and mitigates via compaction (T10) and Lens 7's fixed 3-turn cap. Parallel feeders T15/T16/T17 correct. Novelty-check as background Agent avoids serializing behind debate. No obvious redundancy.

## Overall Verdict: **REVISE**

## Ranked Blockers

1. **No isolated verification of the 7 parsing regexes (T1.5).** Add T1.6 with 7 fixture strings and a 20-line test_parsing.sh that greps each pattern against its fixture. Land before T4.
2. **No global spawn/wall-clock budget.** Add to T11 or new T11.5: `state.spawn_count`, `state.wall_clock_budget_s` (default 1800s), hard-abort with partial-briefing write if exceeded.
3. **Moderator context exhaustion is not the same as transcript compaction.** Either (a) add a documented self-compact trigger for the Moderator, or (b) accept the risk and document it in caveats. Current plan does neither.

## Potential Pitfalls

1. 4-char/token heuristic underestimates for code/JSON-heavy content.
2. Lens 7's Moderator thematic query template unspecified.
3. T5 novelty-check "lazy collection" needs a deadline at Lens 7 start.
4. Sonnet-vs-Opus asymmetry in "conceded" severity assignment.
5. T2 same-slug: abandoned vs. active run distinction unclear.
6. maybe_compact determinism unspecified — resume could produce different running_ctx if LLM-based.
7. T19 smoke paper lenses may not be fully exercisable.
8. T1 SKILL.md frontmatter missing allowed-tools declaration.

## Minimum Changes Required to PASS

1. Add T1.6 (parsing-regex fixtures + test script) between T1.5 and T2.
2. Add to T11 (or new T11.5): spawn budget fields in state.json with enforcement.
3. Amend T10 to specify compaction determinism.
4. Amend T18 to address Moderator context pressure.
5. Amend T1 to include allowed-tools in SKILL.md frontmatter.
6. Amend T9 to specify the thematic query template.
7. Add to T5: background-collection deadline (mark timed_out at Lens 7 start if not yet collected).

</details>

### Status

3 blockers and 8 pitfalls — continuing to rewrite phase (pending user checkpoint approval).

---

## Round 1 Rewrite (2026-04-22 — user-driven, external)

Between Round 1 and Round 2, the user rewrote the plan directly (not via rewriter subagent). The plan grew 3189 → 3539 lines (+350).

### Changes applied (verified in the rewritten plan)

- **T1.6 added** (line 624+) — 7 parsing-regex fixture files + `test_parsing.sh`. Gates T2.
- **Step 3.8.5 added** (line 2279+) — spawn/wall-clock budget fields in state.json (`spawn_count`, `spawn_budget=80`, `wall_clock_start`, `wall_clock_budget_s=1800`, `abort_reason`, `moderator_own_context_est_chars`), `check_budgets_before_lens()` gate, `abort_run()` partial-briefing path.
- **Step 10.1.5 added** (line 2162+) — Moderator own-context soft budget (`MODERATOR_OWN_CONTEXT_SOFT_LIMIT_CHARS = 1_600_000`), tracked via `spawn_agent` wrapper, enforced at lens boundary, with explicit resume-reset semantics.
- **T1 allowed-tools** (line 393) — frontmatter now declares `Bash(*)`, `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Agent`, `mcp__notebooklm__*`.
- **T5 novelty-check deadline** — already in place; `NOVELTY_CHECK_TIMEOUT_SECONDS = 300` enforced at Step 2.7, Step 3.1, and Lens 7 Step 9.1.1.

### Partial/deferred

- **T10 compaction determinism** — PARTIAL; `summary_for_compaction` stored at lens-close (T11 Step 11.1) makes compaction output deterministic by contract, but the T10 pseudocode still shows `summarize_exchange(...)` rather than reading the stored field.
- **T18 Moderator context pressure** — effectively addressed via Step 10.1.5 resume semantics and existing T18 maybe_compact(state.transcript) rebuild, though T18 itself wasn't directly edited.
- **T9 thematic query template** — Moderator is a relay; the THEMATIC_QUERY string is authored by the Reviewer per Format C (T15). Correctly located; no Moderator-authored template needed.

---

## Round 2 (2026-04-22 21:15 EDT)

### Verdict

- Overall: **PASS**
- Failed criteria: none
- Passed criteria: Goal clarity, Scope control, Sequencing, Actionability, Verification, Risk handling, Completeness, Efficiency

### Blocker verification

| Blocker | Status | Evidence |
|---|---|---|
| **B1** (no parsing-regex tests) | **RESOLVED** | T1.6 (line 624+) creates 7 fixture files + `test_parsing.sh`; explicitly gates T2 ("Do NOT proceed to T2 until all 7 PASS", line 817). |
| **B2** (no spawn/wall-clock budget) | **RESOLVED** | Step 3.8.5 (line 2279+) adds full budget schema + `check_budgets_before_lens()` + `abort_run()` partial-briefing path. |
| **B3** (Moderator context exhaustion ≠ transcript compaction) | **RESOLVED** | Step 10.1.5 (line 2162+) explicitly distinguishes the two concerns with separate soft-limit (1.6M chars ≈ 400K tokens) + abort + resume reset. |

### Minimum-changes landing status

| # | Change | Status |
|---|---|---|
| 1 | T1.6 parsing fixtures + test script | **LANDED** |
| 2 | Spawn-budget fields + enforcement | **LANDED** |
| 3 | T10 compaction determinism | **PARTIAL** (contract-level resolved via `summary_for_compaction`; pseudocode cleanup deferred) |
| 4 | T18 Moderator context pressure | **LANDED** (via Step 10.1.5 resume semantics) |
| 5 | T1 allowed-tools in frontmatter | **LANDED** |
| 6 | T9 thematic query template | **LANDED** (as Reviewer-authored, Moderator relays) |
| 7 | T5 novelty-check deadline | **LANDED** (pre-existing at `NOVELTY_CHECK_TIMEOUT_SECONDS = 300`) |

### New blockers introduced by rewrites

**None.** Spawn budget 80 vs worst-case ~65 = ~23% headroom. Moderator context limit 1.6M chars ≈ 400K tokens vs. harness ceiling 1M tokens = ~60% headroom. `spawn_agent` wrapper is drop-in. T1.6 fixtures are POSIX-sh, portable.

### Remaining non-blocking pitfalls (acceptable for v1)

1. 4-char/token heuristic undercount — explicitly acknowledged; soft limit sized with headroom. V1-acceptable.
2. Thematic query template — correctly located in Reviewer Format C; resolved by design.
3. Novelty-check deadline — FIXED.
4. Sonnet "conceded" → critical asymmetry — v1 risk (user sees transcript and can override). Consider stub in "Known caveats".
5. T2 same-slug active-vs-abandoned — partially addressed (stale novelty-check cleanup on resume); no concurrent-run file-lock. V1-acceptable.
6. `maybe_compact` determinism — PARTIAL; pseudocode cleanup at implementation time.
7. T19 smoke 9-lens coverage — narrowly addressed; smoke, not full coverage.
8. allowed-tools — FIXED.

### Minimum additional changes (non-blocking, optional polish)

- T10 pseudocode cleanup: change `summarize_exchange(decisive, …)` to read `lens_record["summary_for_compaction"]`.
- Known caveats stub: add one bullet for Sonnet "conceded" severity asymmetry.
- Concurrent-run guard: optional `flock` or PID sidecar in Phase 0 (two-line change, deferrable).

### Reviewer Raw Response

<details>
<summary>Click to expand full Round 2 reviewer response</summary>

Step 3.8.5 is thorough. The spawn_budget of 80 vs. worst-case ~65 provides ~23% headroom — reasonable. One minor concern: the enforcement only fires at lens boundaries, so a runaway retry loop *within* a single lens could exceed the budget before the next boundary check. But the plan acknowledges this implicitly ("Optional: check spawn budget mid-lens too (not required)"). Acceptable.

## Per-criterion scoring (strict, against rubric)

1. Goal clarity — PASS. Goal unchanged, unambiguous, architecture amendment banner is explicit.
2. Scope control — PASS. `--spawn-budget` explicitly marked "out of scope for v1". Budget fields don't expand feature scope.
3. Sequencing — PASS. T1.6 cleanly inserted between T1.5 and T2; DAG updated to show `T1.5 → T1.6 → T2`.
4. Actionability — PASS. T1.6 has concrete fixture strings + runnable harness; Step 3.8.5 pseudocode executable. Prior borderline concerns resolved since parsing contract §N is now fixture-backed.
5. Verification — PASS. T1.6 adds dev-time gate that must pass before T2. T19 pass predicate unchanged and still machine-checkable.
6. Risk handling — PASS. Spawn / wall-clock / Moderator-context budgets now enforced with `abort_run` + partial briefing + resume. Prior "no spawn budget" gap closed.
7. Completeness — PASS. allowed-tools landed (line 393); parsing-regex test harness landed; concurrent-run case still partial but all Round 1 minimum-changes addressed.
8. Efficiency — PASS. No unnecessary work added. T1.6 fixture test is cheap (~1s) and prevents T19 churn. Moderator-context estimator is coarse-but-monotone by design.

## Overall verdict: PASS

All 3 blockers resolved. 6 of 7 minimum-changes LANDED; the 7th (T10 determinism) is PARTIAL at the pseudocode level but resolved by written contract — non-blocking for v1. No new blockers introduced.

STOP condition met: every criterion passes AND no blocker remains.

</details>

### Status

**LOOP TERMINATED — PASS at Round 2 of MAX_ROUNDS=4.**

`FINAL_PLAN.md` contains the approved plan. Three low-severity non-blocking items documented above for optional polish during implementation:
1. T10 pseudocode cleanup to literalize the `summary_for_compaction` contract.
2. Known-caveats stub for Sonnet "conceded" severity asymmetry.
3. Optional `flock`/PID sidecar for concurrent-same-slug protection.

---

