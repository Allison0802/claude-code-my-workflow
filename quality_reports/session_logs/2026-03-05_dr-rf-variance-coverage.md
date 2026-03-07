# Session Log

## Goal
Implement a standalone DR-RF variance-estimator simulation study with Cox-generated recurrent-event data and pointwise 95% coverage summaries at each landmark timepoint.

## Approach
- Added `Missing Types/variance estimator/dr_rf_variance_coverage_study.R`.
- Kept the implementation standalone by loading only the specific helper functions needed from `Missing Types/functions.R`.
- Implemented subject-level cross-fitting for RF propensity and RF outcome nuisances.
- Built landmark-specific DR-weighted pseudo-observations, influence terms, subject-bootstrap RF traces, and IJ-plus-propagated variance estimates.
- Computed subject-specific Cox-truth survival targets using the retained frailty and the known data-generating rate formulas.

## Verification
- Parsed the new script successfully with `Rscript -e "parse(file=...)"`.
- Ran a smoke test with `TEST_RUN=true N_SIMS=1 N_SUBJECTS=60 N_TREES=10 N_FOLDS=3`.
- Verified output files were written under `Missing Types/variance estimator/results/`.

## Notes
- Local R initially lacked `randomForest` and `ranger`; both were installed to complete verification.
- Current IDE lints are mostly non-blocking NSE/dynamic-loading warnings rather than runtime failures.
