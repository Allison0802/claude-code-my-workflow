# Domain Review: simulation_runner.R and functions.R (Missing Types)

**Date:** 2026-03-27
**Reviewer:** domain-reviewer agent (5-lens statistical correctness)
**Scope:** `simulation_runner.R`, `functions.R` — NOT variance estimator subfolder
**Context:** Session following T1–T9, m1–m6 fixes; new issues only

---

## Summary

| Category | Count |
|----------|-------|
| Blocking (prevent submission) | 1 |
| Major (fix before submission) | 2 |
| Minor (fix before committing) | 5 |
| Documentation-only | 1 |
| **Total** | **9** |

---

## Lens 1: Statistical Correctness

### [BLOCKING] Issue 1.1: `generate_km_pseudoEst_weighted` targets S_k(tau), not CIF_k(tau)

**File:** `functions.R`, lines 1718–1812 (`calculate_weighted_km_survival`, `generate_km_pseudoEst_weighted`)

`calculate_weighted_km_survival` uses the product-limit (KM) formula, treating competing events as censored. This estimates cause-specific survival S_k(tau), not CIF_k(tau) = P(T_k ≤ tau, type=k). The jackknife pseudo-observations thus target S_k(tau).

The main unweighted estimator `generate_km_pseudoEst` (already fixed to use AJ) correctly targets CIF_k(tau). **Result: RPM and DR pseudo-observations are targeting a different estimand than CCA and IPW.** Any table comparing these methods is comparing results under different estimands.

The code comment at line 1759 acknowledges this as future work. That is acceptable for the code, but:
- Every results table must state this limitation prominently
- OR: approximate CIF by computing `1 - surv_full` within `generate_km_pseudoEst_weighted` to reduce the estimand gap (see suggested fix below)

**Suggested fix (minimal):** Change `calculate_weighted_km_survival` to return `1 - surv_prob` and update `generate_km_pseudoEst_weighted` to use this as the CIF approximation. Full fix (AJ with fractional weights) remains future work.

---

### [MINOR] Issue 1.2: RMST pseudo-observations target cause-specific RMST, not restricted mean CIF

**File:** `functions.R`, lines 886–979 (`generate_rmst_pseudoEst_stratified`)

`survfit(Surv(time_to_event_typeX, event_typeX))` treats competing events as censored. The resulting pseudo-observations target E[min(T_k, tau)] under cause-specific censoring, not ∫₀^τ CIF_k(t) dt. With both event types having appreciable rates (r01=0.20, r02=0.15), these differ meaningfully.

**Suggested fix:** Clarify estimand in comments and methods section. If restricted mean CIF is intended, replace with AJ pstate-based computation.

---

### [MINOR] Issue 1.3: Logistic propensity model uses in-sample fitted values, not cross-fitted

**File:** `functions.R`, lines 1866–1872 (`fit_propensity_model`)

```r
prop_scores <- predict(propensity_fit, newdata = event_data, type = "response")
```

In-sample prediction produces overfit propensity scores (pi_hat too close to 0 or 1), inflating augmentation terms R/pi × (I_k − m_k). The RF version (`fit_propensity_model_rf`) uses OOB predictions — which ARE leave-one-out. This asymmetry means DR and DR-RF are not evaluated under comparable conditions, making the DR vs DR-RF comparison confounded by estimation method, not just model class.

**Suggested fix:** Use K-fold cross-fitting (e.g., K=5) for the logistic propensity score to match the RF OOB behavior. Document the asymmetry in the paper.

---

## Lens 2: Simulation Design

### [MAJOR] Issue 2.1: DGP generates two independent Poisson processes, not standard single-spell competing risks

**File:** `functions.R`, lines 22–109 (`rate_cox_data_gen_complex`)

Type-1 and type-2 events are generated as two entirely independent non-homogeneous Poisson processes (separate `while` loops, lines 36–55 and 56–79). They share only the frailty `q.gamma` and censoring time. In standard competing risks (Fine-Gray setting), only one event type can occur per spell. Here both types can occur independently at arbitrary times — this is a recurrent multi-type point process (Aalen-Gill sense), not competing risks in the conventional sense.

This is not necessarily wrong, but:
- The paper must describe the DGP precisely as a "recurrent multi-type point process" or "recurrent competing risks" (Aalen-Gill), not standard competing risks
- The AJ estimator applied per landmark is valid for this setting but the interpretation differs
- If single-spell competing risks was intended, the DGP needs to be revised (superpose both processes and assign each event a type via thinning)

---

### [MINOR] Issue 2.2: MNAR sensitivity only varies missingness percentage, not degree of non-ignorability

**File:** `simulation_engine.R`, lines 177–188

Only two MNAR percentages (30%, 50%) are tested with a fixed non-ignorability ratio (type-1 twice as likely to be missing as type-2). Reviewers will ask about robustness as non-ignorability increases.

**Suggested fix:** Add one MNAR scenario with a 3:1 ratio to show performance degradation as non-ignorability increases.

---

## Lens 3: ML Methodology

### [MINOR] Issue 3.1: Cox interval-to-landmark join duplicates predictions across landmarks

**File:** `simulation_runner.R`, lines 944–947

```r
left_join(..., by = "id", relationship = "many-to-many") %>%
  filter(checkin >= interval_start & checkin <= interval_end)
```

Multiple landmark check-ins can fall within one Cox interval — the single Cox LP is then duplicated across all those landmarks. When the C-index is averaged over landmark times, subjects with many landmarks per interval have inflated contribution. This is acknowledged via `relationship = "many-to-many"` but not resolved.

