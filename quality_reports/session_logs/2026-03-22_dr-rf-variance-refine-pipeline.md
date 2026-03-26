# Session Log: DR-RF Variance Estimator Refinement Pipeline

**Date**: 2026-03-22
**Goal**: Run /research-refine-pipeline on the variance estimator derivation and implementation roadmap

- [later] Missing Types/variance estimator/calibrate_ij_variance.R, diagnose_ciz.R, diagnose_bootstrap_variance.R — replaced `setwd(here::here("variance estimator"))` with `commandArgs`-based script directory detection; `here::here()` fails to find project root in SLURM `--wrap` invocations

## Actions

- [01:00] Missing Types/variance estimator/ — Ran full research-refine-pipeline: triaged derivation + implementation + diagnostic scripts + results
- [01:05] Missing Types/variance estimator/refine-logs/ — Created 6 pipeline deliverables: FINAL_PROPOSAL.md, REVIEW_SUMMARY.md, REFINEMENT_REPORT.md, EXPERIMENT_PLAN.md, EXPERIMENT_TRACKER.md, PIPELINE_SUMMARY.md
- [01:10] Dispatched domain-reviewer and r-reviewer agents for parallel multi-lens review
- [01:30] Integrated agent findings into REVIEW_SUMMARY (14 domain issues, 22 code issues)

## Key Findings

1. **V_prop = 0 in production code** — propagated influence term set to zero in `fit_grf_and_predict()`
2. **Theory-code misalignment** — derivation describes custom IJ; code uses grf honest forest
3. **Custom IJ 33x over-estimation root cause** — non-honest splitting (100-400x), binary inbag (distorts covariance), cluster correction (7.4x amplifier)
4. **Theorem 1 needs proof or downgrade** — stated formally but no proof sketch, missing conditions (boundedness of POs, subsample-size range, additive decomposition independence)
5. **Additive decomposition may double-count** — PO jackknife partially captures DR noise; needs first-order linearization remark + Kennedy (2022) chain rule reference
6. **Reproducibility bugs** — nested set.seed in crossfit_dr_rf_nuisances, calibration samples with replace=TRUE then %in% deduplicates, no mclapply error handling, missing L'Ecuyer-CMRG parallel RNG
7. **DGP too simple** — variance study uses linear Cox DGP (2 covariates) vs main paper's nonlinear DGP (4 covariates, g1/g2 functions). Should stress-test with nonlinear DGP.
8. **tau inconsistency** — derivation/implementation use tau=5a; main paper says tau=10a
9. **Notation conflicts** — c_{ib} has spurious b subscript; Z_i(t) vs F_i(t) feature vector naming; CCA/IPW row in Table 1 misrepresents IPW

## Agent Reviews

- **Domain reviewer** (14 issues, 4 blocking): Full report at quality_reports/dr_rf_variance_derivation_domain_review.md
- **R code reviewer** (22 issues, 4 critical): Full report at quality_reports/dr_rf_variance_coverage_study_r_review.md

## Verdict

**REVISE** — method thesis is sound, implementation has addressable gaps. Next steps:
1. Implement V_prop via `get_forest_weights()` (Task A)
2. Fix reproducibility bugs (Tasks D, E)
3. Run calibration at n=500 (Exp 1)
4. Update derivation to match grf and address reviewer concerns (Task F)
5. Stress-test with nonlinear DGP (Exp 5)

---

## Experiment Bridge — Implementation (2026-03-22)

**Goal**: Implement Tasks A–E from EXPERIMENT_PLAN.md; prepare Exp 1 for local run and Exp 2 for SLURM submission.

### Changes Made

- [experiment-bridge] Missing Types/variance estimator/dr_rf_variance_coverage_study.R — Added `compute_propagated_variance()` using `grf::get_forest_weights()`; updated `fit_grf_and_predict()` to return actual V_prop + V_total (was V_prop=0); removed nested `set.seed()` from `crossfit_dr_rf_nuisances()`; guarded `m_bar` against NaN in `add_phi_terms()`; added `RNGkind("L'Ecuyer-CMRG")` before `mclapply`; added `tryCatch`+`Filter` for mclapply error handling; added `options(dr_rf.functions_only)` sourcing guard before execution block
- [experiment-bridge] Missing Types/variance estimator/legacy_custom_ij.R — New: archived `fit_subject_bootstrap_rf_trace()`, `predict_forest_trace()`, `estimate_variance_components()` (no longer in main script; needed only by diagnose_*.R)
- [experiment-bridge] Missing Types/variance estimator/calibrate_ij_variance.R — Complete rewrite: fixed fragile `eval(parse())` sourcing; switched to `fit_grf_and_predict()` (was using old custom bootstrap RF); generates fresh DGP training data per draw (N_TRAIN=500, N_DRAWS=20) rather than resampling from fixed dataset; updated parameters to production scale (B=100, 5-fold CF)
- [experiment-bridge] Missing Types/variance estimator/diagnose_ciz.R — Fixed fragile sourcing; now uses `options(dr_rf.functions_only=TRUE)` + `source()` guard + `source("legacy_custom_ij.R")`
- [experiment-bridge] Missing Types/variance estimator/diagnose_bootstrap_variance.R — Same sourcing fix as diagnose_ciz.R
- [experiment-bridge] Missing Types/variance estimator/submit_dr_rf_variance_coverage.sh — Updated N_SIMS=100→200 for Exp 2 (narrower coverage CI per EXPERIMENT_TRACKER decision)
- [experiment-bridge] Missing Types/variance estimator/refine-logs/EXPERIMENT_TRACKER.md — Updated task statuses A–E to DONE; Exp 1+2 marked READY TO RUN

### Next Steps

1. **Run Exp 1 locally**: `cd "Missing Types/variance estimator" && Rscript calibrate_ij_variance.R`
2. **Check gate**: median(V_total/empirical_var) in [0.7, 1.5]? → proceed to Exp 2
3. **Submit Exp 2**: `sbatch submit_dr_rf_variance_coverage.sh` (8 SLURM array jobs, ~6 hr wall-clock)
4. **Remaining Tasks F+G**: Update `variance_derivation.tex` and `implementation_roadmap.md` (manuscript tasks, separate from experiment bridge)

---
**Context compaction (auto) at 00:32**
Check git log and quality_reports/plans/ for current state.
