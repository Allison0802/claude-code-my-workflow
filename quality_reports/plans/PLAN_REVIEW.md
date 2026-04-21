# Plan Review Log: method-evolve Skill Design Specification

**Started:** 2026-04-21 16:00 EDT
**Backend:** claude-subagents (Codex MCP not available)
**Plan source:** `quality_reports/specs/2026-04-21_method-evolve-design.md`
**Working copy:** `quality_reports/plans/FINAL_PLAN.md`
**Focus per user:** potential pitfalls or unclarity

## Context Summary

The plan specifies a cross-project Claude Code skill, `method-evolve`, that drives
an evolutionary feature-set search for statistical methods (v1: IPW propensity
features in the Missing Types sub-project). It has four phases
(scan → setup → run → promote/report), a config-driven grammar engine, a
hybrid Mac/Longleaf runtime model, a JSONL program DB, and a subagent proposer.

## Review Criteria (default rubric)

1. Goal clarity
2. Scope control
3. Sequencing
4. Actionability
5. Verification
6. Risk handling
7. Completeness
8. Efficiency

User emphasis: **pitfalls and unclarity**.

---

## Round 1 (2026-04-21 16:05 EDT)

### Verdict
- Overall: **REVISE**
- Failed criteria: Sequencing, Actionability, Verification, Risk handling, Completeness
- Passed criteria: Goal clarity, Scope control, Efficiency (with caveats)

### Key blockers
1. IBS prerequisite circular dependency (§7.1, §14) — `setup` cannot run until IBS is added, but smoke test runs inside `setup`. Ownership unresolved.
2. Recovery-ratio denominator not guarded (§7.3) — collapses when `IBS_CCA ≈ IBS_oracle`.
3. Grammar validator algorithm under-specified (§5) — "R-formula AST walker" unsound without named parser library, transform-arg semantics, and fail-closed rules.
4. `promote` wrapper + results-flow-back is a handwave (§10.1) — no per-variant path namespacing, no `ingest` step to patch `full.*` in DB.
5. Cross-generation state leakage under `mclapply` (§10.2) — no parent-only DB writer, no atomic `variant_id` allocation, no per-child seed derivation.
6. Baseline scenario-match asserted but not detected (§6, §13) — no metadata scheme, no key-comparison algorithm.

### Potential pitfalls (22 items — key highlights)
- Gate thresholds at B=50 produce ~50% false-rejection rate for coverage gate (pitfall 3)
- Zero-gate-passer deadlock in sampler (pitfall 4)
- Subagent may emit malformed JSON; no robust-parse contract (pitfall 7)
- Phase 2 smoke test too narrow — never exercises checkpoint-resume, promote, or zero-pass case (pitfall 9)
- `EVOLVE_STATE.json` schema undefined; mid-generation resumability unclear (pitfall 16)
- Two-layer `${...}` substitution engine not labeled; re-run-`setup` behavior unspecified (pitfall 18)
- `paths.out_dir` lacks sequence suffix required by CLAUDE.md for same-day re-runs (pitfall 22)
- Cross-project reusability claim (§3) contradicted by feature-set-specific grammar (§5) and prompt (§9) (pitfall 15)
- Pseudo-Brier vs. IPCW-Brier decision still "open" in §7.1 — must be pinned (pitfall 13)

### Reviewer Raw Response

<details>
<summary>Click to expand full Round 1 reviewer response</summary>

## Per-criterion results

