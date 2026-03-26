# Manuscript Review: Stratified vs. Joint Pseudo-Observation Random Forests for Dynamic Prediction of Multi-Type Recurrent Events

**Date:** 2026-03-24
**Reviewer:** review-paper skill

## Summary Assessment

**Overall recommendation:** Reject / major reconceptualization needed before resubmission

This paper addresses an important problem: dynamic prediction for recurrent events with multiple event types using pseudo-observation-based machine learning. The comparison of stratified versus joint forests, and the attempt to add mixed-effects structure, are practically interesting and potentially useful for registry data.

The main problem is that the statistical target does not appear to match the claimed prediction task. The manuscript states that it predicts the probability of remaining free of event type `k` over a future window, but the pseudo-observation construction treats other event types as censoring. In a multi-type recurrent process, that produces a cause-specific first-event quantity rather than the marginal probability of no type-`k` event by the horizon when other event types may occur before `k`. Because this issue is central to the method, I do not think the manuscript is ready for a methods journal in its current form.

## Main Strengths

1. The paper tackles a substantively important and methodologically nontrivial prediction problem.
2. The stratified-versus-joint comparison is a useful design question with real applied relevance.
3. The history-feature construction is interpretable and clinically plausible.
4. The simulation study is broad in size, and the CARRA application is relevant and data-rich.

## Main Concerns

### MC1: Estimand and estimator are misaligned in the multi-type recurrent setting
- **Dimension:** Econometrics / Identification
- **Issue:** The paper claims to target the probability of remaining free of event type `k` over a horizon, but the construction censors other event types and uses a cause-specific Kaplan-Meier estimator. In a recurrent multi-type process, a subject can have a non-`k` event before subsequently having a type-`k` event within the same horizon. Censoring at the non-`k` event does not estimate the claimed quantity unless very strong assumptions hold and the estimand is redefined.
- **Suggestion:** Redefine the target explicitly and choose an estimator consistent with that target. If the target is "no type-`k` event by `t + tau` regardless of other event types," do not censor at non-`k` events; instead use a counting-process or multi-state formulation. If the target is about the next event type, use a multi-state / Aalen-Johansen formulation and define the interpretation accordingly.
- **Location:** Section 2.4

### MC2: The simulations do not test the paper's central conceptual claim
- **Dimension:** Argument / Econometrics
- **Issue:** The motivation emphasizes cross-event dependence and information sharing across event types, but the simulation generator mainly varies shared frailty, baseline nonlinearity, censoring, and covariate correlation. It does not clearly encode direct cross-type dependence or event-type transition structure of the sort the joint model is supposed to exploit.
- **Suggestion:** Add scenarios where the hazard of type `k` depends on recent occurrence or count of other event types, vary similarity of type-specific regression surfaces, and vary event-type imbalance more systematically. Report those results as the primary evidence for the joint model.
- **Location:** Section 4.1-4.3

### MC3: Comparator set is too weak for a statistical methods paper
- **Dimension:** Literature / Econometrics
- **Issue:** The paper compares mainly against a Cox benchmark. For this problem, relevant alternatives include multi-state / competing-risks landmark models, joint frailty or multivariate frailty models, and simpler pseudo-observation regressions. Without these, the claims of methodological advantage are under-supported.
- **Suggestion:** Add at least one strong semiparametric recurrent-event comparator and one pseudo-observation regression comparator. If computation is a concern, state that explicitly and include a reduced but defensible comparator set.
- **Location:** Sections 4 and 5

### MC4: Performance assessment is too narrow and partly mismatched to the prediction target
- **Dimension:** Presentation / Econometrics
- **Issue:** The main outcome of the method is a predicted event-free probability, but evaluation is almost entirely through C-indices. The overall C-index is an unweighted average across landmarks, which can overweight sparse late landmarks. The paper also does not provide calibration assessment, Brier scores, or uncertainty intervals for model differences.
- **Suggestion:** Add calibration plots and Brier or integrated Brier scores, report uncertainty for simulation and application comparisons, and either weight the overall concordance measure by comparable pairs/risk set size or justify the unweighted summary.
- **Location:** Section 2.5, Sections 4-5

### MC5: Several definitions are incomplete or inconsistent, hurting reproducibility
- **Dimension:** Writing / Presentation
- **Issue:** `C_i(t)` is undefined; `eta_i^{(k)}(t)` is undefined when no future type-`k` event exists; the definition of `X_i^{(k)}(t)` is inconsistent with the later statement that it is the time to the next observed event or censoring; notation alternates between type-specific survival to `tau` and generic event-time notation. These are not cosmetic issues because they affect the actual implementation.
- **Suggestion:** Rewrite Section 2 with explicit row-level definitions, edge cases, and pseudocode. State exactly what observation enters the pooled joint dataset, and how non-`k` events, censoring, and no-future-event cases are handled.
- **Location:** Sections 2.2-2.5

### MC6: The application description raises a potential temporal leakage problem
- **Dimension:** Identification / Presentation
- **Issue:** Medication exposure is described as occurring during follow-up, but later appears in the baseline predictor set. If post-baseline treatment history is used as a baseline feature, the application is not a fair dynamic prediction exercise.
- **Suggestion:** Define the measurement time for every predictor. If medication is time-varying, update it at each landmark; if it is baseline-only, rewrite the cohort description so this is unambiguous and rerun analyses if necessary.
- **Location:** Section 5.1-5.2

## Minor Concerns

1. The manuscript repeatedly uses phrases such as "rigorous extension" and "asymptotic validity" without providing new theory for the multi-type or MERF extensions.
2. The terms "multi-type recurrent events," "competing risks," and "cause-specific censoring" are used in a way that could confuse readers about the actual data-generating setup.
3. Predictions from random-forest regression on pseudo-observations are not guaranteed to lie in `[0,1]`; the paper should discuss truncation or calibration if probabilities are reported clinically.
4. The results section often makes directional claims without giving effect sizes, Monte Carlo standard errors, or confidence intervals.
5. Several tables/figures are referenced descriptively, but the manuscript text needs more self-contained quantitative summaries in the main paper.

## Referee Objections

### RO1: What exactly is the estimand for event type `k` after landmark `t`?
**Why it matters:** If the estimand is not correctly defined, the pseudo-observation regression is solving the wrong problem.
**How to address it:** State the target in counting-process or multi-state notation and align the estimator and evaluation metric to that target.

### RO2: Why should a joint forest help if the simulation does not generate true cross-type dependence?
**Why it matters:** The main design claim of the paper is about information sharing across event types.
**How to address it:** Simulate explicit cross-type effects and show when pooling helps versus hurts.

### RO3: Why is superiority over Cox enough, given the availability of frailty and multi-state alternatives?
**Why it matters:** Methods papers are judged against the best existing methods, not just a convenient baseline.
**How to address it:** Add stronger comparators or narrow the claims substantially.

### RO4: How trustworthy are the reported gains without calibration or uncertainty quantification?
**Why it matters:** Small C-index differences may be noise, and a probability model should be judged on more than ranking.
**How to address it:** Report paired uncertainty measures, Brier scores, and calibration diagnostics.

## Bottom Line

The paper has an interesting applied idea, but the current formulation does not yet meet the standard for a statistical methods journal. I would encourage the authors to revise around a clearly defined multi-state or counting-process estimand, strengthen the simulation/comparator design, and tighten the presentation substantially before resubmission.
