# Experiment Plan: Doubly Robust Pseudo-Observations for Missing Event Type Labels

**Method:** Two-stage DR pseudo-observation estimator for type-specific cumulative rate functions under MAR event type labels, with cross-fitted ML nuisance estimators
**Target:** *Biostatistics* (primary), *JASA T&M* (if efficiency bound developed)
**Date:** 2026-03-22
**Infrastructure:** R + SLURM (UNC Longleaf), extending `Missing Types/` project infrastructure

---

## Scientific Context

The Missing Types project already compares 7 methods (CCA, IPW, IPW-RF, RPM, RPM-RF, DR, DR-RF) for handling missing event type labels in recurrent competing risks. However, all existing DR implementations treat pseudo-observations as oracle outcomes — they do not propagate pseudo-observation estimation uncertainty through the DR correction layer.

**Idea 7 contribution:** Derive the full two-stage influence function that accounts for uncertainty in both:
1. The pseudo-observation estimate itself (Overgaard et al. 2017)
2. The DR/AIPW correction for missing type labels (Ma et al. 2022 extension)

This yields a formally doubly robust pseudo-observation estimator with valid variance and coverage guarantees.

---

## Common Experimental Design

**Data generation:** `rate_cox_data_gen_complex()` from `Missing Types/functions.R`
- K = 2 event types (matching existing Missing Types infrastructure)
- Recurrent events under Cox PH with shared frailty
- Configurable censoring rate, sample size, complexity

**Missingness mechanisms (from existing infrastructure):**
- MCAR: `introduce_mcar_missingness()` — uniform random type label deletion
- MAR: `introduce_mar_missingness()` — type label missingness depends on covariates (X, Z)

**Missingness rates:** 10%, 20%, 30%, 50%

**Monte Carlo replication sizes:**
- Pilot runs: 200 reps
- Main paper blocks: 500 reps (matching Missing Types convention)
- Appendix/sensitivity: 200 reps

**Landmark scheme:** Spacing `aa` inherited from Missing Types (default: quarterly), horizon `tau = 5*aa`

**Estimators (all blocks unless noted):**

| Label | Description | Nuisance models |
|---|---|---|
| DR-PO-CF | Proposed: DR pseudo-obs with cross-fitted nuisances, two-stage IF variance | 5-fold cross-fit by subject |
| DR-PO-naive | DR pseudo-obs treating POs as oracle (current Missing Types DR) | No IF propagation |
| DR-parametric | Parametric propensity + outcome (logistic + multinomial) | Parametric only |
| IPW-RF | RF-based propensity weighting only | Single nuisance |
| CCA | Complete-case analysis (drops missing types) | None |

---

## Block 1: Two-Stage IF Oracle Sanity Check

**Scientific question:** Is the two-stage influence function implementation correct? Does the IF-based variance match Monte Carlo variance?

**DGM:**
- K = 2, n ∈ {200, 500, 1000, 2000}
- Missingness: MAR at 20% (moderate, well-identified)
- Censoring: 15%, independent
- Simple parametric forms so true rate functions are available analytically

**Estimators:** DR-PO-CF with oracle nuisances (true propensity + true outcome model plugged in), DR-PO-CF with correct parametric nuisances

**Primary metrics:**
- Monte Carlo bias for type-specific cumulative rate at landmark times
- Empirical variance vs IF-based variance ratio (should → 1.0)
- 95% CI coverage at each n
- Comparison: naive variance (ignoring PO uncertainty) vs two-stage IF variance

**Expected finding:** Two-stage IF variance matches MC variance; naive variance underestimates (coverage < 95%); both converge as n grows.

**Kill criterion:** Persistent bias or coverage failure for oracle estimator at n ≥ 1000 → derivation or coding error.

**Run first.** Estimated SLURM: ~4–6 node-hours (4 n sizes × 200 reps pilot, then 500 reps)
**Output:** Table of bias/variance/coverage by n — supplement

---

## Block 2: Double-Robustness 2×2 Matrix

**Scientific question:** Does the estimator maintain consistency under one-correct nuisance specification?

**DGM:**
- K = 2, n = 500
- Missingness: MAR at 30% (moderate-high, stresses propensity)
- Censoring: 20%
- Nonlinear covariate effects on both missingness and outcome

**DR conditions (2 × 2 matrix):**

