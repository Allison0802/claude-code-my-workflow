# Stress-Test Briefing: Random Forest Calibration under Class Imbalance: A State-of-the-Art Approach Using SMOTE Preprocessing

**Authors:** Synthetic Authors X., Synthetic Authors Y., Synthetic Authors Z.
**Year:** 2026
**Source:** master_supporting_docs/supporting_papers/test_papers/testpaper_b_rf_calibration.pdf
**Stress-test date:** 2026-04-24
**Detected paper type:** predictive-ML
**Depth:** 1
**Weights:** heavy/light/light/medium/heavy/medium/heavy/heavy/heavy
**Reviewer model:** opus
**Author-surrogate model:** sonnet

---

## TL;DR verdict

The paper proposes SMOTE-before-RF as a "state-of-the-art" calibration technique for imbalanced classification. The thematic-notebook check surfaces a decisive positioning failure: **the core thesis directly contradicts established analytical results** (Dal Pozzolo 2015, Wallace-Dahabreh 2014) proving that resampling *decalibrates* posteriors, and the canonical RF calibration reference (Niculescu-Mizil & Caruana 2005) is uncited. Compounding this, SMOTE is applied to the combined train+validation pool before model fitting — a textbook data-leakage pattern that inflates every reported metric. Reported ECE is computed on the SMOTE-balanced manifold rather than the source-population distribution (0.17% prevalence). No hyperparameter sensitivity, no competitive baselines, no post-hoc calibration control, no confidence intervals, no seed, no code. **Recommendation: skip** — the headline contribution is a known anti-pattern with no reproducible evidence base.

---

## Top 5 killer questions

1. **[Lens 7/positioning, critical]** The core claim (SMOTE-before-RF improves calibration) directly contradicts Dal Pozzolo et al. (2015) and Wallace-Dahabreh (2014), both uncited, who analytically prove resampling decalibrates probabilities; how is this a contribution rather than a known anti-pattern?
   - *Why it matters:* the headline claim contradicts established theory.
2. **[Lens 0/data, critical]** SMOTE is applied to combined train+validation data before model fitting — every validation point's synthetic neighbors leak into training. On what basis are the reported AUROC/ECE not upward-biased?
   - *Why it matters:* reported metrics are not meaningful if the validation fold was encoded into training via SMOTE interpolation.
3. **[Lens 1/estimand, critical]** ECE<0.03 targets the SMOTE-balanced distribution (~50/50), not the source population P(Y=1)=0.0017; calibration is not invariant to prevalence shift. Where is the prevalence-corrected ECE?
   - *Why it matters:* downstream clinical/financial deployment at true prevalence cannot rely on the reported calibration.
4. **[Lens 8/reproducibility, critical]** Which single numerical result could an independent statistician reproduce — no DUA, no seed, no code, no SMOTE hyperparameters, no fold-leakage audit?
   - *Why it matters:* zero reproducibility; the paper is unauditable.
5. **[Lens 3/methodology, major]** Default RF (500 trees, no max_depth, leaf=1) on imbalanced data is a textbook miscalibration regime independent of prevalence. Where is the factorial hyperparameter ablation to distinguish "SMOTE fixes imbalance" from "SMOTE masks untuned-forest overfitting"?
   - *Why it matters:* causal attribution of the calibration signal to SMOTE vs hyperparameter-regularization-by-proxy is unidentified.

---

## External novelty-check

Skipped (`user_flag`: `--skip-novelty` passed; synthetic test paper). Prior-art triangulation in Lens 7 via the *Machine Learning Fundamentals* thematic notebook returned a decisive hit: mainstream ML literature explicitly does NOT recommend SMOTE-before-RF for calibration — the opposite. SMOTE "actively destroys the reliability of the probabilistic outputs".

---

## Severity summary

| Lens | Name | Weight | Depth | Severity | Judgment |
|------|------|--------|-------|----------|----------|
| 0 | data | heavy | 1 | critical | conceded |
| 1 | estimand | light | 1 | critical | conceded |
| 2 | identification | light | 1 | skipped | — |
| 3 | methodology | medium | 1 | major | conceded |
| 4 | overclaims | heavy | 1 | major | conceded |
| 5 | alternatives | medium | 1 | major | conceded |
| 6 | generalizability | heavy | 1 | major | conceded |
| 7 | positioning | heavy | 1 | critical | conceded |
| 8 | reproducibility | heavy | 1 | critical | conceded |

**Tally:** critical=4 · major=4 · minor=0 · clean=0 · skipped=1

---

## Per-lens findings

### Lens 0 — data (**critical**, conceded)

- **Finding:** SMOTE is applied to the combined train+validation pool BEFORE model fitting. Synthetic minority samples encode validation-fold feature vectors as interpolation anchors. Every reported metric is upward-biased.
- **Author's best defense:** "the paper does not address this" — no mention, no disclaimer, no mitigation.
- **Why it didn't hold:** textbook leakage; no acknowledgment.

### Lens 1 — estimand (**critical**, conceded)

