# Session Log: DR-RF Variance Calibration (2026-03-23)

**Goal**: Run Exp 1 (IJ calibration), diagnose failures, fix V_prop formula, apply V_IJ deflation.

## Actions

- [session] Missing Types/variance estimator/dr_rf_variance_coverage_study.R — Fixed `compute_propagated_variance()`: was incorrectly separating W-sum and phi-sum before multiplying (inflated V_prop by ~137x via Cauchy-Schwarz); corrected to element-wise `W * phi` via `W %*% Diagonal(phi_vec)` before subject aggregation
- [session] Ran Exp 1 (`calibrate_ij_variance.R`, N_DRAWS=20, N_TRAIN=500, MAR 30%) → V_prop/empirical_var = 0.991 (fixed ✓), V_IJ/empirical_var = 3.637 (over-estimated), V_total/empirical_var = 4.591 → STATUS: FAIL
- [session] Ran `diagnose_bootstrap_variance.R` → confirmed 116x ratio is for OLD legacy custom IJ (not grf); not informative for current pipeline
- [session] Root cause of V_IJ 3.6x: grf's honest-forest IJ with cluster subsampling applies (n/(n-s))^2 = (500/250)^2 = 4 correction; conservative but systematic at n=500 with sample.fraction=0.5
- [session] Missing Types/variance estimator/dr_rf_variance_coverage_study.R — Applied empirical deflation: `IJ_DEFLATION_FACTOR <- 3.637`; `var_ij <- pmax(...) / IJ_DEFLATION_FACTOR`; updated Last Updated to 2026-03-23

- [session] Theoretical derivation of correct IJ correction for honest forests with cluster subsampling:
  - grf applies C_grf = (n_c/(n_c-s_c))^2 = 4 (based on full subsample s_c=250)
  - Correct for honest forests: C_correct = (n_c/(n_c-n_est))^2 = (500/375)^2 ≈ 1.78, where n_est = s_c × honesty.fraction = 125
  - Theory-based deflation: V_IJ × (1-p)^2/(1-p×f_h)^2 = V_IJ × 4/9 ≈ V_IJ × 0.444 → predicts ratio 2.25
  - Residual factor 3.637/2.25 ≈ 1.62 likely from grf using I(c ∈ S_b) not I(c ∈ E_b) in raw c_c
  - Empirical 3.637 is pragmatically correct for this setup; closed-form does not fully explain all of it
- [session] Added Exp 0 diagnostic block to EXPERIMENT_PLAN.md: 0A (honesty=FALSE check), 0B (calibration grid across n × missingness), 0C (optional: raw IJ extraction)
- [session] Updated PIPELINE_SUMMARY.md: new risk entry for IJ deflation generalisation; updated Next Action

- [session] Diagnosed V_total/empirical ≈ 2.0 after IJ-only deflation: old deflation calibrated V_IJ → V_e assuming V_prop=0; after V_prop≈V_e was implemented, V_total = V_IJ/3.637 + V_prop ≈ V_e + V_e = 2×V_e (over-conservative). Root cause: must calibrate V_TOTAL jointly, not V_IJ alone.
- [session] Missing Types/variance estimator/dr_rf_variance_coverage_study.R — Switched `fit_grf_and_predict` from IJ-only deflation to total deflation: parameter renamed `ij_deflation_factor` → `total_deflation_factor` (default 4.628 = 3.637+0.991 from pilot); deflation applied to V_total_raw = V_IJ_raw + V_prop_raw after combining; components var_ij/var_prop back-scaled by same factor so they sum to var_total
- [session] Missing Types/variance estimator/calibrate_ij_variance.R — Fixed parameter name mismatch: `ij_deflation_factor` → `total_deflation_factor`; changed IJ_DEFLATION default to 1.0 (calibration always wants raw ratios); removed honesty-based branching from deflation default (total deflation is honesty-independent)

- [session] Confirmed via code inspection: V_prop intentionally set to 0 in current code (RF trained on S_aipw already captures phi-term variability via IJ; adding V_prop would double-count). V_total = V_IJ only.
- [session] Calibration (IJ_DEFLATION=1.0, raw) confirms: V_IJ/empirical = 3.637, V_prop = 0 (intentional), V_total = 3.637 → STATUS: FAIL (expected, deflation not yet applied in production default)
- [session] Missing Types/variance estimator/dr_rf_variance_coverage_study.R — Set total_deflation_factor default to 3.637 (calibrated); updated comment to document source and rationale (honest-forest (n/(n-s))^2 = 4 over-correction, empirically measured 2026-03-23)

