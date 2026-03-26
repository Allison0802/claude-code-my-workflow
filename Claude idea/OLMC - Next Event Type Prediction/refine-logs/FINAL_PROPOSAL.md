# Final Proposal: Orthogonal Landmark Mark Classifier (OLMC)

**Status:** APPROVED (after Round 1 critical revision)
**Date:** 2026-03-18
**Target venue:** *Biometrics* (primary), *Biostatistics* (fallback)

---

## Problem Anchor (Frozen)

For K non-competing recurrent event types, no method exists to predict the next-event type distribution from arbitrary post-history landmark states under right censoring and an absorbing terminal event.

Competing risks ML (Fine-Gray, DeepHit, RSF-CR) handles only the first absorbing failure — the subject exits after one event. In real clinical settings, subjects follow trajectories like (MI → stroke → MI → hospitalization → ...) and clinicians need to predict the next event type from any state the subject has reached, updating after each recurrence.

**This gap is completely empty in both the ML and statistics literature as of March 2026.**

---

## Method Thesis (One Sentence)

We develop a cross-fitted doubly robust estimator for the vector of post-landmark next-transition probabilities μ_k(h) = P(T_s^N ≤ w, J_s = k, T_s^N < T_s^D | H_s = h) and derive the conditional event-type classifier π_k(h) = μ_k(h) / Σ_l μ_l(h) as a stable normalization, with validity under history-dependent censoring and competing death.

---

## Dominant Contribution (One Thing)

A semiparametrically justified estimator for **next-transition type prediction after arbitrary recurrent histories**, where subjects re-enter prediction after prior events — conceptually impossible with any first-event absorbing-failure framework.

---

## Formal Setup

**Process:** Subject i has recurrent nonterminal events of types k = 1,…,K and an absorbing terminal event (death D). Events can repeat: subject can have type 1, then type 2, then type 1 again.

**Landmark state:** At landmark time s, the history H_s captures: prior event count by type, time since last event of each type, gap sequence, baseline covariates.

**Post-landmark outcomes (for window [s, s+w]):**
- T_s^N = time to next nonterminal event (of any type) after s
- J_s ∈ {1,…,K} = type of that event
- T_s^D = time to death after s
- C_s = time to censoring after s

**Primary estimand:** The K-vector of next-transition probabilities
  μ_k(h) = P(T_s^N ≤ w, J_s = k, T_s^N < T_s^D | H_s = h), k = 1,…,K

**Secondary estimand:** Conditional type classifier
  π_k(h) = μ_k(h) / Σ_l μ_l(h) = P(J_s = k | T_s^N ≤ w, T_s^N < T_s^D, H_s = h)

**Note:** μ_k(h) is the primary target for theory (avoids 1/q(h) instability); π_k(h) is derived by normalization and reported where q(h) = Σ_l μ_l(h) ≥ 0.10.

---

## Identification Assumptions

1. **Conditional independent censoring:** C_s ⊥ (T_s^N, J_s, T_s^D) | H_s
2. **Positivity for censoring:** G_C(u | H_s) = P(C_s > u | H_s) > ε for all u ∈ [0, w]
3. **Positivity for occurrence (secondary):** q(H_s) > ε on reported support
4. **No interference** across subjects at landmark

**Critical note:** Death is NOT treated as missing data. It is an absorbing competing transition in the post-landmark process. Only censoring coarsens the data.

---

## Estimation Framework

### Efficient Influence Function (EIF)

For the estimand μ_k(h), the EIF at history state h takes the counting-process form:

φ_{μ_k,h}(O) = a_h(H_s) [
  M_k(H_s) - μ_k(h)
  + ∫_0^w G_C(u- | H_s)^{-1} { dN_k(u) - Y(u) dΛ_k(u | H_s) }
]