- **Goal clarity — PASS.** §1 states a clear outcome ("cross-project skill that applies an evolutionary code-search loop … to statistical methods") and §7.3 defines `recovery_IBS` as the primary success signal. The success condition ("top-K gate-passing variants promoted to full tier") is implicit but discernible.
- **Scope control — PASS.** §2 lists honest non-goals (no PDF auto-discovery, single slot kind, single population, no direct API proposer, no reviewer loop). v1 is bounded to `feature_set` kind for IPW.
- **Sequencing — FAIL.** §14 declares "IBS must be added to the MC output before `setup` can run" but §4 lists `scan → setup` as the second entry point and §7.1 also calls IBS a prerequisite; the plan never defines when, by whom, or in which commit the IBS patch lands. This is a circular scheduling hazard (see Blocker 1).
- **Actionability — FAIL.** Several core mechanisms are underspecified: the "R-formula AST walker" (§5, no library, no algorithm), the subagent JSON schema (§8.1, §9 — only an example, not a schema), the `promote`-wrapper generation (§10.1, "pins `FEATURE_SET_FILE` per top-K variant" without saying how), and the `${…}` substitution engine (§6, bindings and freeze-point are not fully pinned). An engineer cannot implement §5 or the wrapper without guessing.
- **Verification — FAIL.** Phase 2 smoke test (§4) runs "one generation with `batch_size = 2`" and is claimed to "validate the full loop" — but it does not exercise `promote`, does not exercise checkpoint-resume-after-crash, does not exercise Longleaf path, and does not exercise early-stop. §4 Phase 3 lists "Evaluate" but no per-phase verification acceptance criteria (what output constitutes "this generation succeeded"?). No overall success criterion beyond the leaderboard exists.
- **Risk handling — FAIL.** Major risk paths are missing: (a) zero variants pass gates in a generation (sampler requires "top-3 gate-passers" — what if none exist?), (b) pathological recovery-ratio denominator when `IBS_CCA ≈ IBS_oracle`, (c) one `mclapply` worker poisoning others, (d) OneDrive file-lock contention on DB writes during long sleep/wake, (e) subagent emitting malformed JSON (no parsing contract in §9), (f) reused `setup` clobbering a frozen `${run_date}` folder.
- **Completeness — FAIL.** Missing pieces: DB-write concurrency model (JSONL append from `mclapply` children is not obviously safe), lockfile discipline, variant-ID allocation under parallelism, baseline scenario-match detection algorithm (§6 asserts requirement but no detection), results-flow-back contract from Longleaf (§10.1 only covers outbound), and explicit cost/time budget (§6 has `max_variants: 200` but no wall-clock model).
- **Efficiency — PASS (with caveats).** Screen vs. Full tier split is sensible; not running nested `mclapply` is correct; reusing existing submit script is pragmatic. Caveat: the negative-example list grows unbounded (§9) and parent-variant context can bloat — not addressed.

## Overall verdict

**REVISE**

## Ranked blockers

1. **IBS prerequisite circular dependency (§7.1, §14).** §14 says `setup` cannot run until IBS is added; §4 Phase 2 (Scaffold) says the smoke test runs inside `setup`. The plan never resolves which side owns the patch, whether `scan` is permitted before IBS exists, whether the reference `.claude/skills/method-evolve/examples/missing-types-ipw/config.yaml` (§13) can ship before IBS is committed, and what happens if `scan` detects missing IBS mid-run. **Minimum fix:** Pin IBS as a Phase −1 task owned by a specific script patch, gate `setup` on an explicit `has_ibs` check, and remove the circular claim.

2. **Recovery-ratio denominator is not guarded (§7.3).** `recovery_IBS = (IBS_CCA − IBS_IPW) / (IBS_CCA − IBS_oracle)`. When `IBS_CCA ≈ IBS_oracle` the denominator collapses to MC noise, yielding huge-magnitude ratios that dominate the sampler. Values `>1` are flagged for "manual inspection" but nothing is said about denominators near zero, negative, or with large MC variance. **Minimum fix:** Specify a denominator-floor check (e.g., reject the scenario as non-informative if `|IBS_CCA − IBS_oracle| < ε`) and a fallback fitness when the denominator is degenerate.

3. **Grammar validator algorithm is under-specified (§5).** "Minimal R-formula AST walker … no code execution required" — but R's formula language is not a context-free grammar you can fully AST-walk without evaluating (e.g., `ns(df=3)`, `I(x^2)`, and arbitrary calls). The plan doesn't pick a library (`codetools`, `rlang::parse_expr`, `Rscript -e 'quote(...)'`), does not specify safe-eval behavior, and does not say what happens when the subagent emits a term like `poly(x, 3)` that's syntactically legal but outside `slot.transforms`. **Minimum fix:** Name the parser (e.g., `rlang::parse_expr` + an allowlist tree walk), define the handling of transform arguments (e.g., `ns(..., df=3)` must exactly match whitelisted form `ns(df=3)`), and spec the fail-closed behavior on parse error.

