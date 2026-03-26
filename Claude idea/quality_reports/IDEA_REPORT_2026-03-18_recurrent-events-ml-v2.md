# Idea Discovery Report (v2 — Updated with Event Type Prediction)

**Direction:** Survival probability/event free time prediction AND event type prediction for recurrent events with multiple non-competing event types using machine learning methods
**Date:** 2026-03-18
**Pipeline:** research-lit → idea-creator (GPT-4o xhigh) → novelty-check → critical review (GPT-4o)
**Prior run:** IDEA_REPORT_2026-03-16_recurrent-events-ml.md (survival probability only)
**New focus:** Event type prediction — P(next event type = k | history) — completely unaddressed in literature

---

## Executive Summary

Three new publishable ideas emerged from the event type prediction gap:

1. **New Idea A (Orthogonal Landmark Mark Classifier)** — AIPW/EIF-based estimation of P(next event type = k | event occurs in [s,s+w], H_s). This is the most scientifically central contribution for the dissertation — fills the completely empty "event type prediction for recurrent events" cell with formal semiparametric theory. Reviewer called it the **core dissertation paper** for the event type gap.
2. **New Idea C (Proper Scoring Rules)** — IPCW/AIPW joint Brier and log scores for (K+1)-outcome recurrent prediction; type-specific decomposition. **Field-defining evaluation infrastructure** that strengthens every other paper. Should accompany New Idea A.
3. **New Idea B (Coherent Joint Simplex Learner)** — IPCW multinomial for K+1 outcome (no event, type 1…K) at landmark. Weaker than A without structural upgrade; may be folded into New Idea A as empirical complement.

**Revised overall dissertation priority (GPT-4o ranking):**

1. Idea 7 (DR pseudo-obs) — highest pub probability (65%, Biostatistics)
2. **New Idea A (Orthogonal Mark Classifier)** — most scientifically important gap
3. **New Idea C (Proper Scoring Rules)** — field-defining evaluation paper
4. Idea 1 (MTLRF) — ML foundation for survival prediction (40%, Biostatistics/StatMed)
5. New Idea B (Coherent Simplex) — only if structurally upgraded

**Recommended next step:** Develop New Idea A influence function + simulation; pair with New Idea C evaluation framework.

---

## Literature Landscape (Updated March 2026)

### Gap Matrix


| Setting                                         | Parametric/Cox            | Tree-based ML                           | Deep Learning     |
| ----------------------------------------------- | ------------------------- | --------------------------------------- | ----------------- |
| Single recurrent type, survival prediction      | Well-covered              | Well-covered 2024–2025                  | Partially covered |
| Recurrent + terminal event                      | Well-covered              | RecForest (BMC 2025)                    | TransformerLSR    |
| **Multi-type recurrent, survival prediction**   | Covered (estimation)      | **EMPTY ← dissertation (Idea 1 MTLRF)** | **EMPTY**         |
| **Multi-type recurrent, event type prediction** | Partially (multiRec 2023) | **EMPTY ← New Idea A**                  | **EMPTY**         |
| **Joint (survival + type) prediction**          | **EMPTY**                 | **EMPTY ← New Idea B**                  | **EMPTY**         |
| **Proper evaluation for multi-type recurrent**  | **EMPTY**                 | **EMPTY ← New Idea C**                  | N/A               |


### Key Papers

**ML precursors (single type):**

- Loe, Murray, Wu (*Biostatistics* 2025): RF + pseudo-obs, single recurrent type — arXiv:2312.00770
- Loe et al. arXiv:2510.23764 (Oct 2025): RF + IPW pseudo-obs, alternating (2-state) events
- Bouaziz et al. (*BMC* 2025): RecForest — RSF + Ghosh-Lin splitting, single type + terminal
- Sun et al. (*JASA* 2025): Gap-time tree ensembles, global/episode-specific, single type
- Boost-R (*JQT* 2021): Gradient boosted trees for cumulative intensity function