| | Propensity correct | Propensity wrong |
|---|---|---|
| **Outcome correct** | DR-both-correct | DR-prop-wrong |
| **Outcome wrong** | DR-out-wrong | DR-both-wrong |

**Misspecification details:**
- Propensity wrong: fit intercept-only logistic (ignores all covariates)
- Outcome wrong: fit intercept-only multinomial (ignores all covariates)

**Primary metrics:**
- Bias and RMSE for type-specific cumulative rate
- 95% CI coverage
- Comparison to single-robust: IPW-only, outcome-regression-only

**Expected finding:** DR stays near-unbiased in both one-correct cells; both-wrong shows bias comparable to single-robust methods.

**Kill criterion:** No separation between one-correct and both-wrong → DR property not functioning.

**Run second.** Estimated SLURM: ~6–8 node-hours (4 conditions × 500 reps)
**Output:** Main paper Table 1 — 2×2 bias/coverage matrix

---

## Block 3: Practical Bias Demonstration (Existing Methods Comparison)

**Scientific question:** How much bias do existing Missing Types methods show, and does DR-PO-CF eliminate it?

**DGM:**
- K = 2, n = 500
- Missingness: MAR at {10%, 20%, 30%, 50%}
- Censoring: 20–30% (moderate)
- Strong MAR mechanism: missingness depends on treatment, prior event count, covariate interactions

**Estimators:** DR-PO-CF, DR-PO-naive, DR-parametric, IPW-RF, CCA

**Primary metrics:**
- Absolute bias for type-specific cumulative rate across missingness rates
- RMSE comparison
- CI coverage: DR-PO-CF (two-stage IF) vs DR-PO-naive (ignoring PO uncertainty)
- C-index recovery: how close each method's prediction gets to the no-missingness oracle C-index

**Expected finding:**
- CCA: increasing bias with missingness rate
- IPW-RF: unbiased if propensity correct, but high variance at 50%
- DR-PO-naive: near-unbiased point estimates but anti-conservative CIs
- DR-PO-CF: near-unbiased with correct CI coverage

**Kill criterion:** DR-PO-CF shows no coverage improvement over DR-PO-naive → two-stage IF adds nothing practical.

**Run third.** Estimated SLURM: ~8–10 node-hours (4 missingness rates × 5 estimators × 500 reps)
**Output:** Main paper Figure 1 — bias + coverage by missingness rate

---

## Block 4: Cross-Fitting Benefit

**Scientific question:** Does cross-fitting with ML nuisance estimators improve over parametric DR?

**DGM:**
- K = 2, n = 500
- Missingness: MAR at 30%
- Censoring: 25%
- Complex nonlinear/interaction DGM (current Missing Types "complex" scenario)

**Estimators:**
- DR-PO-CF with RF nuisances (5-fold cross-fit by subject)
- DR-PO-CF with parametric nuisances (5-fold cross-fit)
- DR-parametric (no cross-fitting)
- IPW-RF (no cross-fitting)

**Primary metrics:**
- Bias and RMSE
- CI coverage
- n^{-1/4} convergence check: does cross-fitting satisfy DML rate conditions?

**Expected finding:** Cross-fitted RF reduces bias relative to parametric DR in complex DGM; convergence is stable.

**Kill criterion:** Cross-fitting with RF is unstable (convergence failures, extreme weights) at n = 500.

**Run fourth.** Estimated SLURM: ~6–8 node-hours
**Output:** Main paper Table 2 — cross-fitting benefit

---

## Block 5: MCAR vs MAR Sensitivity

**Scientific question:** Does the DR advantage persist under MCAR (where simpler methods should suffice)?

**DGM:**
- K = 2, n = 500
- Missingness: MCAR at {20%, 30%, 50%} and MAR at {20%, 30%, 50%}
- Censoring: 20%

**Estimators:** DR-PO-CF, CCA, IPW (logistic), IPW-RF

**Primary metrics:**
- Bias and coverage under MCAR vs MAR
- Efficiency comparison: variance ratio DR-PO-CF / CCA under MCAR (expect ≈ 1 or modest loss)

**Expected finding:** Under MCAR, CCA is unbiased but inefficient; DR-PO-CF matches or slightly exceeds. Under MAR, CCA fails; DR-PO-CF remains valid.

**Kill criterion:** DR-PO-CF has dramatically worse efficiency than CCA under MCAR → practical cost of DR too high.

