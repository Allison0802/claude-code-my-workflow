# Session Log: OLMC Experiment Bridge

**Date:** 2026-03-21
**Skill:** /experiment-bridge
**Status:** CODE READY — awaiting Longleaf transfer and Block 1 pilot submission

---

## Plan Loaded

- Method: OLMC (Orthogonal Landmark Mark Classifier) — cross-fitted DR estimator for mu_k(h)
- 6 experiment blocks; Blocks 1-5 required for Biometrics submission (~41-47 node-hours)
- All R code pre-built in `Claude idea/R/`: functions_olmc.R, dr_estimator.R, evaluation.R, block1_sanity.R
- SLURM script: `Claude idea/slurm/submit_block1_pilot.sh`

## Bugs Fixed (2026-03-21)

- [CRITICAL] `block1_sanity.R` line 42: `script_dir` used `dirname(here::here("R/..."))` which resolved to `project_root/R`, then appended `"R/functions_olmc.R"` → double `R/R/` path, would crash on first `source()` on SLURM. Fixed to `here::here()` (project root).
- [MEDIUM] `dr_estimator.R` `fit_censoring_model()`: dead subjects incorrectly marked as `C_event = 1` because `C_si = T_sD` and the old condition `C_si <= min(T_sN, T_sD, w)` was trivially true for them. Fixed to `C_event = I(delta_N == 0 & !(died_in_window))`, so death correctly competes with censoring.
- [LOW] `dr_estimator.R` `compute_if_corrections()`: removed stale first assignment to `gc_at_TsN` (dead code, immediately overwritten by the per-subject loop).
- Created `.here` file in `Claude idea/` to anchor `here::here()` on Longleaf.

## Pre-Submission Checklist

- [ ] Transfer `Claude idea/` to Longleaf: `rsync -av "Claude idea/" yumeiy@longleaf.unc.edu:~/Research/OLMC/`
- [ ] Verify R packages on Longleaf: `tidyverse`, `survival`, `here`, `ranger`
- [ ] Submit Block 1 pilot: `bash slurm/submit_block1_pilot.sh`
- [ ] Collect results after completion: `Rscript R/collect_block1.R`
- [ ] Check kill criterion: DR-oracle bias < 0.005, coverage ≥ 0.93 at n=1000

## Next Steps

After Block 1 pilot passes gate → submit Block 2 pilot (200 reps, 4 DR conditions).
After Block 2 pilot passes → submit Blocks 3+4 in parallel (1000 reps each).