**Statistical multi-type (estimation only):**

- Ghosh et al. (*AJE* 2023): multiRec — dynamic risk model, K types, Cox-based, `multiRec` R package
- Xu et al. arXiv:2512.07973 (2025): Bayesian semiparametric joint dynamic model, multi-type
- arXiv:2509.10354 (2025): Bayesian gap-time model, multi-type recurrent + terminal
- frailtypack `multivPenal`: semiparametric, exactly 2 types, individual predictions

**Evaluation:**

- Guide to evaluating recurrent event prediction models (*Diag & Prog Res* 2025) — single type only
- Blanche & Gerds (*Biostatistics* 2024): time-dependent C-index for recurrent events (single type)
- Bouaziz (2024): generalized Brier score for single-type recurrent — no multi-type

**Competing risks (terminal, NOT recurrent):**

- Austin & Steyerberg (*Stat Med* 2020): ICI for survival
- Austin et al. (2022): ICI for competing risks
- Alberge et al. arXiv:2602.00194 (Jan 2026): calibration for competing risks (confirm no recurrent)

### Five Confirmed Structural Gaps

1. **ML prediction for K non-competing simultaneous recurrent event types** — survival probability (Idea 1 MTLRF)
2. **Event type prediction**: P(next event type = k | history) with proper censoring handling — completely empty (New Idea A)
3. **Joint prediction**: simultaneous (event-free survival probability, conditional type distribution) — empty (New Idea B)
4. **Type-specific proper scoring rules** for recurrent event ML predictions (New Idea C)
5. **Cross-type variable importance** decomposition in multi-type forests (part of Idea 1)

---

## NEW Ideas (from March 2026 Run)

### 🏆 New Idea A: Orthogonal Landmark Mark Classifier — CORE NEW CONTRIBUTION

**PhD contribution type:** Methodological / Theoretical

**Hypothesis:** Next-event type can be estimated under censoring and recurrent history by treating "first event type in [s,s+w]" as a censored multinomial missing-data target and estimating P(type = k | event occurs, H_s) via an AIPW/EIF-based orthogonal score, achieving double robustness and valid semiparametric inference when plugged into ML learners.

**Core method:**

- Define Y_{s,w} ∈ {0, 1, …, K} with 0 = no event in [s,s+w]
- Estimate P(Y = k | Y ≠ 0, H_s) via AIPW/EIF-based multinomial regression
- Nuisance models: (1) censoring model P(C > s+w | H_s), (2) event occurrence model P(Y ≠ 0 | H_s), (3) type-specific rate models
- Plug-in: tree/boosting/GAM learner for the orthogonalized score
- Death modeled explicitly as K+2 class or treated as informative censoring with shared frailty adjustment
- Cross-fitting for ML nuisance estimators (5-fold)

**Minimum viable experiment (R simulation):**

- K = 3 types, n = 500, 30–50% censoring, 15% informative death
- Compare: (1) observed-case multinomial, (2) IPCW type model, (3) AIPW orthogonalized
- Metrics: conditional type log score, type-specific calibration at each landmark
- 4 nuisance scenarios: both correct, propensity correct/outcome wrong, outcome correct/propensity wrong, both wrong
- ~3–4 hours SLURM, existing `rate_cox_data_gen_complex()` infrastructure usable with modifications

**Novelty verdict:** CONFIRMED — No existing paper estimates P(next event type | recurrent history, event occurs in window)
**Closest threat:** AIPW multiclass classification (generic) + competing risks classification (Fine-Gray, DeepHit) — but neither handles recurrent post-history landmark event type
**Novelty boundary vs competing risks:** Fine-Gray/DeepHit predict type of FIRST absorbing failure; this predicts type of NEXT recurrent non-terminal event from arbitrary history state. Subject can have (MI → stroke → MI). Once MI occurs, Fine-Gray exits — this model updates and predicts next event type.

