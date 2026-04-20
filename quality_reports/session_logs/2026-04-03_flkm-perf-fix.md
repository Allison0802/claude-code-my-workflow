# Session Log: 2026-04-03 — FL-KM Validation Performance Fix

## Goal
Fix O(n²) performance bottleneck in FL-KM pseudo-observation generation that caused
validation jobs (N=500, 20 seeds/cell) to run 8+ hours per chunk.

## Changes

- [Missing Types/functions.R] `generate_flkm_pseudoEst()` — replaced three inner-loop
  `bind_rows(growing_df, tibble(...))` accumulations (O(n²) in pseudo-row count) with
  list accumulators (`pseudo_row_list`, `invalid_state_list`, `event_trace_list`) and
  a single `bind_rows()` call after the outer loop. Verified locally: N=20, 1 seed →
  2914 pseudo rows, 37.3s (was 8+ hrs projected for N=500).

## Status
- Fix committed locally; cluster jobs (submitted with old code) must be cancelled and
  resubmitted after syncing `functions.R` to `/work/users/y/u/yumeiy/missing types/`.