**Suggested fix:** Document as a limitation in the paper's methods or discussion section.

---

### [MINOR] Issue 3.2: RF subject-level bootstrap uses `replace = FALSE` within each tree

**File:** `functions.R`, line 1123 (`fit_subject_weighted_rf`)

```r
model <- randomForest(..., ntree = 1, replace = FALSE, ...)
```

Each tree sees the full bootstrapped subject sample without internal row-level resampling. This is statistically valid (subject-level bootstrap provides variance), but variability is lower than standard RF. This design choice should be documented.

**Suggested fix:** No code fix needed — add a comment or paper statement clarifying this choice.

---

## Lens 4: Missing Data Handling

### [MAJOR] Issue 4.1: MAR scaling distorts logistic surface, making IPW propensity potentially misspecified

**File:** `functions.R`, lines 1262–1283 (`introduce_mar_missingness`)

The function applies a logistic score, then scales all probabilities by `scale_factor = target_prob / current_mean` to achieve the target missing rate. This linear rescaling of sigmoid outputs non-uniformly distorts the MAR surface: subjects near probability 1 are unaffected (capped at 0.95); subjects near 0 are amplified proportionally. The shape of the missingness surface changes across simulations in a covariate-density-dependent way.

**Impact:** The IPW propensity model uses the correct predictors (X, Z, XX2) but may be systematically misspecified because the logistic functional form it assumes does not match the distorted missingness surface generated by the DGP.

**Suggested fix:** Calibrate the intercept directly: solve numerically for the intercept α such that E[logistic(α + f(X,Z,XX2))] = target_prob (e.g., using `uniroot`). This preserves the logistic surface shape and ensures IPW is correctly specified by construction.

---

## Lens 5: Results Interpretation

### [MINOR] Issue 5.1: Time-specific C-indices averaged without at-risk weighting

**File:** `simulation_runner.R`, lines 530–539 (`calculate_avg_time_specific_cindex`)

```r
return(mean(valid_cindices))
```

Early landmark times have many more subjects than late times. A simple average weights a C-index from 5 subjects equally with one from 80 subjects. Since `aa` and hence the number of landmark times are data-adaptive (vary per replicate), the number of terms averaged also varies, increasing Monte Carlo variance.

**Suggested fix:** Weight by the number of comparable pairs (or at-risk count) at each landmark time. Report distribution of time-specific C-indices as a secondary diagnostic.

---

## Cross-Project Notes

### Estimand terminology inconsistency (documentation)
The knowledge base defines `mu_k(t) = E[N_k(t)]` (mean cumulative function, can exceed 1) but the pseudo-observation estimand is `CIF_k(tau) = P(N_k(tau) ≥ 1)` (probability, bounded by 1). These differ in the recurrent events setting. The paper should clarify which is the primary estimand and why CIF_k(tau) is used (it has a closed-form AJ estimator and is bounded).

### Seed reproducibility note (minor)
`clusterSetRNGStream(cl, iseed = 20260326)` in `simulation_engine.R` is fixed. Reproducibility is contingent on the same parallel cluster size — different chunk sizes will give different per-worker RNG streams. This is expected behavior and should be noted in reproducibility documentation.

---

## Priority Recommendations

| Priority | Issue | Location |
|----------|-------|----------|
| 1 (BLOCKING) | Estimand mismatch: RPM/DR use KM pseudo-obs (S_k), CCA/IPW use AJ pseudo-obs (CIF_k) | `functions.R` L1718–1812 |
| 2 (MAJOR) | Clarify DGP as recurrent multi-type (independent Poisson) not single-spell competing risks | `functions.R` L22–109 |
| 3 (MAJOR) | Fix MAR scaling to preserve logistic surface shape (use intercept calibration) | `functions.R` L1262–1283 |
| 4 (MINOR) | Cross-fit logistic propensity to match RF OOB behavior (DR vs DR-RF fairness) | `functions.R` L1866–1872 |
| 5 (MINOR) | Document RMST pseudo-obs estimand (cause-specific RMST, not restricted mean CIF) | `functions.R` L886–979 |
| 6 (MINOR) | Document Cox-to-landmark prediction duplication (many-to-many join) | `simulation_runner.R` L944–947 |
| 7 (MINOR) | Weight landmark C-index average by at-risk count | `simulation_runner.R` L530–539 |
| 8 (MINOR) | Add MNAR 3:1 ratio scenario for non-ignorability sensitivity | `simulation_engine.R` L177–188 |

---

## Confirmed Correct

| Aspect | Evidence |
|--------|---------|
| AJ jackknife pseudo-observations | `survfit(Surv(t, factor(status_cr, c(0,1,2))) ~ 1)` — correct AJ trigger; formula `n*θ − (n-1)*θ_{-i}` textbook-correct (L837–838) |
| Subject-level train-test split | `unique(id)` → `sample()` → `setdiff()` — no data leakage (L407–417) |
| DR/AIPW augmentation formula | `R/pi * (I_k − m_k)` correct; clipping explained with correct double-robustness reasoning (L2030–2042) |
| RPM/DR training filter | `type_ok`/`type_ok2` helpers correctly gate fractional-indicator rows |
| L'Ecuyer-CMRG parallel RNG | Called after `makeCluster` with fixed iseed |
| IPW XX2 inclusion | `intersect(c("X","Z","XX2"), ...)` matches `introduce_mar_missingness` DGP |
| withCallingHandlers for MERF | All 3 MERF calls scoped correctly |
