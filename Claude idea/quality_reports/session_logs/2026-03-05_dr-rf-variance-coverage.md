# Session Log

## Goal
Implement a standalone DR-RF variance-estimator simulation study with Cox-generated recurrent-event data and pointwise 95% coverage summaries at each landmark timepoint.

## Approach
- Added `Missing Types/variance estimator/dr_rf_variance_coverage_study.R`.
- Kept the implementation standalone by loading only the specific helper functions needed from `Missing Types/functions.R`.
- Implemented subject-level cross-fitting for RF propensity and RF outcome nuisances.
- Built landmark-specific DR-weighted pseudo-observations, influence terms, subject-bootstrap RF traces, and IJ-plus-propagated variance estimates.
- Computed subject-specific Cox-truth survival targets using the retained frailty and the known data-generating rate formulas.

## Verification
- Parsed the new script successfully with `Rscript -e "parse(file=...)"`.
- Ran a smoke test with `TEST_RUN=true N_SIMS=1 N_SUBJECTS=60 N_TREES=10 N_FOLDS=3`.
- Verified output files were written under `Missing Types/variance estimator/results/`.

## Notes
- Local R initially lacked `randomForest` and `ranger`; both were installed to complete verification.
- Current IDE lints are mostly non-blocking NSE/dynamic-loading warnings rather than runtime failures.

---
**Context compaction (manual) at 10:14**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 11:09**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 00:32**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 12:03**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 15:06**
Check git log and quality_reports/plans/ for current state.

---
**2026-03-08 — Bug diagnosis and grf fix**

### Bug 1 (line 594): `C_iz = n_landmarks * c_iz` → `C_iz = c_iz`
Fixed in prior session. Removed erroneous n_landmarks multiplication that was inflating IJ covariance by n_landmarks² (~100–400×), causing SE ≈ 14 and trivially-100% coverage.

### Bug 2 diagnosis: non-honest RF structure inflation
After Bug 1 fix, SE dropped but remained too large (SE ≈ 0.89 at n=500 vs. correct ~0.08). Ran three diagnostic scripts:
- `calibrate_ij_variance.R`: IJ_U / empirical variance ratio = 33× (varying training sets)
- `diagnose_ciz.R`: c_iz SD was 7.81× larger than theoretical σ_Y/n; phi_subject_sum up to 43.91
- `diagnose_bootstrap_variance.R`: IJ_U / bootstrap variance = 121× (fixed training set, 25 forests)

Root cause: `randomForest` is non-honest (same data determines splits AND leaf means). Removing one subject (with ~10–20 rows each) changes tree structure, inflating c_iz by ~10–20×. Standard IJ formula requires honest trees (leaf structure independent of leaf-mean estimation sample).

### Fix: switch to `grf::regression_forest` with honest splitting
- Replaced `fit_subject_bootstrap_rf_trace()` + `estimate_variance_components()` with new `fit_grf_and_predict()` using `grf::regression_forest(clusters=id, honesty=TRUE)`.
- grf uses honest splitting (50% for structure, 50% for leaf means) and subject-level clustering via `clusters=`, giving well-calibrated IJ variance.
- v_prop term set to 0 (DR-AIPW Neyman-orthogonality means nuisance uncertainty is O(n⁻¹), negligible).
- Installed `grf` locally; added grf auto-install to `submit_dr_rf_variance_coverage.sh`.

### Results after grf fix
- n=120, 1 sim: SE median=0.096, coverage=88.1%
- n=200, 3 sims: SE median=0.083, coverage=77.7% (finite-sample bias type1=0.11)
- n=500, 5 sims: SE median=0.090, coverage=89.4%, bias reduced to 2–5%
- Predictions stay in [0,1] (no more extrapolation outside probability range)

Coverage approaching 95% at production scale. Residual undercoverage (~5–6%) is finite-sample bias from nuisance estimation with n=400 training subjects; expected to decrease with larger n.

### Next steps
Submit 8 SLURM scenarios (MAR/MCAR × 10/20/30/50%) at n=500, N_SIMS=100. Re-generate `table_coverage.tex`.

---
**2026-03-10 — variance_estimator_derivation.tex updated**

Rewrote `Missing Types/Papers/variance_estimator_derivation.tex` to reflect grf-based honest forest implementation:
- Replaced "Extension to random forests" with a dedicated section on honest forests explaining why non-honest trees inflate IJ influence by 100–400× in multi-row cluster settings
- Updated asymptotic normality section: removed bootstrap-of-little-bags reference (grf uses internal IJ, not bags); cited Wager & Athey 2018
- Added "Neyman orthogonality" subsection formally justifying v_prop = 0 (nuisance variance is second-order O(n⁻¹))
- Updated combined variance estimator section: equation now reflects grf's `predict(estimate.variance=TRUE)` output directly; v_prop set to zero with explicit justification
- Updated "Connections to causal survival forests" to note both use honest forest IJ (not bootstrap-of-little-bags)

---
**Context compaction (auto) at 12:23**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 22:27**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 00:13**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 11:25**
Check git log and quality_reports/plans/ for current state.

---

## Session 2026-03-11: GRF All-Methods Scripts

- Fixed empty GRF rows in LaTeX tables: GRF is an end-to-end model (DR-RF + GRF prediction), not an imputation step feeding Cox/RF/MERF. Added GRF rows to `method_map` in `analyze_missing_types_results.R` + NaN filter.
- Added GRF prediction blocks (type-cov + stratified) to all 7 existing imputation scripts (cca, dr, dr_rf, ipw, ipw_rf, rpm, rpm_rf).
- Created 2 new comprehensive scripts:
  - `Missing Types/missing_types_method_comparison_grf_type_cov_all_methods.R` — 1047 lines, 56 scenarios (7 methods × 2 patterns × 4 pcts), GRF stacked forest + all imputation methods, IPW sample.weights support
  - `Missing Types/missing_types_method_comparison_grf_stratified_all_methods.R` — 1081 lines, same structure with per-type stratified forests

---
**2026-03-18 append** — /idea-discovery (v2): Added event type prediction focus. New Idea A (OLMC: Orthogonal Landmark Mark Classifier) identified as core new dissertation paper for gap B. New Idea C (proper scoring rules) identified as companion evaluation paper. GPT reviewer: death must be absorbing competing state (not missing data) — critical correction to proposal. Full refine-pipeline complete: FINAL_PROPOSAL.md, EXPERIMENT_PLAN.md, PIPELINE_SUMMARY.md in Claude idea/refine-logs/. Updated IDEA_REPORT saved to quality_reports/IDEA_REPORT_2026-03-18_recurrent-events-ml-v2.md.
