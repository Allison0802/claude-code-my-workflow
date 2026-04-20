# Session Log: Extended Output Implementation for Paper Revision

**Date:** 2026-04-10
**Goal:** Implement SAVE_EXTENDED modifications across all simulation and CARRA scripts, expand to all 37 scenarios, support by-method pipeline for f5 high-frailty scenarios
**Continuation of:** 2026-04-09 research-refine-pipeline session

---

## Pre-Experiment Audit (Longleaf)

Ran two audits on Longleaf to inform implementation:

### Audit 0.1: Existing results structure
- Confirmed existing `.rds` files contain **only C-indices** (no `extended` field, no predictions)
- Fields: `success, scenario, aa, tau, n_time_points, c_rf_strat_type1, ...` (C-indices only)
- **Re-runs required** for all 5 paper revision tasks

### Audit 0.2: MERFranger object structure
- `$Sigma` = NULL, `$sigma` = NULL, `$random_effects` = NULL (all tried by initial helper -- wrong)
- **Correct fields discovered:**
  - `$RanEffSD` -- random-effect SD (sigma_b) -- **this is what we need**
  - `$IterationsUsed` -- EM iteration count
  - `$RandomEffects` -- BLUP estimates (list)
  - `$LogLik` -- log-likelihood trajectory per iteration
  - `$ErrorSD` -- residual error SD
- `sf` package had corrupted shared library (`libgdal.so.37: file too short`), fixed via `reinstall_sf_interactive.sh`

---

## Bug Fixes from Audit

Fixed `extract_merf_sigma_b()` in 3 files -- was checking `$Sigma`/`$sigma`/`$random_effects` (all NULL), now checks `$RanEffSD` with `$RandomEffects` fallback:

| File | Fix |
|------|-----|
| `Simulations/comprehensive_method_comparison.R` | `$RanEffSD` instead of `$Sigma`/`$sigma`/`$random_effects`/`$lme` |
| `Uveitis_Project/age_based_analysis/carra_model_evaluation_100_runs_age_based.R` | Same |
| `Simulations/timing_benchmark.R` | `$IterationsUsed` instead of `length($OOBerror)` |

---

## Scope Expansion: All 37 Scenarios + 3 CARRA Taus

User requested:
1. **All 37 scenarios** (not just 8 extreme) -- full parameter sweep for supplement
2. **By-method pipeline for f5 scenarios** -- high-frailty scenarios need 800G RAM, run one method per SLURM job
3. **All 3 CARRA tau values** (30, 90, 180 days) -- not just tau=90

### By-Method Pipeline Modifications

Modified `run_single_method.R` and `method_runners.R` to support SAVE_EXTENDED, since these are the scripts used for f5 scenarios:

**`method_runners.R` changes:**
- `run_ml_method()`: Added `save_extended` param. When TRUE, returns `$extended` with pred_type1, pred_type2, sigma_b, em_iterations, test_outcomes
- `run_cox_method()`: Added `save_extended` param. When TRUE, returns `$extended` with Cox linear predictors and test outcomes
- 4 MERF helper functions (`fit_and_predict_merfranger_strat`, `_strat_no_hist`, `_cov`, `_cov_no_hist`): Added `save_extended` param. When TRUE, return list with predictions + `model$RanEffSD` + `model$IterationsUsed`. When FALSE, return bare vectors (backward compatible)

**`run_single_method.R` changes:**
- Reads `SAVE_EXTENDED` env var
- Passes `save_extended` to method runners
- Saves to `results_extended_by_method/` when extended

**New: `combine_extended_results.R`:**
- Reads per-method files from `results_extended_by_method/`
- Merges into per-scenario files in `results_extended_complex/`
- Maps by-method naming convention to comprehensive naming convention
- Required after f5 by-method jobs complete, before post-processing

### SLURM Script Updates

**`submit_extended_comparison_array.sh`:**
- Expanded from 8 to **25 scenarios** (baseline + 12 f0 + 12 f2)
- Array `1-25`, 96G, 16 CPU, 48h

**New: `submit_extended_f5_by_method.sh`:**
- 12 f5 scenarios x 10 methods = **120 array tasks**
- 800G, 52 CPU, 240h (matching original `submit_by_method.sh`)
- Full shared library fixes (PROJ, GDAL symlink, libRlapack)
- Sets `SAVE_EXTENDED=true`

**`submit_carra_extended.sh`:**
- Changed from single tau=90 job to **3-job array** (tau=30, 90, 180)
- Upgraded resources to 300G, 50 CPU (matching original CARRA submission)
- Added full shared library fixes from `submit_carra_100_runs_age_based.sh`

---

## Complete File Inventory

### Modified (5 files)

| File | Changes |
|------|---------|
| `Simulations/comprehensive_method_comparison.R` | SAVE_EXTENDED flag, extract_merf_sigma_b (fixed to $RanEffSD), 6 sigma_b capture points, extended return list, cluster export, output dir |
| `Simulations/method_runners.R` | save_extended param on run_ml_method, run_cox_method, 4 MERF helpers; extended returns with predictions + sigma_b |
| `Simulations/run_single_method.R` | SAVE_EXTENDED env var, passthrough to runners, separate output dir |
| `Uveitis_Project/age_based_analysis/carra_model_evaluation_100_runs_age_based.R` | SAVE_EXTENDED flag, extract_merf_sigma_b (fixed), extended data collection, per-split saving |
| `Simulations/submit_extended_comparison_array.sh` | Expanded 8 -> 25 scenarios (added baseline + all f0/f2) |

