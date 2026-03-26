# Experiment Tracker: OLMC

**Last updated:** 2026-03-21
**Status:** ALL BLOCKS IMPLEMENTED — Ready for Longleaf deployment

---

## Block Status

| Block | Status | Reps | Pass/Fail | Notes |
|---|---|---|---|---|
| Block 1 pilot (K=2, n=1000, 200 reps) | 🟢 CODE TESTED | — | — | Local sanity passed (2 reps, n=100); transfer to Longleaf then `bash slurm/submit_all.sh 1` |
| Block 2 pilot (200 reps) | 🟢 CODE TESTED | — | — | Local sanity passed (1 rep, n=1500); `bash slurm/submit_all.sh 2` |
| Block 3 full (1000 reps) | 🟢 CODE TESTED | — | — | Local sanity passed (1 rep, DR); `bash slurm/submit_all.sh 3` |
| Block 4 full (1000 reps) | 🟢 CODE TESTED | — | — | Local sanity passed (1 rep, all estimators); `bash slurm/submit_all.sh 3` |
| Block 1 full (1000 reps) | 🟡 READY | — | — | Run after pilot passes; need submit_block1_full.sh |
| Block 2 full (1000 reps) | 🟡 READY | — | — | Run after pilot passes; need submit_block2_full.sh |
| Block 5 full (1000 reps) | 🟢 CODE TESTED | — | — | Syntax verified; `bash slurm/submit_all.sh 5` |
| Block 6 appendix (500 reps) | ⬜ NOT STARTED | — | — | Optional, last |

---

## Gate Checks

| Gate | Status | Criterion |
|---|---|---|
| Block 1 pilot | ⬜ | DR-oracle bias < 0.005, coverage >= 93% at n=1000 |
| Block 2 pilot | ⬜ | DR one-correct: bias < 0.01; both-wrong: bias > 0.03 |
| Block 3 | ⬜ | Naive bias >= 0.10 in >= 1 scenario |
| Block 4 | ⬜ | CR methods miscalibrated or undefined for H1+ |
| Block 5 | ⬜ | Coverage >= 91% for pi_k(h) at q(h) >= 0.10 |
| FINAL: Biometrics-ready | ⬜ | All 5 gates pass |

---

## Code Development Status

| Component | Status | Notes |
|---|---|---|
| generate_olmc_data() (K types + death, log-normal frailty) | ✅ DONE | R/functions_olmc.R; overflow cap added 2026-03-21 |
| Landmark dataset builder (J_s, T_sN, T_sD, C_si, tau_i) | ✅ DONE | R/functions_olmc.R |
| History strata H0-H3 classifier | ✅ DONE | R/functions_olmc.R |
| DR estimator for mu_k(h) (EIF implementation) | ✅ DONE | R/dr_estimator.R |
| Censoring survival estimator (Cox by H_s) | ✅ DONE | R/dr_estimator.R |
| Outcome regression M_k(H_s) (logistic + ranger) | ✅ DONE | R/dr_estimator.R |
| Subject-level cross-fitting (5-fold split by subject) | ✅ DONE | R/dr_estimator.R |
| Normalization to pi_k(h) with q(h) threshold | ✅ DONE | R/dr_estimator.R |
| Variance: subject-clustered influence-function SE | ✅ DONE | R/dr_estimator.R |
| Evaluation metrics: bias, RMSE, coverage, log loss, calibration | ✅ DONE | R/evaluation.R |
| True mu_k(h) (oracle, exponential DGM, Block 1) | ✅ DONE | R/evaluation.R |
| Block 1 simulation script (4 estimators, 3 n sizes) | ✅ DONE | R/block1_sanity.R |
| Block 2 simulation script (2x2 DR matrix + 2 single) | ✅ DONE | R/block2_dr_matrix.R |
| Block 3 simulation script (5 estimators incl naive) | ✅ DONE | R/block3_naive_bias.R |
| Block 4 simulation script (DR vs CR methods) | ✅ DONE | R/block4_cr_comparison.R |
| Block 5 simulation script (rare-event stability) | ✅ DONE | R/block5_rare_event.R |
| Results collection: Block 1 | ✅ DONE | R/collect_block1.R |
| Results collection: Block 2 | ✅ DONE | R/collect_block2.R |
| Results collection: Block 3 | ✅ DONE | R/collect_block3.R |
| Results collection: Block 4 | ✅ DONE | R/collect_block4.R |
| Results collection: Block 5 | ✅ DONE | R/collect_block5.R |
| SLURM: Block 1 pilot | ✅ DONE | slurm/submit_block1_pilot.sh |
| SLURM: Block 2 pilot | ✅ DONE | slurm/submit_block2_pilot.sh |
| SLURM: Block 3 full | ✅ DONE | slurm/submit_block3_full.sh |
| SLURM: Block 4 full | ✅ DONE | slurm/submit_block4_full.sh |
| SLURM: Block 5 full | ✅ DONE | slurm/submit_block5_full.sh |
| SLURM: Master orchestrator | ✅ DONE | slurm/submit_all.sh |

---

## Bug Fixes

| Date | Bug | Fix | File |
|---|---|---|---|
| 2026-03-21 | 3 initial bugs in Block 1 code | Fixed (prior session) | R/block1_sanity.R |
| 2026-03-21 | generate_olmc_data() overflow with history_on_rec=TRUE | Added `min(lp_k, 10)` / `min(lp_D, 10)` caps | R/functions_olmc.R |
| 2026-03-21 | Block 4 SLURM estimator names mismatched | Fixed to Proposed-DR, Fine-Gray, CS-Cox-noHist, Baseline-only | slurm/submit_block4_full.sh |

---

## SLURM Log

| Job ID | Block | Date | Status | Time | Notes |
|---|---|---|---|---|---|
| — | — | — | — | — | Not yet submitted |

---

## Deployment Checklist

1. Transfer `Claude idea/` to Longleaf: `rsync -av "Claude idea/" longleaf:~/Research/Claude\ idea/`
2. Run Block 1 pilot: `bash slurm/submit_all.sh 1`
3. After Block 1 completes: `Rscript R/collect_block1.R` -> check gate
4. Run Block 2 pilot: `bash slurm/submit_all.sh 2`
5. After Block 2 completes: `Rscript R/collect_block2.R` -> check gate
6. Run Blocks 3+4: `bash slurm/submit_all.sh 3`
7. After complete: collect and check gates
8. Run Block 5: `bash slurm/submit_all.sh 5`
9. All gates pass -> ready for `/auto-review-loop`
