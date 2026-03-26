# Session Log: 2026-03-20 — OLMC Experiment Bridge

**Goal:** Implement core R code for OLMC (Orthogonal Landmark Mark Classifier) experiment suite — Workflow 1.5 bridging idea discovery to simulations.

---

- [session start] Loaded EXPERIMENT_PLAN.md, EXPERIMENT_TRACKER.md, FINAL_PROPOSAL.md; surveyed existing comparisons/functions.R for reusable infrastructure
- [implementation] `R/functions_olmc.R` — new DGM `generate_olmc_data()` (K competing recurrent types + absorbing death, log-normal frailty, optional history-dependent hazards); landmark builder `build_landmark_dataset()` (computes T_sN, J_s, T_sD, C_si, tau_i, delta_Nk per landmark row); history strata classifier H0–H3
- [implementation] `R/dr_estimator.R` — Cox censoring model `fit_censoring_model()`; outcome regression `fit_outcome_models()` (logistic/ranger); cause-specific Cox `fit_type_hazard_models()`; EIF corrections `compute_if_corrections()` + oracle path `compute_if_oracle()`; 5-fold subject-level cross-fitting `cross_fit_dr()`; subject-clustered SE; normalization `normalize_to_pi()` with q(h) threshold
- [implementation] `R/evaluation.R` — oracle true mu_k(h) under exponential DGM (closed form); oracle nuisance factories for Block 1; `evaluate_one_rep()`, `aggregate_mc_results()`, `compute_log_loss()`, `compute_calibration()`
- [implementation] `R/block1_sanity.R` — Block 1 pilot simulation: K=2, n in {500,1000,2000}, 4 estimators (DR-oracle, DR-correct, OR-only, IPCW-only), 200 reps; kill criterion check built in; ENV-var/CLI driven for SLURM
- [implementation] `R/collect_block1.R` — collect CSVs, aggregate summary, kill criterion report
- [implementation] `slurm/submit_block1_pilot.sh` — inline heredoc SBATCH array (3 n values × 4 estimator tasks × 50 reps each); Longleaf library path fixes included
- [tracker] Updated EXPERIMENT_TRACKER.md: all 14 code components marked DONE; Block 1 pilot marked READY TO SUBMIT

**Next step:** Run Block 1 pilot on Longleaf. Command: `cd "Research/Claude idea" && bash slurm/submit_block1_pilot.sh`. After results collected, run `Rscript R/collect_block1.R` and check kill criterion gate.