**Publication probability:** 45–55% at *Biometrics* with full EIF derivation + double robustness result
**Target journal:** *Biometrics* (primary); *Biostatistics* as fallback
**Connection to existing work:** Extends pseudo-observation/landmark infrastructure from comparisons/ project; builds on same framework as Idea 1 MTLRF

**Critical reviewer objections (ranked by deadliness):**

1. "This is just AIPW multiclass regression on a relabeled outcome" — must show the EIF and DR result are nontrivial due to (a) time-varying landmark state, (b) repeated risk sets, (c) denominator instability under rare-event windows
2. Finite-sample instability when P(event in [s,s+w] | H_s) is small — weak denominator AIPW variance blows up; must provide stabilized weights or characterize positivity assumption
3. Must show empirically that naive observed-case and IPCW-type approaches are materially biased before proposing AIPW

**Minimum viable improvements:**

- Derive full EIF for P(Y_{s,w} = k | H_s) under right censoring + informative terminal event
- Prove double robustness for the conditional mark estimand (not just occurrence)
- Provide stabilized AIPW weights (trimming + normalization) for finite-sample stability
- Design 4-scenario simulation with DR stress test
- Add real-data illustration (ALLHAT trial or similar cardiovascular multi-type data)

**Underexplored angle:** Variable importance for event type — which predictors matter specifically for type allocation vs occurrence timing? Novel interpretability contribution.

---

### 🥈 New Idea C: Proper Scoring Rules for Recurrent Multi-Type Prediction — EVALUATION INFRASTRUCTURE

**PhD contribution type:** Theoretical / Diagnostic

**Hypothesis:** Existing recurrent-event metrics (C-index, single-type Brier) fail to evaluate joint (occurrence, type) predictions — defining IPCW joint Brier and log scores for the (K+1)-outcome recurrent prediction problem, proving strict propriety under censoring, and decomposing into occurrence vs type components provides the field's first complete evaluation framework.

**Core method:**

- Define joint (K+1)-category outcome: Y_{s,w} ∈ {0 (no event), 1 (type 1)…K (type K)}
- Extend IPCW Brier score: BS_joint = E[IPCW_weight · |Y_{s,w} - p̂_{s,w}|²]
- Decompose: BS_joint = BS_occurrence + BS_type|occurrence (Brier decomposition)
- Conditional type log score: LS_type = E[IPCW_weight · log(p̂_{k|s,w}) | Y ≠ 0]
- Prove strict propriety of each component under Cox or KM IPCW weighting
- Extend to repeated landmarks (L landmark times): landmark-aggregated Brier

**Minimum viable experiment:**

- Fit two models: (1) Cox occurrence + multinomial type, (2) misspecified Cox + uniform type
- Show standard single-type Brier fails to distinguish them; proposed joint Brier does
- Simulations under 4 scenarios varying type imbalance and censoring
- ~2 hours SLURM

**Novelty verdict:** CONFIRMED — No existing recurrent-event Brier score handles multiple non-competing types
**Closest threat:** Competing-risks Brier/log score (pec, riskRegression R packages) + Bouaziz (2024) single-type recurrent Brier

**Publication probability:** 40–50% at *Biometrics* or *Statistics in Medicine* as methods note
**Target journal:** *Biometrics* (if theory is deep); *Statistics in Medicine* (as evaluation methods paper)

**Critical reviewer objections:**

1. "Strict propriety is inherited from standard multiclass scores — this is bookkeeping, not new theory" — must show IPCW weighting with repeated landmark risk sets introduces genuine complications (not just relabeling)
2. Must demonstrate realistic scenarios where proposed scores give different model rankings than ad hoc metrics
3. Paper cannot float standalone — must evaluate at least one of the new methods (New Idea A or Idea 1)

**Minimum viable improvements:**

- Formal strict propriety proof under repeated landmark IPCW weighting
- Derive consistent estimator with bias correction for finite samples
- Decomposition theorem: BS_joint = BS_occurrence + BS_type|occurrence
- Simulation showing score rankings differ from single-type Brier in multi-type settings
- Attach to New Idea A paper as companion evaluation section

