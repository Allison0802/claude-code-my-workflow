# Experiment Tracker: DR Pseudo-Observations for Missing Event Type Labels

**Last updated:** 2026-03-22
**Status:** ALL BLOCKS IMPLEMENTED (1-5) — Ready for local sanity test then Longleaf deployment

---

## Block Status


| Block                                             | Status        | Reps | Pass/Fail | Notes                        |
| ------------------------------------------------- | ------------- | ---- | --------- | ---------------------------- |
| Block 1 pilot (n ∈ {200,500,1000,2000}, 200 reps) | 🟡 CODE READY | —    | —         | `bash slurm/submit_all.sh 1` |
| Block 2 pilot (6 estimators, 200 reps)            | 🟡 CODE READY | —    | —         | `bash slurm/submit_all.sh 2` |
| Block 1 full (500 reps)                           | 🟡 CODE READY | —    | —         | After pilot passes           |
| Block 3 full (4 miss rates, 500 reps)             | 🟡 CODE READY | —    | —         | `bash slurm/submit_all.sh 3` |
| Block 2 full (500 reps)                           | 🟡 CODE READY | —    | —         | After pilot passes           |
| Block 4 full (500 reps)                           | 🟡 CODE READY | —    | —         | `bash slurm/submit_all.sh 4` |
| Block 5 full (6 scenarios, 500 reps)              | 🟡 CODE READY | —    | —         | `bash slurm/submit_all.sh 5` |
| Block 6 appendix (200 reps)                       | ⬜ NOT STARTED | —    | —         | Optional, last               |


---

## Gate Checks


| Gate                       | Status | Criterion                                                       |
| -------------------------- | ------ | --------------------------------------------------------------- |
| Block 1 pilot              | ⬜      | Oracle bias < 0.005, IF var ≈ MC var, coverage ≥ 93% at n ≥ 500 |
| Block 2 pilot              | ⬜      | One-correct bias < 0.01; both-wrong bias > 0.02                 |
| Block 3                    | ⬜      | DR-PO-CF coverage ≥ 93%; naive undercoverage visible            |
| Block 4                    | ⬜      | Cross-fit RF DR ≤ parametric DR bias in complex DGM             |
| Block 5                    | ⬜      | Valid under MCAR and MAR; efficiency cost ≤ 15%                 |
| FINAL: Biostatistics-ready | ⬜      | All 5 gates pass                                                |


---

## Code Development Status


| Component                           | Status | Notes                                                          |
| ----------------------------------- | ------ | -------------------------------------------------------------- |
| Source Missing Types infrastructure | ✅ DONE | R/source_missing_types.R                                       |
| DR-PO estimator with cross-fitting  | ✅ DONE | R/dr_pseudo_obs.R (includes two-stage IF)                      |
| Two-stage IF variance estimator     | ✅ DONE | R/dr_pseudo_obs.R: compute_twostage_if_variance()              |
| Cross-fitting by subject (5-fold)   | ✅ DONE | R/dr_pseudo_obs.R: create_subject_folds()                      |
| Misspecification wrappers (Block 2) | ✅ DONE | R/dr_pseudo_obs.R: fit_propensity_wrong(), fit_outcome_wrong() |
| Block 1 simulation script           | ✅ DONE | R/block1_if_sanity.R (oracle + correct parametric)             |
| Block 2 simulation script           | ✅ DONE | R/block2_dr_matrix.R (2×2 matrix + IPW/OR only)                |
| Block 3 simulation script           | ✅ DONE | R/block3_bias_demo.R (5 estimators × 4 miss rates)             |
| Block 4 simulation script           | ✅ DONE | R/block4_crossfit.R (RF vs parametric, CF vs no-CF)            |
| Block 5 simulation script           | ✅ DONE | R/block5_mcar_mar.R (MCAR vs MAR × 3 rates)                    |
| Block 6 simulation script           | ⬜ TODO | R/block6_variance.R (bootstrap comparison, optional)           |
| Results collection: Block 1         | ✅ DONE | R/collect_block1.R                                             |
| Results collection: Block 2         | ✅ DONE | R/collect_block2.R                                             |
| Results collection: Block 3         | ✅ DONE | R/collect_block3.R                                             |
| Results collection: Block 4         | ✅ DONE | R/collect_block4.R                                             |
| Results collection: Block 5         | ✅ DONE | R/collect_block5.R                                             |
| SLURM: Block 1 pilot                | ✅ DONE | slurm/submit_block1_pilot.sh (array 1-4)                       |
| SLURM: Block 2 pilot                | ✅ DONE | slurm/submit_block2_pilot.sh (array 1-6)                       |
| SLURM: Block 3 full                 | ✅ DONE | slurm/submit_block3_full.sh (array 1-4)                        |
| SLURM: Block 4 full                 | ✅ DONE | slurm/submit_block4_full.sh                                    |
| SLURM: Block 5 full                 | ✅ DONE | slurm/submit_block5_full.sh (array 1-6)                        |
| SLURM: Master orchestrator          | ✅ DONE | slurm/submit_all.sh                                            |
| .here anchor file                   | ✅ DONE | .here                                                          |


---

## Deployment Checklist

1. ✅ Implement core R code (dr_pseudo_obs.R)
2. ✅ Implement Block 1-5 simulation scripts
3. ✅ Implement collection scripts and SLURM
4. ⬜ Local sanity test (1-2 reps, small n) — `N_REPS=2 N_SIZE=100 Rscript R/block1_if_sanity.R`
5. ⬜ Transfer to Longleaf: `rsync -av "Idea 7 - DR Pseudo-Obs/" yumeiy@longleaf.unc.edu:~/Research/Idea7_DR_PseudoObs/`
6. ⬜ Submit Block 1 pilot: `bash slurm/submit_all.sh 1`
7. ⬜ After Block 1 completes: `Rscript R/collect_block1.R` → check gate
8. ⬜ Submit Block 2 pilot: `bash slurm/submit_all.sh 2`
9. ⬜ After Block 2 completes: `Rscript R/collect_block2.R` → check gate
10. ⬜ Deploy Blocks 3-5: `bash slurm/submit_all.sh 3` then 4 then 5
11. ⬜ Collect all results → check all gates
12. ⬜ Ready for `/auto-review-loop`

