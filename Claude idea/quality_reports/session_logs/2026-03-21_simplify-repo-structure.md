# Session Log: Simplify Repo Structure and Scripts
Date: 2026-03-21

## Summary
Ran `/simplify` across the repo. Three parallel review agents identified dead code,
superseded scripts, and missing pipeline documentation. Applied safe fixes only;
larger refactors (shared functions.R extraction, combine_method_results.R expansion)
flagged for future work.

## Changes Made

### comparisons/Simulations/ — test scripts archived
- [09:00] comparisons/Simulations/ — moved 7 test_*.R debug scripts to comparisons/archive/:
  test_censoring_slurm.R, test_data_consistency.R, test_f5_c1_rho0.9_60pct_local.R,
  test_highdim_comprehensive.R, test_highdim_local.R, test_highdim_local_rmst.R,
  test_paper_history_simple.R
  (reason: one-off debug/empirical-check artifacts; archive/ already existed)

### comparisons/Simulations/ — v1/v2 pipeline headers added
- [09:05] functions.R — added PIPELINE: v1 status header with cross-reference to functions_v2.R
- [09:05] functions_v2.R — added PIPELINE: v2 header noting it extends functions.R with rate_cox_data_gen_interaction()
- [09:05] method_runners.R — added PIPELINE: v1 header referencing submit_by_method.sh
- [09:05] method_runners_v2.R — added PIPELINE: v2 header referencing submit_by_method_v2.sh
- [09:05] run_single_method.R — added PIPELINE: v1 header (called by submit_by_method.sh, --array=1-20)
- [09:05] run_single_method_v2.R — added PIPELINE: v2 header

### Missing Types/ — superseded GRF scripts archived
- [09:02] Missing Types/ — moved 3 scripts to Missing Types/archive/:
  missing_types_method_comparison_grf_stratified.R (superseded by _grf_stratified_all_methods.R),
  missing_types_method_comparison_grf_type_cov.R (superseded by _grf_type_cov_all_methods.R),
  missing_types_method_comparison_ipw_rf_test_hyperparams.R (tuning artifact)

## Deferred / Needs Decision

- **combine_method_results.R**: intentionally covers only 2 scenarios (the ones submitted
  separately via submit_by_method.sh for the most complex parameter combinations). Not a bug.
- **functions.R duplication**: core functions are duplicated verbatim across
  comparisons/Simulations/functions.R, functions_v2.R, and Missing Types/functions.R.
  scripts/R/ is the intended consolidation point but is still empty. Extracting the
  shared core is a larger refactor — deferred.
- **Missing Types/ method count**: CLAUDE.md documents 5 imputation methods but 7+ families
  now exist. Architecture section should be updated.
- **3-way skills table duplication**: ~~deferred~~ resolved (see below).

## Additional Changes (same session)

- [09:20] Missing Types/CLAUDE.md — updated method count from 5 to 9 active methods;
  updated File Organization diagram; updated Imputation Method Differences table to
  include rpm_rf, dr_rf, grf_stratified_all_methods, grf_type_cov_all_methods
- [09:20] Missing Types/CLAUDE.md + comparisons/CLAUDE.md — collapsed Writing/Research
  skills sections; replaced duplicated generic command tables with a pointer to parent
  CLAUDE.md; retained only sub-project-specific context rows