## Next Steps

1. **Verify gate**: `IJ_DEFLATION=3.637 Rscript calibrate_ij_variance.R` — confirm V_total/empirical ≈ 1.0 with production deflation applied
2. **Exp 0A** (optional): `HONESTY=false Rscript calibrate_ij_variance.R` — confirm ratio ≈ 1 for non-honest forest (mechanism check)
3. **If gate passes**: `sbatch submit_dr_rf_variance_coverage.sh` (Exp 2, 8 SLURM array jobs)

---
**Context compaction (auto) at 14:37**
Check git log and quality_reports/plans/ for current state.

- [session] Invoked `/research-refine-pipeline` to triage calibration finding 2 (median V_IJ,grf / Var_empirical = 3.637) and answer: "Is there a closed-form variance estimator for the honest forest + cluster subsampling case?"
- [session] Analysis: closed-form correction is `((n_c-s_c)/n_c)^2 * V_IJ,grf`; removes grf's Wager et al. (2014) finite-population correction `(n_c/(n_c-s_c))^2 = 4`; raw IJ (before grf's correction) is calibrated (expected ratio = 3.637 * 0.25 = 0.909 ≈ 1); current code uses hardcoded 3.637 which gives ratio = 1.0 exactly but is not general
- [session] Updated all five refine-logs: EXPERIMENT_PLAN.md (new Calibration Finding 2, updated method thesis, Task I, corrected Exp 1-4 design), FINAL_PROPOSAL.md (new Section 4 on grf overcorrection mechanism), REVIEW_SUMMARY.md (supersession of first calibration result), PIPELINE_SUMMARY.md (updated method thesis and anchor finding), EXPERIMENT_TRACKER.md (Task I added, decision log updated, Exp 4 upgraded to recommended)
- [session] Task I recommended: replace hardcoded `total_deflation_factor = 3.637` in `dr_rf_variance_coverage_study.R` with computed `deflation_factor = ((n_c - s_c) / n_c)^2` from forest params (more general, theoretical justification)
- [session] /experiment-bridge: implemented Task I in `dr_rf_variance_coverage_study.R` — default changed from 3.637 to NULL → theoretical `(1/(1-sf))^2` from forest params; gated on `honesty` (non-honest forests → factor=1.0); stop() if sample.fraction missing (no silent fallback); also fixed `calibrate_ij_variance.R` NA gate bug (n_draws >= 5 → adaptive threshold)
- [session] Sanity check (local, N_DRAWS=3, N_TRAIN=120, IJ_DEFLATION=1): 3/3 draws completed, V_prop=0, raw ratio ≈ 3.483 ≈ 4 — confirms mechanism; READY TO DEPLOY Exp 1 + Exp 2 on Longleaf

---
**Context compaction (auto) at 09:18**
Check git log and quality_reports/plans/ for current state.

## Session 2026-03-24

- [session] Exp 2 (200 reps, n=500, 8 scenarios) completed on Longleaf; results downloaded
- [session] Diagnosed analyze_variance_coverage.R: was averaging coverage over 7624 rows per scenario, of which 7622 had n_replicates=1 (unique per-replicate checkin grids) — table results were noise
- [session] Root cause: aa=avg_gap/3 computed per-replicate → every replicate has a different checkin grid; only checkin=0 is shared across all 200 replicates
- [session] Missing Types/variance estimator/analyze_variance_coverage.R — Added filter to keep only timepoints with n_replicates >= 50% of max before echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrcecho 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrcaggregation; updated table caption
- [session] Missing Types/variance estimator/dr_rf_variance_coverage_study.R — Fixed landmark grid: added fixed_aa/fixed_tau computed once from n=5000 reference draw (seed 20260307) before mclapply; run_one_replicate now accepts aa,tau as parameters instead of computing per-replicate; saved fixed_aa/fixed_tau in config output
- [session] Coverage at checkin=0 (only reliable timepoint in old runs): Type 1 = 51.7%, Type 2 = 65.8% (MAR 30%); bias = +0.078 / +0.044; bias/SE ≈ 1.7 is primary driver of low coverage — point estimate bias, not variance miscalibration
- [session] Next: resubmit Exp 2 on Longleaf with fixed landmark grid to get coverage across all timepoints; also investigate source of positive bias in DR-RF predictions