where:
- a_h(H_s) localizes at history state h
- M_k(H_s) = P(T_s^N ≤ w, J_s = k, T_s^N < T_s^D | H_s) — outcome regression
- G_C = censoring survival function
- N_k(u) = I(T_s^N ≤ u, J_s = k, T_s^N < T_s^D) — counting process
- Y(u) = I(T_s^N ∧ T_s^D ∧ C_s > u) — at-risk indicator (includes death in at-risk removal)
- Λ_k(u | H_s) = cumulative hazard for type-k next-event (before death or censoring)

Then:
- φ_{q,h} = Σ_k φ_{μ_k,h} (EIF for occurrence probability)
- φ_{π_k,h} = φ_{μ_k,h}/q(h) - μ_k(h) φ_{q,h}/q(h)² (EIF for conditional type, by ratio rule)

### Double Robustness

The estimator is consistent if EITHER:
1. The censoring model G_C(u | H_s) is correctly specified, OR
2. The outcome regression M_k(H_s) is correctly specified

(Standard Neyman orthogonality result for counting-process nuisance pair.)

### Nuisance Models Required

| Nuisance | Form | Default ML estimator |
|---|---|---|
| G_C(u | H_s) | Censoring survival | Cox PH or Kaplan-Meier stratified on H_s |
| M_k(H_s) | Direct regression for μ_k | Boosted trees, random forest, GAM |
| Λ_k(u | H_s) | Type-k hazard (optional, for EIF construction) | Cause-specific Cox |
| λ_D(u | H_s) | Death hazard (required for at-risk indicator) | Separate Cox |

### Cross-Fitting Protocol

- Split by **subject** (not by landmark row) into 5 folds
- Estimate nuisance functions on out-of-fold subjects
- Aggregate influence functions at the subject level before computing variance
- Subject-clustered variance estimation (CR sandwich or subject-level mean influence)

### Stability for π_k(h)

- Estimate μ_k(h) first, then normalize
- This avoids direct 1/q(H_s) in the score (prevents blow-up)
- Report π_k(h) only where estimated q(h) ≥ 0.10 on the support of H_s
- Provide sensitivity analysis under q(h) ≥ 0.05 and ≥ 0.15 thresholds

---

## Three Key Claims

1. **Identification and EIF:** μ_k(h) is identified under conditional independent censoring with death as absorbing; the EIF has the counting-process form above and is nontrivial because (a) it involves the landmark-state-conditional at-risk indicator including death, (b) subjects contribute multiple landmark rows requiring subject-level aggregation, and (c) normalization to π_k introduces a ratio term.

2. **Double robustness:** The estimator is consistent under one-correct-nuisance in at least two clinical scenarios where observed-case and naive IPCW approaches show material bias (specifically: history-dependent censoring and informative death correlated with event type risk).

3. **Practical distinction from competing risks:** First-event competing-risks methods (Fine-Gray, cause-specific Cox, DeepHit) fail to produce valid predictions after recurrence because they do not re-index on evolving history H_s; the proposed estimator remains calibrated across post-event landmark states (shown via direct comparison in simulation).

---

## Complexity Intentionally Rejected

- No joint frailty full-likelihood model (too complex; DR approach achieves robustness without shared frailty estimation)
- No death-as-missingness formulation (incorrect — death is an absorbing competing state)
- No triply-robust hazard layer (adds implementation complexity without core contribution)
- No joint prediction of time + type (type prediction is the contribution; time handled separately by Loe et al. 2025 framework)
- No inference treating landmark rows as iid (incorrect — must cluster by subject)

---

## Connection to Existing Dissertation Infrastructure

- `rate_cox_data_gen_complex()`: extend to output J_s (event type) per event alongside existing outputs
- Landmark transformation: already built; extend to track J_s per landmark window
- Pseudo-observation machinery: related but distinct — OLMC uses direct DR estimation, not pseudo-observation regression
- Evaluation: pair with New Idea C (proper scoring rules paper) for calibration and log score metrics
