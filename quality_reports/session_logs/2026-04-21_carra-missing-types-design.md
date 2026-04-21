# Session Log: CARRA Missing-Types Real-Data Application — Design & Plan

**Date:** 2026-04-21
**Scope:** Missing Types sub-project (extends `Papers/method.tex`)
**Status:** Brainstorming + writing-plans complete; execution not yet started.

## Goal

Apply the Missing Types framework (7 imputation methods × 7 prediction models,
FL-KM pseudo-observations) to the CARRA pediatric uveitis registry as the
method paper's real-data validation. Retain the ~2,672 uveitis events the
current CARRA pipeline silently discards (1,614 `UVEITTYP = "Unknown"` + 1,057
`UVEITTYP = "Not Collected"` + 1 NA out of 7,299 total events).

## Approach

- Strategy B (NotebookLM-backed via Wang & Ding; Nevo/Wang/Nishihara):
  pooled-MAR primary analysis + mechanism-stratified sensitivity analyses
  (Unknown-only ≈ MAR-clinical, Not-Collected-only ≈ MCAR-registry) to isolate
  MNAR risk if Unknown-only diverges.
- Evaluation: 10-fold subject-stratified CV × 10 cycles; pool out-of-fold
  predictions per cycle → one c-index per (model, type, tau) per cycle → report
  mean ± SD across 10 cycles. Lower bias and honest variance vs repeated 80/20
  splits; NotebookLM-backed by RecForest and mlr3proba conventions.
- Taus: {30, 90, 180} days. tau=90 and tau=180 overlap the existing
  age-based CARRA pipeline for cross-paper comparison.
- Observed R only (no synthetic injection) — the simulation already covers
  controlled 10/20/30/50% rates.
- Covariates: same feature set as the existing age-based CARRA pipeline for
  prediction models (§6a); pre-CV bivariate logistic screening at p < 0.1
  for the IPW/RPM/DR missingness-model formula (§6b, Nevo et al.
  `MAR_{X,Z,T,Q}` condition — event time T and case-only auxiliaries
  eye_affected, CELLCHAM are candidates).
- Layout: new `Missing Types/CARRA_analysis/` subdirectory; new preprocessing
  file; legacy `comparisons/Uveitis_Project/preprocess_longitudinal_data.R`
  untouched so the age-based pipeline stays reproducible.
- SLURM: 63 tasks = 7 methods × 3 taus × 3 variants (9-task array per method).

## Changes

- [11:25] `Missing Types/quality_reports/brainstorming/2026-04-21_carra-missing-types-design/design.md` —
  wrote 11-section design spec (321 lines). Locks core architecture decisions;
  defines preprocessing, landmark+FL-KM, screening, CV driver, analysis
  outputs, paper integration, risks, and out-of-scope items. NotebookLM-backed
  (ML for Recurrent Events notebook) for Strategy B and for 10-fold CV × 10
  repeats vs repeated 80/20 splits.
- [11:40] `Missing Types/quality_reports/plans/2026-04-21_carra-missing-types-implementation.md` —
  wrote 10-task implementation plan (T0 prerequisite log_time check → T9 paper
  integration). TDD-style bite-sized steps with exact R code and bash commands
  throughout. Key integration point: surgical backward-compatible extension to
  `fit_propensity_model*` and `fit_rate_proportion_model*` in `functions.R`
  (adds `feature_set = NULL` arg; `NULL` preserves simulation default).
  Structural refactor of `simulation_runner.R` to extract the 7-model fitting
  block into `fit_seven_prediction_models_and_predict()`.
- [11:47] `Missing Types` subrepo commit `d9cb225` —
  `docs(carra): brainstorming design + implementation plan for CARRA real-data application`.
  Two files, 1876 insertions.

## Verification

- Raw CARRA event-type counts validated by direct query of
  `uveitis_data_2023-10-20_1627.csv`: 650 Acute, 3,977 Chronic, 1,057 Not
  Collected, 1,614 Unknown, 1 NA — total 7,299.
- Processed `carra_processed_slurm.rds` (legacy age-based pipeline output)
  cross-checked: current pipeline retains only the 4,087 known-type events
  and drops the 2,672 missing-type events. This confirms the scope of
  "retained information" the new preprocessing recovers.
