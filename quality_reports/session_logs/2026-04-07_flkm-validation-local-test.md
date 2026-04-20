# Session Log: FL-KM Validation Local Test — Diagnose & Verify

**Date:** 2026-04-07
**Goal:** Run `test_flkm_warning_validation.R` locally on one scenario after the 2026-04-06 fixes (min_group_size + NA-break) to confirm the validation pipeline passes before resubmitting to SLURM.

## Diagnosis

Pre-session concern: the min_group_size=10 guard might skip all landmark groups when N_SUBJECTS=20, producing empty `pseudo_rows`. Investigation showed this was not the case — at the first (earliest) landmark time, all 20 subjects are at risk, giving n_t = 20 ≥ 10. Later groups shrink, but the first pass produces sufficient pseudo_rows.

## Result

All four FL-KM regression tests passed locally:

| Test | Result |
|------|--------|
| `test_flkm_warning_validation.R` | PASS — all assertions including trace_extract |
| `test_flkm_min_group.R` | PASS — 4/4 assertions |
| `test_flkm_zero_denom_na.R` | PASS (NOTE: zero-denom path not triggered by N=12/15 seeds — structural contract still verified) |
| `test_flkm_validation_diagnosis.R` | PASS — all assertions including green/pending/red states |

## No Code Changes Needed

The 2026-04-06 fixes (`functions.R`) are consistent with the existing tests. No modifications were required to any file.

## Next Step

Sync `functions.R` to Longleaf, delete old first-pass RDS artifacts, and resubmit the 21-cell first-pass validation grid (`submit_flkm_warning_validation_first_pass.sh`).
