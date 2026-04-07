# Session Log: FL-KM Out-of-Range Survival NA Fix

**Date:** 2026-04-07
**Goal:** Eliminate remaining `core FL-KM bug` classification after fix 2 (zero-denominator NA).

## Root Cause

Validation pipeline (trace-extract complete) produced 105 `invalid-but-unflagged internal failure` rows:
- 30 rows: extreme finite pseudo (-0.70 to 5.64), n_t = 11–16, IPW/DR methods.
  Root cause: `.flkm_survival_one_group_details()` recorded `survival_out_of_unit_interval`
  when `d_total > y_total` (extreme IPW upweighting) but continued, propagating the negative
  survival value to `pseudo_val`. The fast path `.flkm_survival_one_group()` had no guard at all.
- 75 rows: NA pseudo (correctly handled by earlier fixes), mis-classified as bugs because
  the pipeline had no "correctly handled invalidity" class.
- 3 fixes also: positional arg misalignment in row-level `.flkm_append_invalid_state()` calls.

Also fixed: memory-efficient lazy loading in `summarize_flkm_trace_audit()` (grouping audit
requests by trace file, releasing after each group) — prevents OOM crash when loading 56 large
trace-extract RDS files sequentially. The `trace_present` fix for `invalid_anchor` rows was
also bundled: now checks `nrow(invalid_subset) > 0` instead of `nrow(trace_subset) > 0`, since
`invalid_anchor_id` is never propagated to `event_trace`.

## Fixes

### functions.R
- Added `surv_val <- NA_real_; break` after `survival_out_of_unit_interval` recording
  in `.flkm_survival_one_group_details()` (detailed path)
- Added identical `!is.finite(surv_val) || surv_val < 0 || surv_val > 1` guard in
  `.flkm_survival_one_group()` fast path (validation_mode="none", used in main simulation)
- Fixed positional arg bug in three row-level `.flkm_append_invalid_state()` calls:
  `failure_type` was landing in `event_subject_id`, leaving `failure_type = NA` in table

### flkm_warning_validation_analysis.R
- Added "correctly handled invalidity" audit class for `invalid_anchor` requests where
  `pseudo = NA` (invalid state detected and NA propagated correctly)
- Updated `recommend_flkm_validation_action()`: removed `has_invalid_internal_state` check
  from first_pass_summary (too coarse); rely solely on audited_rows classification
- Fixed lazy loading in `summarize_flkm_trace_audit()` to prevent OOM
- Fixed `trace_present` for `invalid_anchor` rows (check `invalid_subset` not `trace_subset`)

## Changes

- `Missing Types/functions.R` — four fixes; `Last Updated: 2026-04-07`
- `Missing Types/flkm_warning_validation_analysis.R` — classification + recommendation + memory; `Last Updated: 2026-04-07`
- `Missing Types/test_flkm_surv_out_of_range.R` — new focused test (4 assertions, all PASS)
- `Missing Types/CLAUDE.md` — documented guard in Critical Details

## Verification

Longleaf: delete old first-pass + trace-extract files, rerun first-pass (21 jobs, ~1.5h each),
then trace-extract. Final diagnosis expected: `Stage: complete, Cause: benign jackknife
overshoot` or `general small-group jackknife sensitivity`.

## Open Question

After this fix, more NA pseudo-obs will appear in `validation_mode = "none"` (main simulation).
Check whether `randomForest`/`ranger` error on NA outcomes in `simulation_runner.R`.
