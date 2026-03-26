# Experiment Plan: Orthogonal Landmark Mark Classifier (OLMC)

**Method:** Cross-fitted doubly robust estimator for μ_k(h) = P(T_s^N ≤ w, J_s = k, T_s^N < T_s^D | H_s = h)
**Target:** *Biometrics* submission
**Date:** 2026-03-18
**Infrastructure:** R + SLURM (UNC Longleaf), `rate_cox_data_gen_complex()` extension

---

## Common Experimental Design

**Landmark scheme:** Quarterly landmarks at {6, 12, 18, 24, 30, 36} months; prediction window w = 180 days (sensitivity: w = 90 days in Block 5)

**Evaluation history strata (4 prespecified):**
- H0: No prior events (baseline prediction)
- H1: One recent type-1 event (< 6 months ago)
- H2: Mixed history, ≥ 2 prior events of different types
- H3: High-burden history, ≥ 3 recent events

**Monte Carlo replication sizes:**
- Pilot runs: 200 reps (early signal check)
- Main paper blocks: 1000 reps
- Appendix/sensitivity: 500 reps

**Default DGM:**
- K = 3 event types, shared log-normal frailty (σ² = 0.5, sensitivity at σ² = 1.0)
- Recurrent hazard depends on: event count, last event type, gap time, baseline covariates (5 variables)
- Death cumulative incidence ~20–30% by 3 years
- Censoring: 15–35%, history-dependent

**Estimators (all blocks unless specified):**
- DR: Proposed doubly-robust μ-then-normalize (cross-fit by subject, 5-fold)
- OR-only: Outcome regression only (no censoring adjustment)
- IPCW: Inverse probability of censoring weighting (no outcome regression)
- Observed-case: Complete window analysis (death treated as censoring)
- CR-baseline: Competing-risks first-event model applied after recurrence (Block 4 only)

---

## Block 1: EIF / Oracle Sanity Check

**Scientific question:** Is the implementation correct, and does the EIF variance match the Monte Carlo variance?

**DGM:**
- K = 2 (simpler for verification)
- n ∈ {500, 1000, 2000}
- Censoring: 15%, independent (simplest case)
- Death: 15–20%, moderate frailty σ² = 0.3
- Simple parametric hazard forms so true μ_k(h) is available by numerical integration

**Estimators:** DR-oracle (true nuisances plugged in), DR-correct-parametric, OR-only-correct, IPCW-only-correct

**Primary metrics:**
- Monte Carlo bias for μ_k(h) at H0–H3
- Empirical variance vs EIF-based variance ratio
- 95% CI coverage at n = 500, 1000, 2000

**Expected finding:** DR-oracle is essentially unbiased; EIF-based variance estimates match Monte Carlo; coverage approaches 95% as n grows.

**Kill criterion:** Persistent bias or coverage failure for DR-oracle at n ≥ 1000 → coding or derivation error; stop and debug.

**Run first:** YES — this is the implementation verification gate.
**Estimated SLURM:** ~6–8 node-hours (3 n sizes × 200 reps pilot first, then 1000 reps)
**Output:** Table of bias/variance/coverage by n — supplement

---

## Block 2: Double-Robustness Matrix

**Scientific question:** Does the estimator stay consistent under one-correct nuisance?

**DGM:**
- K = 3, n = 1500
- Censoring: 25–30%, driven by observed history (informative)
- Death: 20–25%, correlated with recurrent event risk (shared frailty σ² = 0.5)
- Recurrent hazard: strong dependence on count, last type, gap time

**DR conditions (2 × 2 matrix):**
| | G correct | G wrong (misspecified) |
|---|---|---|
| OR correct | DR-both-correct | DR-G-wrong |
| OR wrong | DR-OR-wrong | DR-both-wrong |

**Primary metrics:**
- Bias and RMSE for μ_k(h) across H0–H3
- 95% CI coverage

**Expected finding:** DR stays near-unbiased in both one-correct conditions; both-wrong condition shows bias similar to single-robust methods; OR-only fails when OR wrong; IPCW-only fails when G wrong.

**Kill criterion:** No separation between one-correct and both-wrong conditions; or positivity violation collapsing the estimator.

**Run second** (after Block 1 passes pilot).
**Estimated SLURM:** ~8–10 node-hours (4 conditions × n = 1500 × 1000 reps)
**Output:** Main paper Table 1 — 2×2 bias/coverage matrix

---

## Block 3: Naive Bias Demonstration

**Scientific question:** Are observed-case and IPCW shortcuts materially biased in realistic settings?

**DGM:**
- K = 3, n = 1500
- Censoring: 30–35%, strongly driven by deteriorating event history (dropout informative)
- Death: 25–30%, strongly linked to event type 1 risk (confounding)
- Frailty σ² = 0.5–1.0

**Estimators:** DR, OR-only, IPCW-only, observed-case, death-as-censoring naive

**Primary metrics:**
- Absolute bias for μ_k(h) across H0–H3
- Type-specific calibration error for π_k(h)
- Clinical magnitude: express bias in terms of clinically meaningful units

**Expected finding:** Observed-case and death-as-censoring approaches show ≥ 10% absolute bias for at least one history stratum; DR materially closer to truth.

**Kill criterion:** Naive methods nearly unbiased in ALL plausible scenarios → practical motivation for the paper is weak.

**Run third.**
**Estimated SLURM:** ~6–8 node-hours
**Output:** Main paper Figure 1 or Table 2 — bias comparison across history strata

---

## Block 4: Practical Distinction From Competing Risks

