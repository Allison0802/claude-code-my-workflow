# Session Log: FL-KM Trace-Extract RNG Fix

**Date:** 2026-04-05
**Goal:** Diagnose why validation pipeline remained at `awaiting_trace_extract` after all 46 trace-extract cluster jobs finished.

---

## Root Cause Analysis

### Bug 1: RNG Kind Mismatch (critical)

**File:** `simulation_engine.R`

**Problem:** First-pass runs used PSOCK cluster workers. `clusterSetRNGStream(cl, iseed=20260326)` activates `L'Ecuyer-CMRG` on each worker before `set.seed(seed)` is called. Sequential trace-extract runs (CHUNK_SIZE=1, no cluster) used the default Mersenne-Twister RNG. `set.seed(3)` produces completely different data under L'Ecuyer-CMRG vs Mersenne-Twister → different landmark times → different row_ids → zero row_id matches between first-pass audit requests and trace event_trace.

**Fix:** Added `RNGkind("L'Ecuyer-CMRG")` to the sequential execution path before the `lapply`, matching the parallel path.

**Evidence:** First-pass flagged row_id `"24__3.79005198192537__2"` absent from trace event_trace; trace had row_ids like `"24__0.0366..."`  (different time scale from different data).

### Bug 2: `trace_present` logic for `invalid_anchor` type (analysis)

**File:** `flkm_warning_validation_analysis.R`

**Problem:** `trace_present` for `invalid_anchor` type audit rows checked if `invalid_anchor_id` appears in `event_trace`, but `invalid_anchor_id` is never set in `event_trace` (it's always NA — `.flkm_attach_trace_to_row` only sets `row_id`). So all 105 `invalid_anchor` audit rows had `trace_present = FALSE`.

**Fix:** For `invalid_anchor` type, `trace_present` now checks `invalid_state_table` (which does store `invalid_anchor_id` from `.flkm_append_invalid_state`).

---

## Changes

- `simulation_engine.R` — `RNGkind("L'Ecuyer-CMRG")` in sequential path; `Last Updated: 2026-04-05`
- `flkm_warning_validation_analysis.R` — `trace_present` fix for invalid_anchor; `Last Updated: 2026-04-05`

---

## Verification

Local test (N=30, 3 seeds, CCA only):
- First-pass: 3 seeds, 12 flagged rows, 407 invalid states ✓
- Trace-extract: `trace_complete: TRUE`, all 10 `trace_present: TRUE` after generating 2 trace files ✓

---

## Next Steps

1. Push `simulation_engine.R` and `flkm_warning_validation_analysis.R` to cluster
2. Delete old trace-extract RDS files (wrong data from RNG mismatch)
3. Re-submit all 46 trace-extract jobs
4. Download results and run diagnosis

---
**Context compaction (manual) at 01:01**
Check git log and quality_reports/plans/ for current state.
