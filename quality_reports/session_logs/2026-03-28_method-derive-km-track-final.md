# Session Log: 2026-03-28 — /method-derive KM Track Final + Pilot Re-verification

## Goal

Close out the within-type KM derivation track (3 rounds, all REDERIVE) and complete
the /method-derive skill workflow: domain review, pilot run, SLURM update.

## Context

Continuation of a prior session (context exhaustion). The AJ-based derivation
(FINAL_DERIVATION.md, 7.4/10, MAX_ROUNDS=5) was already finalized in prior sessions.
The new KM derivation track (estimand P(T_k^(1) ≤ τ) instead of AJ CIF) reached 3
rounds of Codex review, all REDERIVE, and was abandoned as irresolvable.

---

## Key Decisions

### KM Track Abandoned

**Decision:** Within-type KM derivation track abandoned after 3 rounds (2.3→3.1→3.8/10).

**Reason:** The depleted first-event risk set Y^(k)(t) = I(C_i ≥ t, T_k,i^(1) ≥ t) requires
knowing which events are type k (to determine if subject has had prior type-k event). With
missing types, Y^(k)(t) cannot be computed. No assumption resolves this:
- A0 (sparse recurrence): prevents second type-k events per subject, NOT depletion after first event. Codex counterexample: two subjects with events at t=1, t=2; first-event KM gives S(2)=0, undepleted gives S(2)=1/4.
- A_Poisson (non-contagion): equates hazard VALUES but not counting process increments. E[dN_k(s)] ≠ E[dN_k^(1)(s)] — they differ by factor S_k(s-|W_i) for all s > 0.

**Resolution:** AJ estimand P(T≤τ, K=k) ≈ P(T_k^(1)≤τ) + O(τ²) under A0 for small windows.

### Double-Robustness Scenario Added

Domain reviewer (Issue 2.1) identified that all MAR scenarios use correctly specified outcome model, so DR consistency could be attributed to the outcome model alone rather than double robustness.

**Action:** Added `n200_dr_misspec_outcome` scenario (X2-only outcome model, correctly specified propensity). Pilot result: bias 0.23%/0.10% (K=1/K=2) — confirms A4b double robustness.

---

## Files Changed

| File | Change |
|------|--------|
| `Missing Types/derive-logs/round-3-km-math-review.md` | Created — Codex Round 3 KM review (3.8/10, REDERIVE) |
| `Missing Types/derive-logs/MATH_REVIEW_SUMMARY-km.md` | Created — full analysis of why KM track is irresolvable |
| `Missing Types/derive-logs/score-history.md` | Updated — added KM track (2.3→3.1→3.8, all REDERIVE) |
| `Missing Types/derive-logs/DERIVE_STATE.json` | Updated — phase=pilot, pilot_result=PASS 20/20 |
| `Missing Types/derive-logs/simulation.R` | Updated — added `dr_misspec` scenario, domain review comments (Issues 1.1-1.4, 2.1), Last Updated header |
| `Missing Types/derive-logs/simulation_longleaf.R` | Updated — Last Updated header |
| `Missing Types/derive-logs/run_full.slurm` | Updated — array 1-9 → 1-10 for new scenario |
| `Missing Types/derive-logs/pilot_results.md` | Updated — appended 2026-03-28 re-run results (20/20) |
| `quality_reports/simulation_code_review_2026-03-28.md` | Created — domain reviewer output |

---

## Pilot Results (2026-03-28 Re-run)

**20/20 PASS** across all scenarios:
- Max relative bias: 1.07% (n50 scenario) — well below 5% threshold
- SE ratio: 0.944–1.065 (target [0.90, 1.10])
- Coverage: 0.930–0.964 (target [0.91, 0.99])
- Double robustness confirmed: misspecified outcome (X2 only) + correct propensity → bias < 0.25%

---

## Open Issues

1. **SLURM not deployed** — full run (1000 reps, n=200-500) not yet submitted to Longleaf. Run when cluster access available.
2. **Theoretical SE formula** — open problem in FINAL_DERIVATION.md; bootstrap is empirical device only.
3. **AJ derivation score 7.4/10** — MAX_ROUNDS reached; remaining gaps are the SE/variance dimension (5.5/10) and a deferred influence function derivation.

---

## Production Integration (same session, follow-up)

**Goal:** Port fractional AJ estimator from `derive-logs/simulation.R` into production `functions.R`.

**Problem identified:** `generate_km_pseudoEst_weighted` (used by RPM/DR in production) was computing per-type fractional KM — i.e., cause-specific survival `S_k(τ)`, not `CIF_k(τ) = P(T≤τ, K=k)`. Inconsistent estimand vs CCA/IPW path (which uses true AJ).

### Files Changed

| File | Change |
|------|--------|
| `Missing Types/functions.R` | Added `generate_frac_aj_pseudoEst` (new Section 9 function) + `.frac_aj_cif` helper; deprecated `generate_km_pseudoEst_weighted`; `Last Updated: 2026-03-28` |
| `Missing Types/simulation_runner.R` | `apply_pseudo_observations`: RPM/DR now call `generate_frac_aj_pseudoEst` instead of `generate_km_pseudoEst_weighted`; `Last Updated: 2026-03-28` |

### Test Result

`SCENARIO_NAME=missing_MAR_30pct_rpm N_SIMS=2` — RPM: clean run, "Generating RPM fractional AJ pseudo-observations...", results saved.
`SCENARIO_NAME=missing_MAR_30pct_dr N_SIMS=2` — DR: clean run, "Generating DR fractional AJ pseudo-observations...", results saved.

---
**Context compaction (auto) at 22:32**
Check git log and quality_reports/plans/ for current state.

---

## Longleaf Robustness Fix (follow-up)

**Problem:** `run_chunked_simulations` in `simulation_engine.R` reconstructed `temp_dir` via `here::here(...)` but did not call `dir.create` — it assumed `configure_simulation` had already run. Direct `Rscript` invocation on Longleaf caused `saveRDS` to fail with "No such file or directory".

### Files Changed

| File | Change |
|------|--------|
| `Missing Types/simulation_engine.R` | Added `dir.create(temp_dir, recursive=TRUE, showWarnings=FALSE)` in `run_chunked_simulations` after temp_dir assignment; `Last Updated: 2026-03-28` |
| All 10 `submit_missing_types_*.sh` | Added `mkdir -p "${WORKDIR}/results_missing_types"` alongside existing logs mkdir |
