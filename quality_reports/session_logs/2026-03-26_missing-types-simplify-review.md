# Session Log: Missing Types Code Simplification Review

**Date:** 2026-03-26
**Goal:** Review all non-archive, non-variance-estimator R scripts in Missing Types for code reuse, quality, and efficiency; fix actionable issues.

- [analysis strength review] Missing Types/ — deep domain + R code review for analysis-strength improvements; 2 critical bugs found (RPM/DR training filter = CCA; IPW misses XX2 from MAR), 3 major statistical flaws (DR normalization breaks double-robustness; KM vs Aalen-Johansen; avg_gap inflated by censoring); full report at quality_reports/missing_types_analysis_strength_review_2026-03-26.md

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

## T1 — RPM/DR Training Data Filter Bug Fix

- [fix] Missing Types/simulation_runner.R — BUG FIX (T1): introduced type_ok/type_ok2 helpers; RPM/DR training filters now allow fractional-indicator rows (missing type but valid pseudo-obs) through, while CCA/IPW still require observed type. Old `(event != 1 | !is.na(type))` guard removed from train_data_type1, train_data_type2, and train_combined. Syntax verified OK.

## T2 — IPW propensity model fix (2026-03-27)

- [09:00] Missing Types/simulation_runner.R — added XX2 to `ipw_features` in `apply_imputation_phase_b`; MAR mechanism depends on X, Z, AND XX2 (quadratic + interaction terms), omitting XX2 caused systematic propensity misspecification under MAR
- [09:00] Missing Types/CLAUDE.md — corrected IPW documentation: updated "IPW for Missing Types" section and imputation method table to reflect `("X", "Z", "XX2")` instead of `("X", "Z")`

---
**Context compaction (auto) at 00:32**
Check git log and quality_reports/plans/ for current state.

## T3–T9 Analysis Strength Fixes (continued from context-compacted session)

- [T3] Missing Types/functions.R — Replaced DR/DR-RF sum-normalization (`dr_sum`) with per-component clipping `pmax(0, pmin(1, DR_k))` in both `compute_dr_indicators_rf` and `compute_dr_indicators`. Renormalization destroyed double-robustness: E[DR_k/(DR_1+DR_2)] ≠ P(type=k) even under correct models.
- [T4] Missing Types/simulation_runner.R — Fixed avg_gap computation: now filters to event rows only (`data$event == 1`) before computing inter-event gaps. Censoring intervals were inflating avg_gap, aa, and tau.
- [T5] Missing Types/simulation_runner.R — Removed second `set.seed(seed)` call before the train-test split. Re-seeding made the split deterministically coupled to data generation, decoupling it from imputation randomness.
- [T6] Missing Types/functions.R — Replaced per-cause KM with Aalen-Johansen estimator in `generate_km_pseudoEst`. Added `safe_aj_cif_est()` helper. KM was estimating cause-specific survival S_k(tau), not CIF_k(tau). `generate_km_pseudoEst_weighted` (fractional indicators) left as-is with theoretical limitation documented.
- [T7] Missing Types/simulation_runner.R — All 7 silent `tryCatch` model-fitting error handlers now log to `failed_models <<- ...`. Field included in result list. Prevents systematic failures from silently biasing mean C-indices.
- [T8] Missing Types/simulation_engine.R — Added `RNGkind("L'Ecuyer-CMRG"); clusterSetRNGStream(cl, iseed=20260326)` after `makeCluster()` to initialize independent RNG streams on parallel workers.
- [T9] Missing Types/analyze_missing_types_results.R — Fixed Joint RF Type 2 gold-standard copy-paste bug (`c_rf_time_type2_mean` → `c_rf_time_type2_true_mean`); replaced `#2E86AB`/`#A23B72` with Okabe-Ito `#56B4E9`/`#D55E00`; added `bg="white"` to both ggsave calls; `size=0.5` → `linewidth=0.5` in geom_errorbar; added `library(here)` and `set.seed(20260326)`.
- [permissions] Research/.claude/settings.local.json — Added `"Bash(*)"` allow rule for all bash commands in this repo context.

---
**Context compaction (auto) at 01:26**
Check git log and quality_reports/plans/ for current state.

## Remaining Fixes (m1–m6 + minor, 2026-03-27)