- **Finding:** ECE<0.03 targets calibration on SMOTE-balanced (~50/50) manifold, not P(Y=1|X) on source population (0.17% prevalence). Calibration is not invariant to prevalence shift.
- **Author's best defense:** "the paper does not address this" — no prevalence-corrected ECE, no recalibration.
- **Why it didn't hold:** reported quantity answers a different question than paper claims.

### Lens 2 — identification (**skipped**)

- **Finding:** Skipped per predictive-ML weight matrix — no causal estimand, identification-as-causal-inference does not apply.
- **Author's best defense:** n/a.

### Lens 3 — methodology (**major**, conceded)

- **Finding:** Default RF (n_estimators=500, max_depth=None, min_samples_leaf=1) on imbalanced data is a textbook recipe for sigmoid-shaped miscalibration independent of prevalence; no factorial hyperparameter sensitivity.
- **Author's best defense:** "the paper does not address this" — no ablation.
- **Why it didn't hold:** "SMOTE fixes imbalance" confounded with "SMOTE masks untuned-forest overfitting".

### Lens 4 — overclaims (**major**, conceded)

- **Finding:** "State-of-the-art" with only plain-RF baseline — no Platt, no isotonic, no class-weighted RF, no focal, no calibration wrappers. No CIs, no bootstrap, no DeLong.
- **Author's best defense:** "the paper does not address this".
- **Why it didn't hold:** 0.94 vs 0.92 AUROC indistinguishable from sampling noise without uncertainty quantification.

### Lens 5 — alternatives (**major**, conceded)

- **Finding:** Gains confound (a) training-size increase from oversampling, (b) merged train+val pool, (c) actual calibration. No post-hoc Platt/isotonic on plain RF to isolate (c).
- **Author's best defense:** "the paper does not address this".
- **Why it didn't hold:** standard calibration baseline missing; three-way confound unidentified.

### Lens 6 — generalizability (**major**, conceded)

- **Finding:** 2 tabular datasets, 1 classifier, 1 resampler, iid splits — yet "default preprocessing step in any imbalanced classification task" recommended. Five unsupported extrapolation axes.
- **Author's best defense:** "the paper does not address this".
- **Why it didn't hold:** universal recommendation not supported.

### Lens 7 — positioning (**critical**, conceded)

- **Finding:** Paper claims "state-of-the-art calibration" yet cites ZERO calibration literature — Niculescu-Mizil & Caruana (2005), Guo et al. (2017), Dal Pozzolo et al. (2015), and Wallace-Dahabreh (2014) all uncited. Dal Pozzolo and Wallace-Dahabreh analytically PROVE resampling decalibrates — the opposite of this paper's thesis.
- **Author's best defense:** "the paper does not address this. References list contains only Chawla (2002) and Breiman (2001)."
- **Why it didn't hold:** core claim is a known anti-pattern; zero calibration literature engaged.

### Lens 8 — reproducibility (**critical**, conceded)

- **Finding:** Private dataset (no DUA/availability), no seed, no code repo, no SMOTE k_neighbors, no random_state, no fold-leakage confirmation.
- **Author's best defense:** "the paper does not address this".
- **Why it didn't hold:** total reproducibility failure.

---

## Skipped lenses

- **Lens 2 (identification):** predictive-ML weight matrix sets identification to "light" at depth 1; paper makes no causal claim.

---

## Relevance to user's sub-projects

### Missing Types (`Missing Types/`) — **No (synthetic test paper)**

- **Applies:** No.
- **Data match:** *Poor.* Missing Types targets missing event-type labels for recurrent competing risks; this paper is binary classification under class imbalance.
- **Warning:** If probability calibration ever becomes relevant in Missing Types evaluation, cite Niculescu-Mizil & Caruana (2005), Guo et al. (2017), and Dal Pozzolo et al. (2015) — not this paper.
- **Missing comparator:** Not a candidate baseline.

### Comparisons (`comparisons/`) — **No (synthetic test paper)**

- **Applies:** No.
- **Data match:** *Poor.*
- **Warning:** Same as above.
- **Missing comparator:** Not a candidate baseline.

---

## Recommendation

**skip**

**Rationale:** Severity tally across 8 active lenses (lens 2 skipped per predictive-ML weight matrix): critical=4 (lenses 0/1/7/8), major=4 (lenses 3/4/5/6), minor=0, clean=0. Mechanical rule: critical ≥ 1 → **skip**. The paper fails on every dimension a calibration paper must pass: leaked data, wrong-distribution estimand, known anti-pattern thesis, zero reproducibility. Skip.

---

## Disposable notebook

- **Name:** stress-test-testpaper_b_rf_2026-04-24
- **ID:** `0ab87c96-b4c7-47be-89a6-919b2ab52f4a`
- **URL:** https://notebooklm.google.com/notebook/0ab87c96-b4c7-47be-89a6-919b2ab52f4a
- **Disposition:** deleted in Phase 6 cleanup

---

## Prior stress-tests of this paper

None on record. This is the first stress-test for `testpaper_b_rf_*`.
