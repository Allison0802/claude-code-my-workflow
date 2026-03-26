# Idea Discovery Report

**Direction:** Survival probability prediction for recurrent events with multiple event types (not competing risks) using machine learning methods
**Date:** 2026-03-16
**Pipeline:** research-lit → idea-creator → novelty-check → research-review

---

## Executive Summary

The most publishable idea is **Idea 7 (Doubly Robust Pseudo-Observations with formal theory)**, which directly deepens the existing Missing Types/ project with semiparametric guarantees (65% chance of top-journal publication if theory is executed correctly). The **foundational methods paper (Idea 1: MTLRF)** is the dissertation centerpiece — the first ML prediction framework for K simultaneous non-competing recurrent event types — but requires formal impurity theory to avoid desk-rejection. **Idea 3 (Calibration)** needs fundamental reframing around the pseudo-observation bias-correction angle to be viable at top venues.

**Recommended next step:** Begin with Idea 7 theory + simulation, use Idea 1 as the parallel methods paper.

---

## Literature Landscape

### Gap Matrix (March 2026)

| Setting | Parametric/Cox | Tree-based ML | Deep Learning |
|---|---|---|---|
| Single recurrent type | Well-covered | **Well-covered 2024-2025** | Partially covered |
| Recurrent + terminal | Well-covered | Covered (RecForest 2025) | Partially (TransformerLSR) |
| **Multi-type recurrent (non-competing)** | Covered (estimation only) | **EMPTY ← dissertation** | **EMPTY** |
| **Multi-type recurrent + terminal** | Covered (estimation only) | **EMPTY** | **EMPTY** |

### Key Papers

**ML precursors (single type, 2024-2025):**
- Loe, Murray, Wu (Biostatistics 2025): RF + pseudo-obs, single recurrent type — direct antecedent
- Loe et al. arXiv:2510.23764 (Oct 2025): RF + IPW pseudo-obs, alternating (2-state) events
- Bouaziz et al. (BMC 2025): RecForest — RSF with Ghosh-Lin splitting, single type + terminal
- Sun et al. (JASA 2025): Gap-time tree ensembles, global vs episode-specific, single type

**Statistical multi-type (estimation only):**
- Ghosh et al. (AJE 2023): multiRec — fully parametric, 3-4 types, dynamic effects
- Xu et al. (arXiv:2512.07973, 2025): Bayesian semiparametric joint dynamic model, multi-type
- frailtypack `multivPenal`: semiparametric, exactly 2 types, individual predictions
- Ma et al. (2022): AIPW for additive rates model, missing event types (formal DR theory)

**Calibration:**
- Austin & Steyerberg (Stat Med 2020): ICI for survival
- Austin et al. (2022): ICI for competing risks
- Alberge et al. arXiv:2602.00194 (Jan 2026): calibration for competing risks — read full PDF to confirm no recurrent events extension

**Evaluation:**
- Blanche & Gerds (Biostatistics 2024): time-dependent C-index for recurrent events (single type)

### Five Confirmed Structural Gaps

1. **ML prediction for K non-competing simultaneous recurrent event types** (primary gap)
2. **Cross-type interaction effects in ML models** (nonlinear, not captured in parametric models)
3. **Type-specific calibration metrics** for recurrent event prediction
4. **Landmark supermodel for multi-type recurrent events** with ML learners
5. **Variable importance decomposition by type** in multi-type recurrent forests

---

## Ranked Ideas (All 10)

### 🏆 Idea 7: Doubly Robust Pseudo-Observations for Missing Event Type Labels — RECOMMENDED LEAD
*PhD contribution type: Methodological / Theoretical*

**Hypothesis:** A formally doubly robust pseudo-observation estimator for type-specific cumulative rate functions under MAR event type labels is consistent if either the censoring model or missingness model is correctly specified; proving this via influence function derivation is novel relative to Ma et al. 2022 which proves AIPW for the regression coefficient, not the pseudo-observation itself.

**Core innovation:** Derive the full two-stage influence function (accounting for uncertainty in both the rate function estimation and the DR correction layer), prove double robustness for the pseudo-observation estimand specifically, establish asymptotic normality under cross-fitting with ML nuisance estimators (following Chernozhukov et al. 2018 DML framework).

**Novelty verdict:** PARTIAL → CONFIRMED with careful framing
**Closest threat:** Ma et al. (Stat Med 2022) — AIPW for additive rates model coefficients (not pseudo-obs)
**Publication probability:** 65% at Biometrics/Biostatistics if influence function is executed correctly
**Target journal:** Biostatistics (primary); JASA Theory & Methods if efficiency bound is developed
**Connection to existing work:** Direct deepening of Missing Types/ project — simulation infrastructure already built

**Critical reviewer objections (ranked by deadliness):**
1. Two-stage influence function must propagate uncertainty through both the rate function estimate and DR correction — do not treat pseudo-observations as oracle
2. Double robustness must be stated precisely for the pseudo-observation estimand, not just invoked by analogy
3. Asymptotic normality requires n^{-1/4} convergence rate conditions on nuisance RF estimators — must invoke cross-fitting

