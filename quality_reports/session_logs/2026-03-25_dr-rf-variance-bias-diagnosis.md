# Session Log: 2026-03-25 — DR-RF Variance Estimator Bias Diagnosis

## Goal
Investigate why the variance estimator coverage is always below 95% in the
nsim=200 results for all 8 scenarios (MCAR/MAR × 10/20/30/50%).

## Key Findings

- [11:30] Missing Types/variance estimator/results/ — Reviewed all nsim=200 CSV summaries. Coverage ranges 47–74%; prior nsim=100 results showed same pattern.
- [11:45] Missing Types/variance estimator/dr_rf_variance_coverage_study.R — Confirmed IJ variance estimator is correct and calibrated (ratio ≈ 0.91). Problem is NOT variance.
- [12:00] Missing Types/variance estimator/results/*.csv — Quantified bias: mean_pred − mean_truth = +0.049 (MCAR 10%) growing to +0.111 (MAR 50%) for type 1. Bias grows with missingness → fingerprint of AIPW IPW term.
- [12:15] Missing Types/functions.R lines 536–550, 660–663 — Found root cause: `generate_landmark_weighted_pseudo()` uses `time_to_event_type_k` (time to next OBSERVED type-k event) as KM time axis, but `event_type_k_dr_cf` is the DR indicator for the next event of ANY type. These misalign for ~43% of intervals (those where the next any-type event is of the other type). Negative DR weights applied at wrong times → KM overestimates survival.
- [12:30] Missing Types/variance estimator/dr_rf_variance_coverage_study.R `add_phi_terms()` — Secondary bug: `response_aipw = pseudoEst_km_DR + phi_aipw` double-counts the AIPW correction (once via fractional KM event indicators, once via phi_aipw).

## Fix Specified
- RC1 (required): change `time_col <- paste0("time_to_event_type", type_k)` to `time_col <- "time_to_event"` in `generate_landmark_weighted_pseudo()`
- RC2 (conditional): set `response_aipw = pseudoEst_km_DR` (remove phi_aipw from response) if RC1 alone gives residual bias or over-coverage

## Outputs
- Updated all 6 refine-logs files in `Missing Types/variance estimator/refine-logs/`
- All prior coverage results (Exp 2 v1 and v2) superseded; fix must be applied before re-running