### Created (13 files)

| File | Purpose |
|------|---------|
| **SLURM scripts** | |
| `Simulations/submit_extended_f5_by_method.sh` | f5 scenarios by-method (120 array tasks) |
| `Simulations/submit_timing_benchmark.sh` | Timing benchmark |
| `Uveitis_Project/age_based_analysis/submit_carra_extended.sh` | CARRA 3-tau array |
| **Core scripts** | |
| `Simulations/timing_benchmark.R` | Wall-clock timing per method (5 reps, 4 scenarios) |
| `Simulations/combine_extended_results.R` | Merge by-method results into per-scenario files |
| **Post-processing scripts** | |
| `Simulations/compute_brier_scores.R` | Task 1a: IPCW Brier scores (manual implementation) |
| `Uveitis_Project/age_based_analysis/compute_calibration_plot.R` | Task 1b: Calibration plot (Joint RF) |
| `Simulations/compute_out_of_range.R` | Task 2: Predictions outside [0,1] |
| `Uveitis_Project/age_based_analysis/compute_fairness_metrics.R` | Task 3: Sex/race-stratified C-indices |
| `Simulations/summarize_timing.R` | Task 4: Timing summary table |
| `Simulations/analyze_merf_diagnostics.R` | Task 5: sigma_b boxplot + summary |
| **Pipeline documents** | |
| `refine-logs/` (6 files) | FINAL_PROPOSAL, REVIEW_SUMMARY, REFINEMENT_REPORT, EXPERIMENT_PLAN, EXPERIMENT_TRACKER, PIPELINE_SUMMARY |

---

## Submission Sequence

```bash
# Step 1: Submit all SLURM jobs
cd comparisons/Simulations
sbatch submit_extended_comparison_array.sh    # 25 non-f5 scenarios
sbatch submit_extended_f5_by_method.sh        # 12 f5 x 10 methods
sbatch submit_timing_benchmark.sh             # timing

cd ../Uveitis_Project/age_based_analysis
sbatch submit_carra_extended.sh               # 3 tau values

# Step 2: After f5 by-method jobs complete
cd comparisons/Simulations
Rscript combine_extended_results.R

# Step 3: Post-processing (all read from results_extended_complex/)
Rscript compute_brier_scores.R
Rscript compute_out_of_range.R
Rscript summarize_timing.R
Rscript analyze_merf_diagnostics.R

cd ../Uveitis_Project/age_based_analysis
Rscript compute_calibration_plot.R
Rscript compute_fairness_metrics.R

# Step 4: Paper integration
```

---

## Key Design Decisions

- **By-method for f5 only**: f5 high-frailty scenarios need 800G RAM. Non-f5 scenarios run all methods in one job (96G sufficient).
- **Combiner script bridges the gap**: By-method produces per-method files; combiner merges them into the same per-scenario format as the comprehensive script, so all post-processing scripts work on one directory.
- **Backward compatible**: All `save_extended` parameters default to FALSE. Existing behavior unchanged when SAVE_EXTENDED env var is not set.
- **CARRA 3 taus**: Paper reports tau=30, 90, 180. Extended runs needed for all three to compute calibration and fairness across horizons.
- **sigma_b via $RanEffSD**: Confirmed by audit. Initial implementation checked wrong fields ($Sigma, $sigma) -- fixed in all 3 files.

## Session Continuation (2026-04-11): Post-Run Fixes for Longleaf Flat Layout

### Context
CARRA tau=180 run completed on Longleaf (77/100 splits). Ran post-processing scripts; found path bugs due to Longleaf flat layout vs. Mac nested structure.

### Fixes Applied
- **[09:00] compute_calibration_plot.R** — Removed hardcoded `results_carra_evaluation_age_based_100_runs_tau90/extended` and `../../Paper/figures` paths. Now auto-detects all available tau directories via `list.dirs()` + grep; outputs to `analysis_extended/`; loops over all taus. Tested parse: OK.
- **[09:05] compute_fairness_metrics.R** — Removed hardcoded tau=90. Now auto-detects all tau dirs; outer loop over taus; adds `tau` column to all data frames; `group_by(tau, event_type, ...)` in summary. Tested parse: OK.
- **[09:10] compute_out_of_range.R** — Fixed Longleaf flat path detection. Also fixed runtime bug: `sapply()` on empty character vector returns named list (not logical vector), causing `found[has_ext]` to fail with "invalid subscript type 'list'". Fixed with `if (length(found) == 0) next` guard and `vapply(..., logical(1))`. Tested parse: OK.

## Session Continuation (2026-04-17): IPCW Brier Score Normalization Fix

### Fix Applied

- **[~08:45] compute_brier_scores.R:84** — Changed `return(bs_sum / w_sum)` to `return(bs_sum / n)`. The original `/w_sum` normalization computed a weighted average over non-censored subjects only, removing the IPCW correction's unbiasedness. The correct Graf et al. (1999) formula divides by n (total subjects); IPCW weights have expectation 1 so dividing by n gives an unbiased estimate of E[(Y(τ) − p̂)²]. Confirmed by NotebookLM (ML for Recurrent Events notebook) and Interpretable AI notebook. Note: competing-events validity concern from NotebookLM does NOT apply here — type-2 events are ignored (not censored at competing-event time), so the estimand is a valid marginal P(type-1 event within τ) with only administrative censoring requiring IPCW adjustment.

---
**Context compaction (auto) at 10:35**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 18:32**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 23:18**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 01:16**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (manual) at 09:18**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 09:00**
Check git log and quality_reports/plans/ for current state.