**Minimum viable improvements:**
- [ ] Derive full influence function following Overgaard et al. 2017 + Park et al. 2022 structure
- [ ] Implement 5-fold cross-fitting for ML nuisance estimators (IPW-RF)
- [ ] Design 4-scenario simulation: (both correct), (propensity correct, outcome wrong), (propensity wrong, outcome correct), (both wrong)

**Underexplored angle:** Prove or discuss whether the estimator achieves the semiparametric efficiency bound — would elevate from "valid" to "optimal"

---

### 🥈 Idea 1: Multi-Type Landmark Random Forest (MTLRF) — FOUNDATIONAL METHODS PAPER
*PhD contribution type: Methodological*

**Hypothesis:** A joint random forest with a matrix-trace impurity criterion on K-vector pseudo-observation outcomes for K non-competing simultaneous recurrent event types will outperform K independent forests by capturing cross-type correlations in split decisions, with performance gains largest in high-frailty, high-correlation scenarios.

**Core innovation:** First ML prediction framework for K simultaneous non-competing recurrent event types. Single forest with a principled multi-type impurity criterion, type-specific C-index evaluation, cross-type VIMP decomposition.

**Novelty verdict:** CONFIRMED (Medium-High confidence)
**Closest threat:** Loe et al. arXiv:2510.23764 (Oct 2025) — alternating events, not K-type joint; monitor Loe-Murray-Wu group
**Publication probability:** 40% at Biometrics/Biostatistics; higher (~60%) at Statistics in Medicine
**Target journal:** Biostatistics (extensions of Loe et al. 2025 line); Statistics in Medicine as fallback
**Connection to existing work:** Direct generalization of comparisons/ project; `rate_cox_data_gen_complex()` already generates multi-type data; needs new impurity criterion in partykit

**Critical reviewer objections (ranked by deadliness):**
1. Matrix-trace impurity criterion lacks theoretical grounding for pseudo-observation targets — must justify why trace(S_between)/trace(S_within) is appropriate for this estimand (not just for regression)
2. The "non-competing simultaneous" assumption is underspecified — must show that cross-type correlations are exploited in simulation with explicit frailty-driven scenarios
3. Must include direct comparison to randomForestSRC multivariate forest applied to pseudo-observations

**Minimum viable improvements:**
- [ ] Derive or justify weighted trace criterion using the pseudo-observation covariance matrix (Overgaard et al. 2017 influence function → K-type extension)
- [ ] Design simulation explicitly varying cross-type correlation strength (5 scenarios: independence → high correlation → frailty-driven)
- [ ] Provide OOB-based uncertainty intervals for joint predictions
- [ ] Include direct comparison to: randomForestSRC multivariate, K independent forests, multiRec (Cox parametric), frailtypack

**Underexplored angle:** Cross-type VIMP decomposition — "how much does variable X matter for type 1 vs type 2 vs the joint outcome?" — is interpretable, clinically useful, and technically novel; could be the defining secondary contribution

---

### 🥉 Idea 3: Type-Specific Calibration Metrics — NEEDS REFRAMING
*PhD contribution type: Methodological / Theoretical*

**Hypothesis (revised):** Standard calibration metrics (ICI, calibration slope) applied to pseudo-observation-based predictions are biased in finite samples because pseudo-observations are noisy estimates of the target; deriving a bias-corrected calibration metric exploiting Overgaard et al. 2017's influence function will provide valid inference where naive application fails.

**Core innovation (revised):** Formal measurement-error correction for calibration assessment when calibration targets are estimated pseudo-observations rather than true outcomes. Establishes conditions for valid vs. biased calibration assessment.

**Novelty verdict:** CONFIRMED (with reframing)
**Closest threat:** Alberge et al. arXiv:2602.00194 (Jan 2026) — calibration for competing risks — read full PDF
**Publication probability (as currently framed):** 20% at Biometrics/Biostatistics; needs reframing
**Publication probability (with bias-correction angle):** ~40-50% at Statistics in Medicine
**Target journal:** Statistics in Medicine (methods section) after reframing; Lifetime Data Analysis as fallback
**Connection to existing work:** Adds calibration column to comparisons/ evaluation table; works with existing landmark infrastructure

**Critical reviewer objections:**
1. ICI/calibration slope as standalone contribution is insufficient for top venues — must derive the formal bias from pseudo-observation uncertainty (measurement error framing)
2. Must show that pseudo-observation variance is non-negligible in practical sample sizes (n = 200-1000) — if it's negligible, there's no paper
3. Must develop and prove landmark-varying calibration test (time-varying Hosmer-Lemeshow analog) for recurrent events

**Minimum viable improvements (for reframed version):**
- [ ] Formally quantify bias in calibration slope due to pseudo-observation measurement error (using Overgaard 2017 influence function)
- [ ] Propose bias-corrected calibration slope and prove it is consistent
- [ ] Add landmark-varying calibration test across all L landmark times
- [ ] Demonstrate framework on a real dataset showing miscalibration that existing tools miss