4. **`promote` wrapper and results-flow-back is a handwave (§10.1).** The plan says the skill "generates a promote-variant wrapper that pins `FEATURE_SET_FILE` per top-K variant" via the existing `submit_missing_types_ipw.sh`. This risks SLURM array-index collisions (if the existing submit uses arrays), overlapping `results_missing_types/*.rds` output paths, and makes no statement about how Longleaf results return to the Mac DB. §10.1 explicitly covers outbound (`rsync` + `ssh` + `sbatch`) but not inbound. **Minimum fix:** Define the per-variant output-path namespace, array-index allocation, and a `method-evolve ingest` (or equivalent) command that pulls remote results back and patches `full.*` DB fields.

5. **Cross-generation state leakage under `mclapply` (§10.2).** The plan says `n_workers = 5` and writes JSONL to `PROGRAM_DB.jsonl` after evaluating each variant. `mclapply` children that race on the same JSONL file produce interleaved/truncated writes; variant-RDS filenames depend on `VARIANT_ID` allocation which is not made thread-safe; and `set.seed(YYYYMMDD)` once at the driver top does not isolate seeds across concurrent children. **Minimum fix:** Spec (a) a parent-process-only DB writer (children return records up, parent appends), (b) a pre-generation atomic `variant_id` allocation block, and (c) per-child seed derivation (e.g., `seed_i = base_seed + variant_id_hash`).

6. **Baseline scenario-match detection is asserted but not implemented (§6, §13).** `scenario_match_required: true` — but the plan does not say how the skill inspects `results_missing_types/oracle_hard.rds` to verify it was generated at matching `N`, `SCENARIO_NAME`, and DGP. §6 hints "if only full-tier baselines exist, setup warns and offers to run a scenario-matched baseline pass" — which offer mechanism? **Minimum fix:** Require the evaluator to embed scenario metadata in its output RDS, and specify the exact key comparison that `setup` performs.

## Potential pitfalls