---

### 🥉 New Idea B: Coherent Joint Simplex Learner — EMPIRICAL COMPLEMENT (Needs Upgrade)

**PhD contribution type:** Methodological / Empirical

**Hypothesis:** Modeling the full (K+1)-category post-landmark outcome (no event, type 1…K) directly with IPCW multinomial boosted trees outperforms separate survival + type models by enforcing distributional coherence across event types.

**Core method:**

- IPCW multinomial deviance for p_0(H_s)…p_K(H_s) with boosted trees / multinomial forest
- Recover: (A) event-free survival = p_0; (B) conditional type = p_k/(1-p_0)
- Optional: cross-horizon monotonicity constraint in w; landmark-specific vs. pooled fitting
- Subject-level repeated-landmark dependence handled via cluster-robust standard errors

**Novelty verdict:** CONFIRMED but thin without structural upgrade
**Critical issue:** Without extra contribution (coherence theory, monotonicity penalty, or rare-class structure), reviewers will call this "IPCW multinomial classification with relabeled outcome"

**Recommendation:** Do NOT pursue as standalone paper. Fold into New Idea A as the empirical prediction framework — use New Idea A theory for estimation, Idea B's direct simplex loss for ML learner fitting.

**Publication probability (standalone):** 15–25% at *Statistics in Medicine*
**If folded into New Idea A:** Provides the empirical prediction component (ML fitting) while New Idea A provides the theoretical estimation component.

---

## Prior Ideas (From March 2026 Run) — Unchanged

### 🏆 Idea 7: Doubly Robust Pseudo-Observations for Missing Event Type Labels — HIGHEST PUB PROBABILITY

*Publication probability: 65% at Biostatistics*

[Full description in IDEA_REPORT_2026-03-16_recurrent-events-ml.md]

Core: Influence function derivation for DR pseudo-observation estimator under MAR event type labels. 4-scenario DR stress test. Cross-fitting for ML nuisance estimators. Direct deepening of Missing Types/ project.

---

### 🥈 Idea 1: Multi-Type Landmark Random Forest (MTLRF) — ML FOUNDATION

*Publication probability: 40% at Biostatistics/StatMed*

[Full description in IDEA_REPORT_2026-03-16_recurrent-events-ml.md]

Core: Matrix-trace impurity criterion for K-vector pseudo-observation targets. Cross-type VIMP. OOB uncertainty. 37-scenario simulation.

---

### Idea 3: Type-Specific Calibration Metrics — NEEDS REFRAMING

*Publication probability: 40-50% at Statistics in Medicine (with bias-correction angle)*

[Full description in IDEA_REPORT_2026-03-16_recurrent-events-ml.md]

---

## Revised Dissertation Architecture (Updated)

Based on two `/idea-discovery` runs, the natural 4-paper dissertation structure is:

**Paper 1 (Lead — Missing Types): Idea 7 — DR Pseudo-Observations for Missing Event Type Labels**

- Target: *Biostatistics* or *JASA T&M*
- Unique strength: Formal guarantees; 65% pub probability; builds on existing Missing Types/ infrastructure
- Timeline: Theory → simulation (existing infrastructure)

**Paper 2 (Core — Event Type Prediction): New Idea A — Orthogonal Landmark Mark Classifier**

- Target: *Biometrics*
- Unique strength: First method for P(next event type = k | recurrent history, censoring) — entirely empty gap
- Timeline: EIF derivation → simulation → real data (ALLHAT or cardiovascular)
- Includes: New Idea B (simplex learner) as empirical framework; New Idea C evaluation metrics

**Paper 3 (ML Foundation — Survival Prediction): Idea 1 — MTLRF**

- Target: *Biostatistics* or *Statistics in Medicine*
- Unique strength: First ML prediction for K non-competing recurrent types (survival side)
- Timeline: After Papers 1–2 establish infrastructure

