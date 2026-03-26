# Session Log: Missing Types Code Simplification Review

**Date:** 2026-03-26
**Goal:** Review all non-archive, non-variance-estimator R scripts in Missing Types for code reuse, quality, and efficiency; fix actionable issues.

## Changes Made

- [14:00] Missing Types/missing_types_method_comparison_cca.R — **BUG FIX**: Changed `tau <- 10 * aa` to `tau <- 5 * aa` to match all other method scripts (was making CCA C-index results non-comparable)
- [14:00] Missing Types/diagnose_rf_underperformance.R — Changed `tau <- 10 * aa` to `tau <- 5 * aa` for consistency
- [14:00] Missing Types/test_rpm_small.R — Changed `tau <- 10 * aa` to `tau <- 5 * aa` for consistency
- [14:01] Missing Types/functions.R — Changed default `nodesize = 40` to `nodesize = 5` in `fit_subject_weighted_rf()` (40 was never used; all callers pass 5)
- [14:01] Missing Types/functions.R — Removed hardcoded `seed = 123` from `fit_rate_proportion_model_rf()` and `fit_propensity_model_rf()` ranger calls (was overriding ambient RNG state)
- [14:02] All 9 method comparison scripts — Removed dead `run_comprehensive_simulation_optimized()` function (~225 lines total; defined but never called)
- [14:02] All 9 method comparison scripts — Simplified `aggressive_gc()`: removed triple `gc()` loop and `Sys.sleep(0.5)` (saves ~250s idle time per 500-sim scenario)
- [14:03] All 9 method comparison scripts — Removed commented-out debugging assignments (`# scenario_name <- ...`, `# is_test_run <- TRUE`, `# scenario_params <- scenario`, `# seed <- 123`)

## Deferred Issues (require larger refactoring)

- ~12,000 lines of structural duplication across 9 method scripts (should extract shared simulation engine)
- O(n^2) pseudo-observation computation via leave-one-out `survfit()` (consider `pseudo` package)
- O(n^2) C-index via nested for loops (consider `survival::concordance()`)
- dplyr `filter()`/`arrange()` inside tight loops in `transform_with_covariates_complex()` and DR/RPM indicator propagation
- PSOCK cluster recreated per chunk instead of once
- Near-identical function pairs in functions.R (_rf variants) could be unified with `predict_fn` parameter

---
**Context compaction (auto) at 13:39**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 14:01**
Check git log and quality_reports/plans/ for current state.

---

## Structural Deduplication (Task 6-7)

- [later] Missing Types/simulation_engine.R — **CREATED**: shared Longleaf lib setup, package loading (12 pkgs incl. grf), monitor_memory, aggressive_gc, configure_simulation, run_chunked_simulations, save_and_summarize_results (~387 lines)
- [later] Missing Types/simulation_runner.R — **CREATED**: shared run_comprehensive_simulation with all 7 imputation methods, apply_imputation_phase_a/b, apply_pseudo_observations, compute_event_history_features (~600 lines)
- [later] 7 thin-wrapper scripts (cca, ipw, ipw_rf, rpm, rpm_rf, dr, dr_rf) — **REWRITTEN** to ~20 lines each; -12,374 lines total
- [later] Missing Types/missing_types_method_comparison_grf_type_cov_all_methods.R — replaced old lib/package/memory/run_chunked_simulations boilerplate with source("simulation_engine.R"); kept GRF-specific scenario naming (_grf_type_cov suffix) and run_comprehensive_simulation; -379 lines
- [later] Missing Types/missing_types_method_comparison_grf_stratified_all_methods.R — same as above (_grf_stratified suffix); -377 lines
- All 9 scripts verified: TEST_RUN=true N_SIMS=2 — 2/2 successful simulations on each