**Scientific question:** Do first-event competing-risks methods fail after recurrence?

**DGM:**
- K = 3, n = 2000
- Strong recurrent dependence: next event type strongly depends on last event type and event count
- Death 20–25%, censoring 20–25%, frailty σ² = 0.5

**Estimators:**
- Proposed DR
- Fine-Gray first-event model (applied to ALL landmark rows, including post-recurrence)
- Cause-specific Cox first-event model (same misapplication)
- "Restart but exclude recurrent" — only use baseline prediction from H0

**Primary metrics:**
- Bias and calibration of μ_k(h) and π_k(h) specifically among subjects with ≥ 1 prior event (H1, H2, H3 strata)
- Note: CR models may produce undefined predictions for H1+ strata (event already occurred)

**Expected finding:** CR models are undefined or severely miscalibrated for H1+ strata; proposed method remains calibrated. Exclusion-based baseline model misses the history dependence.

**Kill criterion:** < 25% of evaluable landmark rows have prior events; or prior history has negligible effect on next type (trivial case).

**Run fourth.**
**Estimated SLURM:** ~5–7 node-hours
**Output:** Main paper Figure 2 — calibration plots by history stratum, CR vs OLMC

---

## Block 5: Rare-Event Stability / Reporting Threshold

**Scientific question:** When is π_k(h) stable enough to report?

**DGM:**
- K = 3, n = 2000
- Vary w to make q(h) ≈ {0.05, 0.10, 0.15, 0.20}
- Censoring 20–25%, death 20%
- Sensitivity: w = 90 days vs w = 180 days

**Estimators:** DR μ-then-normalize (main), DR with truncation at various thresholds, direct conditional estimator (for comparison)

**Primary metrics:**
- RMSE and CI coverage for π_k(h) as function of true q(h)
- Threshold identification: minimum q(h) where coverage is within 5% of nominal

**Expected finding:** μ-first estimation stable down to q(h) ≈ 0.10; direct conditional estimation degrades earlier (~0.15).

**Kill criterion:** Instability persists even at q(h) ≥ 0.15 → conditional type prediction is too fragile for main paper claim.

**Run fifth.**
**Estimated SLURM:** ~6–8 node-hours
**Output:** Supplement Figure: stability curve; recommendation for q(h) threshold in practice

---

## Block 6: Clinical-Realism / Flexible Nuisance (Appendix Main)

**Scientific question:** Does cross-fitted ML for nuisance models help in high-dimensional realistic settings?

**DGM:**
- K = 3, n = 2000–3000
- 15–25 baseline/history summary features
- Nonlinear interactions: count × gap time × covariate
- Frailty σ² = 1.0, censoring 25%, death 25%

**Estimators:**
- DR-ML: 5-fold cross-fit with SuperLearner library (GAM + xgboost + ranger for nuisance)
- DR-parametric: 5-fold cross-fit with Cox + GLM
- OR-ML, IPCW-ML
- Comparison: same parametric DR as in Blocks 2–3

**Primary metrics:**
- Integrated bias for μ_k(h) over H0–H3
- Multiclass log loss for π_k(h)
- Robustness under one-correct condition with flexible nuisance

**Expected finding:** DR-ML ≥ DR-parametric in high-dim scenarios; robustness preserved.

**Kill criterion:** Flexible DR offers no gain, or compute becomes impractical.

**Run last** (appendix block; can defer to dissertation chapter after Biometrics submission).
**Estimated SLURM:** ~10–14 node-hours
**Output:** Appendix Table — flexible vs parametric nuisance comparison

---

## Publication Decision Gate

**Biometrics submission requires ALL of the following:**

| Block | Gate criterion |
|---|---|
| Block 1 | DR-oracle: negligible bias, EIF variance ≈ MC variance, coverage ≥ 93% at n ≥ 1000 |
| Block 2 | DR with one correct nuisance: clearly better than single-robust, near-unbiased across H0–H3 |
| Block 3 | At least one realistic scenario with ≥ 10% absolute bias for naive methods, DR materially better |
| Block 4 | CR methods undefined or miscalibrated for ≥ 1 post-recurrence stratum |
| Block 5 | π_k(h) stable and near-nominal coverage for q(h) ≥ 0.10 |

**Minimum publishable subset:** Blocks 1–5. Block 6 is valuable but can appear as dissertation appendix if time-constrained.

---

## Run Order

1. **Block 1 pilot (200 reps, K=2, n=1000)** — verify implementation
2. **Block 2 pilot (200 reps)** — verify DR mechanism
3. **Block 3 + Block 4 (1000 reps)** — parallel, key novelty claims
4. **Block 1 full (1000 reps) + Block 2 full (1000 reps)** — parallel
5. **Block 5 (1000 reps)** — stability threshold
6. **Block 6 (500 reps)** — flexible nuisance (after Blocks 1–5 pass)

---

## Total Compute Budget

| Block | Node-hours | Priority |
|---|---|---|
| Block 1 (pilot + full) | 6–8 | REQUIRED |
| Block 2 (pilot + full) | 8–10 | REQUIRED |
| Block 3 (full) | 6–8 | REQUIRED |
| Block 4 (full) | 5–7 | REQUIRED |
| Block 5 (full) | 6–8 | REQUIRED |
| Block 6 (appendix) | 10–14 | OPTIONAL |
| **Total** | **41–55** | — |
| Overhead (30%) | ~12–16 | — |
| **Grand total** | **~55–70 node-hours** | ~1–2 cluster days |