1. **Hidden state / cross-generation leakage (§10.2).** `compute.screen.n_workers = 5`: per blocker 5, no spec for seed isolation, DB write serialization, or variant-ID atomicity. `~/.method-evolve-cache/${run_date}_${name}` is shared by all workers and survives across `run` invocations — nothing is said about cleanup or stale-file detection.
2. **Recovery ratio near-degeneracy (§7.3).** See blocker 2. Also: the plan never says whether `IBS_CCA` and `IBS_oracle` are fixed values (computed once from baseline RDS) or re-estimated each generation; MC noise in those denominators directly couples into every variant's score.
3. **Gate thresholds are asserted without defense (§7.2).** `|bias| < 0.02`, `coverage ∈ [0.93, 0.97]` (a narrow 4-pp window at B=50 — likely to randomly reject correct methods), `c_index ≥ C_CCA − 0.01`. At B=50, coverage has SE ≈ 0.03 under the null — `[0.93, 0.97]` will reject a nominally correct method with probability ~50%. **No variant may pass gates** in many generations, which silently kills the sampler in §8.2.
4. **Zero-gate-passer deadlock (§8.2).** Sampler spec: "top-3 gate-passers by primary fitness + 1 random gate-passer." If generation 0 produces zero gate-passers, the prompt in §9 has no parents to show. Not addressed.
5. **Grammar validator fragility (§5).** See blocker 3. In addition: §5 bullet 3 says "Every `transform(base)` must use a transform from `slot.transforms`" — but the whitelist contains `"I(^2)"` and `"ns(df=3)"` as strings, which are not R callables; no syntax is given for matching them against real formula terms like `I(age^2)` or `ns(age, df=3)`. False positives and false negatives are both inevitable.
6. **Subagent prompt bloat (§9).** "Parent variants … + up to 5 failed examples." Over 20 generations with 10 variants each, the *DB* grows to 200 entries, but the parent-context stays bounded at 4 — OK. However the plan nowhere caps the total negative-example set across turns, and §9 says "the loop learns the boundary" by showing failures — implying persistent failure memory. Context-bloat risk is real and cache-miss cost not budgeted.
7. **Malformed subagent JSON (§9).** "Returns JSON array of `batch_size` candidate feature sets" — no schema; §8.1 shows a DB record, not a proposer output schema. What if Claude emits ` ```json` fences, commentary prose before/after, a single object instead of array, or malformed escapes? No robust-parse contract.
8. **Phase 0 `scan` heuristic false-positives (§4 Phase 0 table).** The regex `feature_set = `, `formula = ~`, `model.matrix(` will match any such line in the codebase — multiple candidate slots is inevitable if the script has >1 estimator (which it does — IPW, RPM, DR). No deterministic conflict resolution.
9. **Phase 2 smoke test is too narrow (§4 Phase 2.4).** `batch_size = 2`, one generation cannot exercise checkpoint recovery, early-stop, zero-gate-passer, `promote`, Longleaf wrapper, or DB concurrency at `n_workers = 5`.
10. **Parallelism on Mac failure modes (§10.2).** Mac sleep during a 2–3-min eval will suspend `mclapply` children; no spec for detecting stale workers. Worker crash is recorded as `eval_error` but nothing is said about preventing that worker from taking out its siblings when it died holding the DB append file descriptor.
11. **`promote` results-flow-back (§10.1).** See blocker 4.
12. **IBS prerequisite scheduling (§7.1, §14).** See blocker 1.
13. **Pseudo-Brier vs. IPCW-Brier open decision (§7.1).** Primary metric — every score, gate denominator, and leaderboard ranking depends on it. Leaving this "open" means implementation may start with the wrong choice.
14. **Promote wrapper pinning of `FEATURE_SET_FILE` (§10.1).** See blocker 4. Added: §6 `results_file_pattern` uses `${SCENARIO_NAME}`, but at full-tier the scenario is a *grid*, so a single substitution cannot uniquely name outputs. Namespace collision is likely.
15. **Cross-project reusability claim (§3, §5, §9).** §3 declares "no IPW-, RPM-, or Cox-specific logic." But §5 grammar hardcodes R-formula parsing and §9 prompt says "feature sets" — claim of domain-agnosticism is stronger than the design supports.
16. **Resumability promise (§10.2).** No `EVOLVE_STATE.json` schema shown. "Partial generations are rolled back on restart" — wastes MC time on passing variants.
17. **Terminology drift (§4, §6, §10.2).** Relationship between CLI `max_gens` and config `budget.max_generations` not stated. Cumulative or reset?
18. **Config substitution semantics (§6).** Two substitution layers (setup-time freeze vs. per-variant) not labeled. Re-run-`setup` behavior unspecified.
19. **Prerequisite file naming and ownership (§6).** `oracle_hard.rds` consumed by skill but not owned; no version/metadata check against stale baselines.
20. **Subagent JSON contract (§9).** No schema given — only "strict JSON schema" promised.
21. **Baseline scenario-match (§6).** Already covered in blocker 6.
22. **Same-day re-run folder collisions.** `paths.out_dir: "${run_date}_${name}"` lacks the sequence-number suffix required by `CLAUDE.md` "Skill Output Storage."

## Minimum changes required to pass

- [ ] Resolve blocker 1: designate Phase −1 (pre-skill) IBS patch task; `scan` becomes safe no-op that warns; reference config in §13 becomes illustrative until IBS lands.
- [ ] Resolve blocker 2: specify denominator-floor for `recovery_IBS`; name a fallback fitness when `|IBS_CCA − IBS_oracle| < ε`.
- [ ] Resolve blocker 3: pin R parser (e.g., `rlang::parse_expr`), define allowlist tree-walk rules for transform-with-arguments, spec fail-closed behavior.
- [ ] Resolve blocker 4: define `promote` wrapper's per-variant file pinning, array-index/output-path namespacing, AND a back-flow command (`ingest`) that patches `full.*` in DB.
- [ ] Resolve blocker 5: spec parent-only DB appends, atomic `variant_id` allocation, per-child seed derivation.
- [ ] Resolve blocker 6: scenario-match metadata embedded in baseline RDS; exact key comparison in `setup`.
- [ ] Sampler fallback when zero gate-passers.
- [ ] Reconsider or justify gate thresholds at B=50 given false-rejection rate of coverage gate.
- [ ] Robust JSON parsing contract: strip code fences, array root, retry-with-correction.
- [ ] Pin pseudo-Brier vs. IPCW-Brier now.
- [ ] Define `EVOLVE_STATE.json` schema explicitly; commit to mid-generation resumability semantics.
- [ ] Resolve CLI `max_gens` vs. config `max_generations` precedence.
- [ ] Document two-layer `${…}` substitution engine; re-run-`setup` behavior.
- [ ] Add sequence-number suffix convention to `paths.out_dir`.
- [ ] Expand Phase 2 smoke test to include checkpoint-resume, `promote` dry-run, zero-gate-passer synthetic case.
- [ ] Acknowledge or fix cross-project reusability claim vs. feature-set-specific grammar/prompt.

</details>

### Status

Failed criteria (Sequencing, Actionability, Verification, Risk handling, Completeness) and 6 ranked blockers → continuing to rewrite phase.

---

## Round 1 Rewrite (2026-04-21 16:15 EDT)

Rewriter subagent produced a complete revised plan (473 → 720 lines) saved to `FINAL_PLAN.md`.

### Rewriter claim summary (self-reported — verification by round-2 reviewer)

- **Blockers resolved (claimed):**
  - B1: Phase −1 `prereq` command + `has_ibs` version-stamp gate
  - B2: `denom_floor_epsilon = 0.002` + `neg_ibs_ipw` fallback metric
  - B3: `rlang::parse_expr` recursive walker; typed transform descriptors replace fragile strings
  - B4: `promote_manifest.json` + unique `output_namespace` + new `ingest` command patches `full.*` fields
  - B5: Parent-only DB writer; flock-guarded atomic `variant_id`; per-child seed via `digest::digest2int`
  - B6: `*.meta.json` sidecar schema + key-by-key comparison in `setup`

- **Pitfalls materially reduced (claimed):** All 22 addressed, including P3 gate-noise-budget with split screen `[0.91, 0.99]` vs full `[0.93, 0.97]`; P7 JSON parse 5-step contract; P13 pseudo-Brier pinned; P16 `EVOLVE_STATE.json` schema; P22 `-NN` suffix.

- **Hard constraints preserved:** cross-project evolutionary-search skill, v1 = IPW feature search in Missing Types, MC as critic, Claude Opus subagent proposer (explicit `model: "opus"`), two-tier compute, in-session checkpointed runs, JSONL program DB.

---

## Round 2 (2026-04-21 16:25 EDT)

### Verdict
- Overall: **PASS**
- Failed criteria: none
- Passed criteria: Goal clarity, Scope control, Sequencing, Actionability, Verification, Risk handling, Completeness, Efficiency

### Ranked blockers (remaining)
None. Reviewer verified each of B1–B6 with a section citation confirming the fix landed (not merely renamed).

### Potential pitfalls (remaining — all non-blocking)

1. **Phase 0 `scan` conflict resolution (§4/§5).** `scan` does not explicitly state how to pick among multiple candidate `target_script`s when multiple match. Deferred to user interview in `setup`; a one-line tie-break rule would be a micro-improvement.
2. **`--refreeze` data safety (§7.2).** Flag "explicitly overwrites frozen values" but does not state whether prior `variants/` and `PROGRAM_DB.jsonl` are preserved or invalidated. Potential footgun for resumable runs; implementation should either refuse when DB is non-empty or force a new `-NN` folder.
3. **Gate-threshold trade-off framing (§8.2).** Noise budget justified; does not explicitly acknowledge that widened screen gate admits more biased variants. Minor; full tier catches these.
4. **Zero-gate-passer smoke still runs MC (§14).** "Synthesized by tightening gates" reuses the 2-sim/100-subject reduced run — acceptable.

### Reviewer Raw Response (Round 2)

<details>
<summary>Click to expand full Round 2 reviewer response</summary>

## Per-criterion results

- **Goal clarity** — PASS. §1 clearly names v1 target (IPW propensity feature-set search) and configurable intent; §2 lists non-goals. Quote: "v1 target: IPW propensity feature-set search in the Missing Types sub-project."
- **Scope control** — PASS. §2 non-goals retained; §3 tightens cross-project claim (P15); §16 defers v2 items. Quote: "domain-agnostic only for `slot.kind = feature_set`."
- **Sequencing** — PASS. §4 ordering (`scan → prereq → setup → run → promote → ingest → report`) is explicit and checkpointed; §5 is Phase −1 with a clear halt rule. Quote (§4): "`setup` calls `prereq` internally and refuses to continue until every prerequisite check passes."
- **Actionability** — PASS. §5.1 names the exact script and line-stamp (`ibs-patch-version: 1`); §6.2 gives concrete `rlang::parse_expr` walker code; §9.3 shows the atomic-ID R block; §10.2 gives 5-step JSON parse contract; §11.3 fully specifies `promote` and `ingest`; §15.1 shows the state JSON schema.
- **Verification** — PASS. §5.1 check 2 runs a 2-sim smoke; §8.2 adds `--gate-calibration` dry-run against CCA baseline; §14 expands Phase-2 smoke to checkpoint-resume + promote dry-run + synthetic zero-gate-passer.
- **Risk handling** — PASS. Degenerate-scenario halt (§8.3), per-variant fallback metric (§8.3), zero-gate-passer sampler fallback (§9.5), subagent parse retry-once-then-checkpoint (§10.2), worker isolation via subprocess (§11.2), `config_sha` mismatch refusal on resume (§15.2), baseline scenario-metadata hard-fail on mismatch (§5.2), `flock` on accidental double-run (§9.3).
- **Completeness** — PASS. Schema (§7), grammar (§6), DB (§9), state (§15), outputs (§12), prereq (§5), promote/ingest (§11.3) all specified; decisions log (§17) pins 17 items including pseudo-Brier (P13).
- **Efficiency** — PASS. Variant RDS cache kept out of OneDrive (§11.1); B=50 screen vs tight full tier split (§8.2); top-3+1-random sampler (§9.5); negative-example cap of 5 (§10.3); early stop via `early_stop_after` (§7).

## Overall verdict

PASS

## Blocker verification

- B1 landed: §5.1 names `Missing Types/scripts/R/missing_types_method_comparison_ipw.R`, defines `ibs-patch-version: 1` header stamp, `setup` fail-closed rule.
- B2 landed: §8.3 gives `denom_floor_epsilon: 0.002` + `neg_ibs_ipw` fallback + `reject_and_halt` scenario-level.
- B3 landed: §6.2 named `rlang::parse_expr` with recursive walker; §6.3 typed descriptors (name/head/arity/args/kwargs) replace old strings.
- B4 landed: §11.3 promote wrapper (manifest, `output_namespace`, rsync/ssh/sbatch commands) + ingest (walk manifest, load RDS, `.tmp`+rename DB patch). SLURM array formula `v * S + s`.
- B5 landed: §9.2 "Only the driver's main R process appends"; §9.3 flock-guarded atomic ID allocation; §9.4 seed via `digest::digest2int(paste0(parent_seed, "/", variant_id))`.
- B6 landed: §5.2 `*.meta.json` sidecar schema (scenario_name, n_subjects, n_sims, dgp_version, evaluator_sha, ibs_patch_version); hard-fail on hard-key mismatch, warn on evaluator_sha.

## Minimum changes required to pass

None — the plan is ready to execute. The four low-severity items above can be addressed opportunistically during implementation; none rise to blocker level.

STOP condition met: every criterion passes AND no blocker remains.

</details>

### Status

**LOOP TERMINATED — PASS at Round 2 of MAX_ROUNDS=4.**

`FINAL_PLAN.md` contains the approved plan. Four low-severity non-blocking items documented above for optional polish during implementation.