**Run fifth.** Estimated SLURM: ~8–10 node-hours
**Output:** Supplement Table — MCAR vs MAR comparison

---

## Block 6: Variance Estimator Validation (Appendix)

**Scientific question:** Does the two-stage IF variance provide correct coverage across a range of scenarios?

**DGM:**
- K = 2, n ∈ {200, 500, 1000}
- Missingness: MAR at {20%, 30%}
- Censoring: {15%, 30%}
- Both simple and complex DGMs

**Estimators:** DR-PO-CF only, comparing three variance estimators:
- Two-stage IF (proposed)
- Naive (treating POs as oracle)
- Bootstrap (gold standard, expensive)

**Primary metrics:**
- 95% CI coverage for each variance estimator
- Width ratio: IF-based / bootstrap (should be ≈ 1)

**Expected finding:** Two-stage IF tracks bootstrap; naive undercovers by 3–8%.

**Kill criterion:** Two-stage IF coverage consistently worse than naive → IF derivation is wrong.

**Run last (appendix).** Estimated SLURM: ~10–14 node-hours (bootstrap is expensive)
**Output:** Supplement Table — variance estimator comparison

---

## Publication Decision Gate

**Biostatistics submission requires ALL of:**

| Block | Gate criterion |
|---|---|
| Block 1 | Oracle DR-PO-CF: negligible bias, IF variance ≈ MC variance, coverage ≥ 93% at n ≥ 500 |
| Block 2 | One-correct DR: near-unbiased; both-wrong: clear bias; separation ≥ 0.02 |
| Block 3 | DR-PO-CF coverage ≥ 93% across missingness rates; DR-PO-naive undercoverage visible |
| Block 4 | Cross-fitted RF DR ≤ parametric DR bias in complex DGM |
| Block 5 | DR-PO-CF valid under both MCAR and MAR; efficiency cost under MCAR ≤ 15% |

**Minimum publishable subset:** Blocks 1–5. Block 6 strengthens but is appendix material.

---

## Run Order

1. **Block 1 pilot (200 reps, K=2, n=500)** — verify IF implementation
2. **Block 2 pilot (200 reps)** — verify DR mechanism
3. **Block 1 full (500 reps) + Block 3 (500 reps)** — parallel after pilots pass
4. **Block 2 full (500 reps) + Block 4 (500 reps)** — parallel
5. **Block 5 (500 reps)** — MCAR/MAR sensitivity
6. **Block 6 (200 reps)** — variance validation (after Blocks 1–5 pass)

---

## Total Compute Budget

| Block | Node-hours | Priority |
|---|---|---|
| Block 1 (pilot + full) | 4–6 | REQUIRED |
| Block 2 (pilot + full) | 6–8 | REQUIRED |
| Block 3 (full) | 8–10 | REQUIRED |
| Block 4 (full) | 6–8 | REQUIRED |
| Block 5 (full) | 8–10 | REQUIRED |
| Block 6 (appendix) | 10–14 | OPTIONAL |
| **Total** | **42–56** | — |
| Overhead (30%) | ~13–17 | — |
| **Grand total** | **~55–73 node-hours** | ~1–2 cluster days |

---

## Reuse from Missing Types/ Project

| Component | Source | Reuse? |
|---|---|---|
| Data generation | `Missing Types/functions.R` → `rate_cox_data_gen_complex()` | Direct reuse |
| Landmark transformation | `Missing Types/functions.R` → `transform_with_covariates_complex()` | Direct reuse |
| Pseudo-observations | `Missing Types/functions.R` → `generate_km_pseudoEst()` | Direct reuse |
| MCAR/MAR missingness | `Missing Types/functions.R` → `introduce_*_missingness()` | Direct reuse |
| Propensity models | `Missing Types/functions.R` → `fit_propensity_model*()` | Direct reuse |
| DR indicators | `Missing Types/functions.R` → `compute_dr_indicators*()` | Extend for IF |
| C-index evaluation | `Missing Types/functions.R` → `custom_c_index_time_specific()` | Direct reuse |
| SLURM template | `Missing Types/submit_missing_types_dr.sh` | Adapt |
| **Two-stage IF derivation** | — | **NEW (core contribution)** |
| **IF-based variance** | — | **NEW** |
| **Cross-fitting protocol** | — | **NEW** |
| **Misspecification wrappers** | — | **NEW** |
