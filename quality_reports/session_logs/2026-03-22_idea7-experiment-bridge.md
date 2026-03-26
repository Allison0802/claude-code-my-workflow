# Session Log: 2026-03-22 — Idea 7 Experiment Bridge

## Goal
Set up fresh experiment infrastructure for Idea 7 (Doubly Robust Pseudo-Observations for Missing Event Type Labels) under a new directory, separate from the OLMC (New Idea A) code.

## Key Decisions

- Created `Idea 7 - DR Pseudo-Obs/` as a standalone project directory (not inside Missing Types/)
- Sources `Missing Types/functions.R` for data generation, landmark transformation, pseudo-observations, missingness mechanisms, and existing DR/AIPW infrastructure
- Core contribution implemented in `R/dr_pseudo_obs.R`: cross-fitted DR indicators + two-stage IF variance
- 5 simulation blocks (+ 1 optional appendix), following same structure as OLMC experiment plan

## Important Finding
The existing `Claude idea/refine-logs/` (EXPERIMENT_PLAN.md, FINAL_PROPOSAL.md, etc.) are for **OLMC (New Idea A)**, NOT Idea 7. These are different papers:
- Idea 7: DR pseudo-obs for **missing event type labels** (MAR) — deepens Missing Types project
- OLMC: Predicting **next-event type** from post-recurrence states (censoring + death) — standalone new method

## What Was Built

### Core Infrastructure (2 files)
- `R/source_missing_types.R` — bridges to Missing Types/functions.R
- `R/dr_pseudo_obs.R` — cross-fitted DR estimator, two-stage IF variance, misspecification wrappers

### Simulation Scripts (5 files)
- `R/block1_if_sanity.R` — Oracle IF verification (K=2, n ∈ {200,500,1000,2000})
- `R/block2_dr_matrix.R` — 2×2 DR robustness matrix (6 estimators)
- `R/block3_bias_demo.R` — Practical bias comparison (5 methods × 4 miss rates)
- `R/block4_crossfit.R` — Cross-fitting benefit (RF vs parametric)
- `R/block5_mcar_mar.R` — MCAR vs MAR sensitivity

### Collection Scripts (5 files)
- `R/collect_block{1-5}.R` — each with embedded kill criteria checks

### SLURM Scripts (6 files)
- `slurm/submit_block{1-5}*.sh` + `slurm/submit_all.sh` orchestrator
- All use `module load r/4.4.0`, `PROJECT_DIR=$HOME/Research/Idea7_DR_PseudoObs`

## Next Steps
1. Run local sanity test (1-2 reps, small n)
2. Transfer to Longleaf via rsync
3. Submit Block 1 pilot → check gate
4. Proceed through remaining blocks

## Open Questions
- Block 6 (bootstrap variance comparison) not yet implemented — optional appendix material
- The two-stage IF variance uses a linearized approximation; may need numerical verification against bootstrap in Block 6
