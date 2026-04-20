# Session Log: FL-KM Zero-Denominator NA Fix

**Date:** 2026-04-06
**Goal:** Fix residual core FL-KM bug after min_group_size fix.

## Root Cause

After raising min_group_size to 10, validation pipeline still returned
`core FL-KM bug` with 95 `invalid-but-unflagged internal failure` rows in
groups n_t = 11, 12, 15, 16. Pseudo-obs ranged from -0.70 to 5.64. All 7
methods equally affected; audit_reason was `invalid_internal_state` (silent,
no first-pass warning).

Root cause: when the type-k risk set depletes to zero mid-loop in
`.flkm_survival_one_group_details()`, `y_total <= 0` triggered `next`
(freeze), not NA. The jackknife formula amplified the asymmetry between
full-group freeze point and LOO freeze point into extreme pseudo-obs.

## Fix

In both `.flkm_survival_one_group_details()` and `.flkm_survival_one_group()`:
- Changed `next` → `surv_val <- NA_real_; break` for both
  `nonpositive_denominator` and `nonfinite_denominator` handlers.
- NA propagates through `pseudo_val <- n_t * surv_f - (n_t-1) * surv_m`
  naturally. Undefined KM → undefined pseudo-obs.

## Changes

- `Missing Types/functions.R` — NA+break in both KM inner functions; `Last Updated: 2026-04-06`
- `Missing Types/test_flkm_zero_denom_na.R` — new focused test (3 assertions, all pass)

## Next Step

Sync functions.R to Longleaf, delete old first-pass RDS, resubmit first-pass validation.

---
**Context compaction (manual) at 23:56**
Check git log and quality_reports/plans/ for current state.