**Paper 4 (Evaluation): New Idea C + Idea 3 combined**

- Target: *Statistics in Medicine*
- Unique strength: Proper scoring for (occurrence, type) jointly + bias-corrected calibration
- Timeline: After Papers 2–3 methods are implemented (requires concrete methods to evaluate)

---

## All Evaluated Ideas: Quick Reference


| ID      | Title                               | Type              | Pub Prob          | Target                 | Status                   |
| ------- | ----------------------------------- | ----------------- | ----------------- | ---------------------- | ------------------------ |
| Idea 7  | DR pseudo-obs for missing types     | Method/Theory     | 65%               | Biostatistics          | RECOMMENDED LEAD         |
| New A   | Orthogonal Landmark Mark Classifier | Method/Theory     | 45–55%            | Biometrics             | RECOMMENDED NEW          |
| New C   | Proper Scoring Rules                | Theory/Diagnostic | 40–50%            | Biometrics/StatMed     | RECOMMENDED COMPANION    |
| Idea 1  | MTLRF                               | Method            | 40%               | Biostatistics/StatMed  | RECOMMENDED ML           |
| Idea 3  | Calibration metrics                 | Theory/Diagnostic | 40–50%            | Statistics in Medicine | NEEDS REFRAMING          |
| New B   | Coherent Simplex Learner            | Method/Empirical  | 15–25% standalone | StatMed                | FOLD INTO NEW A          |
| Idea 8  | SREF                                | Method            | —                 | —                      | SECTION IN IDEA 1        |
| Idea 4  | Super-Learner                       | Method            | —                 | —                      | SECTION IN IDEA 1        |
| Idea 10 | Conformal intervals                 | Method            | —                 | StatMed short comm     | APPENDIX                 |
| Idea 2  | Cross-type VIMP                     | Diagnostic        | —                 | —                      | SECTION IN IDEA 1        |
| Idea 5  | Gap-Time Multi-Type Forest          | Method            | —                 | —                      | ELIMINATED (incremental) |
| Idea 9  | Clinical Benchmark                  | Applied           | —                 | —                      | ELIMINATED (low novelty) |


---

## Monitoring Alerts

- **Loe-Murray-Wu group (arXiv):** Monitor for follow-up to arXiv:2510.23764 — may reach K-type non-competing setting within 6–12 months
- **arXiv:2602.00194 (Alberge et al.):** Read full PDF to confirm scope doesn't cover recurrent events calibration
- **arXiv:2512.07973 (Xu et al.):** Bayesian multi-type — primary statistical baseline for Papers 2 and 3
- **multiRec (Ghosh et al. 2023):** Statistical baseline; check whether paper discusses any prediction (vs estimation only)

---

## Next Steps

### Immediate (Paper 2 — New Idea A)

- Derive EIF for P(Y_{s,w} = k | H_s) under right censoring + death — start from Overgaard et al. 2017 influence function framework, extend to conditional mark
- Prove double robustness for conditional mark estimand (novel relative to existing DR work which targets occurrence only)
- Implement AIPW estimator in R: 5-fold cross-fitting, stabilized weights
- Design 4-scenario DR simulation using `rate_cox_data_gen_complex()` with multi-type output
- Pair with New Idea C evaluation (joint Brier score) to demonstrate Type prediction value

### Parallel (Paper 1 — Idea 7)

- Begin influence function derivation — Overgaard 2017 → K-type extension under MAR
- 4-scenario DR stress test simulation (Missing Types/ infrastructure)

### Evaluation foundation (New Idea C)

- Derive joint (K+1) Brier score and prove strict propriety
- Implement in R as companion to Papers 2–3

### Administration

- `/run-experiment` to deploy expanded simulations on SLURM once estimators are coded
- `/auto-review-loop` once Paper 2 is drafted
- Read arXiv:2602.00194 (Alberge) full PDF to confirm calibration novelty

