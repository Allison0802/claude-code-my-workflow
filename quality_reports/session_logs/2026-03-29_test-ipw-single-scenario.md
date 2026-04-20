# Session Log — 2026-03-29

## Task
Write a smoke test for the full IPW pipeline under one scenario.

## Log

- [11:13] Missing Types/test_ipw_single_scenario.R — created single-scenario
  smoke test: MCAR 20% / IPW logistic / n=200 / n_trees_grf=100. Sources all
  three pipeline files, runs one rep of run_comprehensive_simulation(), and
  prints formatted C-index tables for all 7 prediction models (observed-type
  and oracle/true-type evaluations).
- [11:30] Missing Types/simulation_runner.R — fixed bug: all 24 occurrences of
  `higher_is_risk = FALSE` changed to `TRUE` for pseudo-observation models
  (RF, GRF). Pseudo-obs encode CIF probability so higher = higher risk;
  FALSE was inverting the C-index, reporting ~0.35 instead of ~0.65-0.73.
  Cox models were already correct (use `TRUE`). After fix: GRF ≥ 0.70 on
  oracle eval, RF ~0.65-0.70.
- [11:45] Missing Types/functions.R — added Section 10: MERFranger() function
  implementing MERF EM algorithm with ranger base learner. Replaces dependency
  on the external MERFranger package (GitHub-only, not on CRAN). Interface
  identical to the original calls in simulation_runner.R (Y, X, random, data,
  num.trees, mtry, min.node.size, maxiter, tol; returns $Forest as ranger
  object). All 7 models now run without errors.