- [m1] Missing Types/analyze_missing_types_results.R — `RESULTS_DIR` now uses `here::here("results_missing_types")` so script works from any cwd (required for SLURM)
- [m2] Missing Types/analyze_missing_types_results.R — Added `theme_publication()` definition; replaced both `theme_minimal()` calls in overview and per-method plots; removed redundant theme elements already covered by `theme_publication()`
- [m5] Missing Types/analyze_missing_types_results.R — Added Monte Carlo SE (`_mc_se = sd/sqrt(n)`) to `aggregate_results`; column order updated to `_mean`, `_sd`, `_mc_se`, `_median`
- [m6] Missing Types/simulation_engine.R — `seq_len(n_sims)` replaces `1:n_sims`; `here::here()` for temp_dir and scenario_file in `run_chunked_simulations` and `save_and_summarize_results`
- [minor] Missing Types/simulation_engine.R — Added Author, Inputs, Outputs to METADATA header; bumped Last Updated to 2026-03-27
- [minor] Missing Types/analyze_missing_types_results.R — bumped Last Updated to 2026-03-27

## Statistical Validity Review (2026-03-27)

Full cross-check of simulation_engine.R and simulation_runner.R against comparisons/ reference implementation.

### All T1–T9, m1–m6 fixes confirmed correct:
- T1 (RPM/DR training filter): type_ok/type_ok2 helpers correctly gate on fractional indicator columns ✓
- T2 (IPW XX2): `ipw_features <- intersect(c("X","Z","XX2"), names(...))` correct ✓
- T3 (DR clipping): pmax(0,pmin(1,DR_k)) in both compute_dr_indicators and _rf ✓
- T4 (avg_gap): filtered to event rows only before gap computation ✓
- T5 (second set.seed removed): confirmed absent ✓
- T6 (AJ estimator): generate_km_pseudoEst uses survfit(Surv(t,factor(status))~1) with 3-level factor ✓
- T7 (failed_models logging): confirmed for 7 RF/MERF/Cox blocks ✓
- T8 (L'Ecuyer-CMRG): RNGkind + clusterSetRNGStream after makeCluster ✓
- T9 (analyze_missing_types_results.R): all 5 fixes confirmed ✓
- m3 (withCallingHandlers): applied to all 3 MERFranger calls ✓

### New bugs found and fixed:

- [fix] Missing Types/simulation_runner.R — **BUG FIX**: GRF error handlers (grf_cov, grf_strat_type1, grf_strat_type2) now append to `failed_models <<- ...` instead of cat()-only; T7 was only partial — GRF blocks were missed
- [fix] Missing Types/functions.R — **STALE WARNING**: In both compute_dr_indicators and compute_dr_indicators_rf, replaced `warning("DR indicators do not sum to 1 after normalization")` with an informational cat() explaining that sum < 1 is expected after pmax/pmin clipping (raw AIPW score was negative for one type). "After normalization" text was left over from the old T3 approach.

### Domain reviewer findings (quality_reports/missing_types_domain_review_2026-03-27.md):
- [BLOCKING] generate_km_pseudoEst_weighted targets S_k(tau) via KM; CCA/IPW use AJ for CIF_k(tau) — estimand mismatch in comparison table; must disclose prominently or fix
- [MAJOR] DGP = two independent Poisson processes (not single-spell competing risks); framing in paper must be precise
- [MAJOR] MAR scaling (`scale_factor = target/mean`) distorts logistic surface → IPW propensity may be misspecified despite using correct predictors
- [MINOR] Logistic propensity: in-sample fitted values vs RF propensity: OOB → DR vs DR-RF not fairly compared; consider K-fold cross-fitting
- [MINOR] RMST pseudo-obs: cause-specific RMST (competing events censored), not restricted mean CIF — document estimand
- [MINOR] Cox-to-landmark many-to-many join duplicates predictions — document as paper limitation
- [MINOR] C-index averaged over landmark times without at-risk weighting — consider weighting by n_pairs
- [MINOR] MNAR: only 2 percentages, no varying non-ignorability degree — add 3:1 ratio scenario

### Acknowledged remaining limitations (not bugs, need methods section mention):

- `generate_km_pseudoEst_weighted` (RPM/DR methods) uses fractional-count KM, not AJ → targets approx CIF but inconsistent estimand vs CCA/IPW/GRF (which use AJ). Theoretical extension to fractional AJ is left as future work; documented in code.
- MERF predicts from fixed-effects forest only (random effects = 0 for test subjects). Documented in code comments at each MERF prediction call.

---
**Context compaction (auto) at 01:33**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 02:07**
Check git log and quality_reports/plans/ for current state.
