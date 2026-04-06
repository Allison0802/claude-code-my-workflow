# Session Log: FL-KM Minimum Group Size Fix

**Date:** 2026-04-06
**Goal:** Fix core FL-KM bug identified by validation pipeline.

## Root Cause

Validation pipeline returned `cause: core FL-KM bug` because 105 `invalid_anchor`
audit rows all had `trace_invalidity = TRUE` (failure_type: `nonpositive_denominator`).
The KM denominator hit zero in very small landmark groups (n_t = 3, 4, 5, 8) during
the jackknife leave-one-out, causing a KM freeze and extreme pseudo-observation values.
No `min_group_size` guard existed — only `if (n_tp < 2) next`.

## Fix

`generate_flkm_pseudoEst()` in `functions.R`:
- Added `min_group_size = as.integer(Sys.getenv("FLKM_MIN_GROUP_SIZE", "10"))` parameter
- Replaced `if (n_tp < 2) next` with `if (n_tp < min_group_size) next`
- Added validation: stop if `min_group_size < 2`

## Changes

- `Missing Types/functions.R` — min_group_size guard; `Last Updated: 2026-04-06`
- `Missing Types/test_flkm_min_group.R` — new focused test (4 assertions, all pass)
- `Missing Types/CLAUDE.md` — documented guard in Critical Details

## Verification

`Rscript test_flkm_min_group.R` — all tests passed locally.