**Underexplored angle:** Landmark-varying calibration — calibration may be good at early landmarks and deteriorate at later ones; a formal test for time-varying miscalibration is novel and connects naturally to the landmark infrastructure

---

### Idea 8: Shared Frailty RF (SREF) — BACKUP METHODS PAPER
*Impact: 4/5, Novelty: 5/5, Complexity: Medium*

Iterative pseudo-observation RF that extracts a frailty proxy from multi-type residuals and re-fits with it as an additional feature (pseudo-observation MERF analog). Genuinely novel (no paper has proposed this), but at risk of non-convergence. Could be a section within the MTLRF paper rather than a standalone paper.

---

### Idea 4: Super-Learner for Multi-Type Recurrent Events — ENSEMBLE EXTENSION
*Impact: 4/5, Novelty: 4/5, Complexity: Medium*

Stack Cox (per type), frailty Cox, RF (per type), MERF using cross-validated K-type Brier loss. Candidate learners are already built in comparisons/. Main risk: if weights collapse to one dominant learner, the paper's contribution is undermined. Best as a section within a larger methods paper.

---

### Idea 2: Cross-Type Interaction VIMP — SECTION WITHIN IDEA 1
*Impact: 4/5, Novelty: 4/5, Complexity: Medium*

Cross-type mediation VIMP: how much of X's predictive signal for type k is mediated through its effect on type j accumulation? Feasible and novel, but best as a subsection within the MTLRF paper rather than a standalone paper.

---

### Idea 10: Conformal Prediction Intervals — SHORT COMMUNICATION
*Impact: 4/5, Novelty: 4/5, Complexity: Low*

Split conformal prediction on landmark RF pseudo-observation predictions. Low complexity (50 lines of R), distributional-free coverage guarantees. Best as a Statistics in Medicine short methods note or appendix.

---

### Idea 6: Dynamic Landmark Updating — INCREMENTAL (FOLD INTO IDEA 1)
*Impact: 4/5, Novelty: 3/5, Complexity: Low*

Adding richer history features (gap since last type-k event, event count variance) to the landmark RF and comparing dynamic vs. static baselines. Should be folded into the MTLRF simulation study as a feature engineering subsection.

---

### Eliminated Ideas

| Idea | Reason |
|---|---|
| 5: Gap-Time Multi-Type Forest | Lower impact (3/5), incremental over JASA 2025; useful but not standalone |
| 9: Clinical Benchmark | Lower novelty (3/5); suitable as applied chapter but not standalone methods contribution |

---

## Recommended Dissertation Architecture

Based on this pipeline, the natural 3-paper dissertation structure is:

**Paper 1 (Lead): Idea 7 — DR Pseudo-Observations for Missing Event Type Labels**
- Target: Biostatistics or JASA Theory & Methods
- Timeline: Theory-first, simulation follows existing Missing Types/ infrastructure
- Unique strength: Formal guarantees that prior work lacks; tractable given Overgaard 2017 machinery
- Includes: 4-scenario simulation (DR stress test), formal influence function, cross-fitting

**Paper 2 (Core): Idea 1 — Multi-Type Landmark Random Forest (MTLRF)**
- Target: Biostatistics or Statistics in Medicine
- Timeline: Methods paper, extends comparisons/ infrastructure
- Unique strength: First ML prediction framework for K non-competing simultaneous recurrent types
- Includes: Principled multi-type impurity criterion, cross-type VIMP, OOB uncertainty, 37-scenario simulation

**Paper 3 (Evaluation/Applied): Idea 3 (reframed) + real data**
- Target: Statistics in Medicine
- Timeline: After Papers 1-2 establish the framework
- Includes: Bias-corrected calibration metrics, landmark-varying calibration test, real data application demonstrating miscalibration

**Supporting sections (fold into Papers 1-2):**
- Idea 2 (cross-type VIMP): Section 4 of Paper 2
- Idea 8 (SREF): Subsection within Paper 2 simulation
- Idea 10 (conformal intervals): Appendix or short communication

---

## Monitoring Alerts

- **Loe-Murray-Wu group** (arXiv): Monitor for follow-up to arXiv:2510.23764 — they are actively extending the pseudo-obs RF framework and may reach the K-type non-competing setting within 6-12 months
- **arXiv:2602.00194** (Alberge et al.): Read full PDF to confirm scope does not include recurrent events calibration
- **arXiv:2512.07973** (Xu et al. Bayesian multi-type): Not an ML competitor but will be cited as the state-of-the-art statistical baseline

---

## Next Steps

- [ ] **Paper 1 (Idea 7):** Begin influence function derivation — start from Overgaard et al. 2017, extend to K-type pseudo-obs under MAR, add DR layer following Ma et al. 2022 structure
- [ ] **Paper 2 (Idea 1):** Implement multi-type impurity criterion in partykit, design 5-correlation-strength simulation, add cross-type VIMP
- [ ] **Baseline immediately:** Read full PDF of arXiv:2602.00194 (Alberge et al.) to confirm calibration novelty
- [ ] `/run-experiment` to deploy expanded simulation studies on SLURM
- [ ] `/auto-review-loop` once Papers 1-2 are drafted
