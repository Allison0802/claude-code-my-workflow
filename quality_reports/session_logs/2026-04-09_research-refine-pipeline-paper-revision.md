# Session Log: Research Refine Pipeline for Paper Revision R Code Tasks

**Date:** 2026-04-09
**Goal:** Run research-refine-pipeline on 5 R code tasks identified by auto-paper-improvement-loop for the comparisons paper revision (Biostatistics AI+RWE)
**Approach:** Triage -> method assessment -> experiment planning

## Key Decisions

- **Method is stable** -- skipped full research-refine loop. The pseudo-observation landmarking framework with RF/MERF comparison is well-established through iterative paper writing.
- **All 5 tasks require HPC re-runs** -- current simulation and CARRA outputs save only C-indices, not raw predictions, MERF diagnostics, or timing information.
- **Strategy: coordinated re-run** -- modify existing scripts to save extended outputs (predictions, sigma_b, timing) via a SAVE_EXTENDED flag, then write lightweight post-processing scripts for each metric. Minimizes HPC time by piggybacking all data collection onto one modified re-run per pipeline.
- **8 simulation scenarios** (4 extreme conditions x 2 EFP levels at rho=0.3) sufficient for Brier scores and sigma_b -- not all 37 scenarios needed.

## Files Created

- `comparisons/refine-logs/FINAL_PROPOSAL.md` -- Method thesis (stable)
- `comparisons/refine-logs/REVIEW_SUMMARY.md` -- 5 reviewer concerns mapped to tasks
- `comparisons/refine-logs/REFINEMENT_REPORT.md` -- Why full research-refine was skipped
- `comparisons/refine-logs/EXPERIMENT_PLAN.md` -- Detailed plan: 3 HPC runs + 6 post-processing scripts
- `comparisons/refine-logs/EXPERIMENT_TRACKER.md` -- Task tracker with dependencies
- `comparisons/refine-logs/PIPELINE_SUMMARY.md` -- Integration summary

## Open Questions

- Does `MERFranger()` return object expose `$Sigma` for random-effect variance? (Need to check on Longleaf)
- Are any predictions already saved in the existing .rds files? (Unlikely based on code review, but audit first)

## Implementation (same session)

- S1: Modified `comprehensive_method_comparison.R` -- 11 targeted edits: SAVE_EXTENDED flag, extract_merf_sigma_b helper, 6 sigma_b capture points, extended return list, cluster export, output directory
- S2: Modified `carra_model_evaluation_100_runs_age_based.R` -- extended data collection block with tryCatch wrappers, per-split saving, save_extended parameter passthrough
- S3: Created `timing_benchmark.R` (553 lines) -- 4 scenarios x 5 reps, system.time() per method
- Created 3 SLURM submission scripts: `submit_extended_comparison_array.sh`, `submit_carra_extended.sh`, `submit_timing_benchmark.sh`
- Created 6 post-processing scripts: `compute_brier_scores.R`, `compute_calibration_plot.R`, `compute_out_of_range.R`, `compute_fairness_metrics.R`, `summarize_timing.R`, `analyze_merf_diagnostics.R`
- Updated experiment tracker with all completed items

## Files Created/Modified

### Modified
- `comparisons/Simulations/comprehensive_method_comparison.R`
- `comparisons/Uveitis_Project/age_based_analysis/carra_model_evaluation_100_runs_age_based.R`

### Created
- `comparisons/Simulations/timing_benchmark.R`
- `comparisons/Simulations/submit_extended_comparison_array.sh`
- `comparisons/Simulations/submit_timing_benchmark.sh`
- `comparisons/Uveitis_Project/age_based_analysis/submit_carra_extended.sh`
- `comparisons/Simulations/compute_brier_scores.R`
- `comparisons/Simulations/compute_out_of_range.R`
- `comparisons/Simulations/summarize_timing.R`
- `comparisons/Simulations/analyze_merf_diagnostics.R`
- `comparisons/Uveitis_Project/age_based_analysis/compute_calibration_plot.R`
- `comparisons/Uveitis_Project/age_based_analysis/compute_fairness_metrics.R`
- `comparisons/refine-logs/` (6 pipeline documents)

## Next Steps

1. Pre-experiment audit on Longleaf (verify data structure, check MERFranger `$Sigma`)
2. Submit SLURM jobs (J1, J2, J3) on Longleaf
3. After HPC completion: run post-processing scripts (P1-P6)
4. Paper integration (T1-T7)