- Design spec self-reviewed: one arithmetic typo corrected (n_notcollected
  5,184 → 5,684) and three duplicate markdown headings de-duplicated
  (`Logic`, `Outputs` across sections 3/4/5).
- Implementation plan self-reviewed: coverage of every design-spec section
  verified; Task 4 `feature_set` extension expanded with both GLM and ranger
  code examples to remove "apply the same pattern" handwaving; function-name
  consistency verified across tasks.

## Open questions / next steps

- Prerequisite (Task 0): verify the parallel log_time design (obs 912,
  design at `2026-04-21_logtime-models-and-predictions/`) is merged into
  `functions.R::prepare_rpm_data()` and `simulation_runner.R::apply_imputation_phase_b()`
  before starting Task 1. CARRA plan assumes `logT`/`log_time` is a
  valid feature in RPM/DR outcome models and IPW propensity model.
- Case-only auxiliary `CELLCHAM` availability in the merged CARRA data
  must be verified during Task 3 (landmark transform) — if absent, screening
  (Task 5) skips it silently.
- Smoke-test gate: if tau=30 pseudo-obs NA rate > 10% at Task 3.3, either
  relax `FLKM_MIN_GROUP_SIZE` to 5 or raise tau=30 → tau=45.
- Execution approach (subagent-driven vs inline) — not yet chosen by user.
- Parent-repo submodule pointer bump — deferred; will combine with the
  in-flight log_time subrepo commits into one parent commit.

## References

- Spec: `Missing Types/quality_reports/brainstorming/2026-04-21_carra-missing-types-design/design.md`
- Plan: `Missing Types/quality_reports/plans/2026-04-21_carra-missing-types-implementation.md`
- Commit: `Missing Types` subrepo `d9cb225`
- Related parallel effort: `Missing Types/quality_reports/brainstorming/2026-04-21_logtime-models-and-predictions/design.md`
- NotebookLM notebook: ML for Recurrent Events (`0bf80af5-8b8d-423d-b7ef-94b13ad48f7b`).
- [13:16] `Missing Types/CARRA_analysis/preprocess_carra_retain_missing.R` -- Task 2: CARRA preprocessing script created; retains unknown-type events (7299 events, 1307 subjects with eye involvement); three .rds artifacts saved; commit 68d1f0e. Subject count 1307 vs spec's 1562 -- spec refers to all enrolled patients (1563), while 1307 is subjects with documented eye-involvement events (correct for this pipeline).
- [13:29] Missing Types/CARRA_analysis/carra_landmark_transform.R -- Task 3: landmark transform module with history features, medication placeholders, paper H1-H3 columns; smoke test passes (390 rows, 47 subjects, event rate 0.123)
- [14:22] CARRA_analysis/screen_missingness_model.R -- Task 5: bivariate screening produced 15 selected features (p < 0.1) for the CARRA missingness model; also fixed duplicate-visits bug in carra_landmark_transform.R (20 duplicate visit_date rows in raw data caused anyDuplicated() assertion failure on full cohort); commit 6497ad8
- [15:26] Missing Types/simulation_runner.R + CARRA_analysis/carra_cv_runner.R + CARRA_analysis/test_cv_smoke.R -- Task 6: extracted fit_seven_prediction_models_and_predict() (long-format predictions, 7 canonical model labels); extended apply_imputation_phase_a/b + apply_pseudo_observations() with feature_set_missingness arg; CV driver run_carra_cv() + run_comprehensive_simulation_for_carra() drives 10-fold x 10-cycle subject-stratified CV; smoke test (N=50, 2 cycles, 3 folds, CCA, tau=90) completed in 25s with c-index range [0.23, 0.70]; CCA simulation regression + test_formula_extension.R still pass.
- [15:46] CARRA_analysis/carra_method_dispatch_*.R + submit_carra_*.sh -- Task 7 Steps 7.1-7.5 complete, 7.6 Longleaf push pending user confirmation: 7 per-method wrappers (cca/ipw/ipw_rf/rpm/rpm_rf/dr/dr_rf) each dispatching a 9-task SLURM array (3 tau × 3 variant) via run_carra_cv(); smoke test (SMOKE=true, array index 5 = tau=90/unknown_only) completed in ~20 min, 28-row output, c-index range [0.24, 0.78]; commit e6c84e7.
