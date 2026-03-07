# Manuscript Review: RF pseudo.tex
**Date:** 2026-03-01
**Manuscript:** `comparisons/RF pseudo.tex`
**Reviewers:** domain-reviewer agent (5 lenses) + ML paper writing framework

---

## Part I: Summary Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| **Contribution clarity** | Good | Multi-type extension clearly motivated |
| **Methods description** | Minor gap | Beta scaling present; history comparison informal but present |
| **Estimand clarity** | Resolved | KM correct for multi-type recurrent; "competing risks" language fixed |
| **Simulation design** | Resolved | DGP correct; terminology fixed throughout |
| **Results presentation** | Figure–text inconsistency | rho=0.9 figure vs. rho=0.3 text |
| **Discussion balance** | Speculation without evidence | MERF identification claim unsupported |

**Overall assessment: MAJOR ISSUES — not ready for submission without revisions**

**Blocking issues (prevent submission):** 2 *(Major Comments 1, 2, 3 retracted/resolved)*
**Non-blocking issues (should fix):** 13

---

## Part II: Fidelity Check — Manuscript vs. Code

| Aspect | What Code Does | What Manuscript Says | Gap? |
|--------|---------------|----------------------|------|
| Scenarios | 37 (3α × 3c × 2ρ × 2cens) | "37 simulation scenarios" | ✓ Match |
| Simulations/scenario | 500 | "500 datasets per scenario" | ✓ Match |
| Methods compared | 12 (with+without history × 6 base methods) | 4 strategies + Cox baseline | **Gap: with/without history not a formal factor** |
| Beta scaling | `complexity_scale` = 1.0/0.5/0.2 | Not described anywhere | **Gap: critical for reproducibility** |
| ρ-based coefficient scaling | `beta × 0.9` when ρ=0.9 | Not described | **Gap** |
| Baseline rate adjustment | r01=0.20→0.50 at complexity=2 | Not described | **Gap** |
| History feature variable names | `H1/H2/H3` + `time_since_last_type1/2` (dual sets) | Single set implied | **Gap: two history sets used simultaneously** |
| Pseudo-observation function used | `generate_pseudoEst` (overall KM) | Type-specific KM claimed | **Gap: code uses wrong function** |
| High-dim scenarios | Separate track exists | Not in manuscript | Abandoned by choice — OK |
| Event-based C-index | Computed but not reported | Absent from results | Abandoned by choice — OK |
| Figure panels | 2×2 within each figure | 2×2 stated | ✓ Match |
| Figure rho | `rho0.9` in Figure 1 filenames | Text focuses on ρ=0.3 | **Gap: inconsistency** |
| Train-test split | 80/20 subject-level | "80%/20% at subject level" | ✓ Match |
| MERF test prediction | Forest only (no random effects) | Equation shows b_i + g(Z) | **Gap: prediction formula misleading** |

---

## Part III: Biostatistics Reviewer Comments

*In the style of Biostatistics, Statistics in Medicine, or Lifetime Data Analysis.*

---

### MAJOR COMMENTS (must address before acceptance)

---

~~**Major Comment 1: Estimand confusion between KM and CIF pseudo-observations**~~ — **RETRACTED**

*This critique assumed a competing-risks setting where events are mutually exclusive. The paper is a multi-type recurrent event setting: both event types can recur in the same subject. In this setting, treating other event types as censoring within each gap and applying the type-specific KM is the correct approach — not the CIF. The KM-based pseudo-observations are methodologically appropriate.*

---

~~**Major Comment 2: Simulation DGP generates independent event processes**~~ — **RETRACTED (DGP correct); terminology RESOLVED in manuscript**

*The DGP correctly generates independent type-1 and type-2 processes — this is the right structure for multi-type recurrent events. The actual issue was "competing risks" language in the manuscript, which has been fixed:*
- *Keywords: `competing risks` removed, replaced with `multiple event types`*
- *Line 136: "competing event types as censoring" → "other event types as censoring"*
- *Line 186: "competing events as censoring" → "other event types as censoring"*

---

~~**Major Comment 3: Beta/coefficient scaling mechanism completely absent from Methods**~~ — **RETRACTED**

*The Simulation Scenarios section contains a paragraph describing all three DGP adjustments: base coefficient vector β=(1.5,1.0,1.2,1.5,0.5,0.3), ρ-based scaling (×0.9 when ρ=0.9), complexity-based scaling (1.0/0.5/0.2), and baseline rate adjustment (r01=0.20→0.50 at c=2). No action required.*

---

~~**Major Comment 3 (renumbered from 4): "With/without history" lacks a formal notation in the Methods**~~ — **RESOLVED**

The Simulation Scenarios section does mention the with/without history comparison and lists the history predictor symbols (H_i(t), H_i^{(rec,k)}(t), L_i(t), N_i(t), etc.), which is good. However, the following gaps remain:

1. Section 2 (Methods) defines Z_i(t) to always include history, leaving the "without history" condition without a formal definition in the methods proper.
2. Two overlapping sets of history variables are used simultaneously in the code: `H1/H2/H3` from Loe et al. (2025) and `time_since_last_type1/2` from the landmark transformation. It is unclear which symbols in the list correspond to which computed variables, or whether both sets are always included together.

**Action required:** (a) Define Z_i^base(t) (baseline only) vs. Z_i(t) (baseline + history) formally in Section 2 so the without-history condition is notated consistently throughout. (b) Clarify whether H_i(t) and the type-specific temporal proximity variables are drawn from one source or two, and confirm both sets appear in the with-history models.

---

**Major Comment 4 (renumbered from 5): Figure 1 shows ρ=0.9 scenarios while text states results focus on ρ=0.3**

Line 259: "We present results focusing on scenarios with ρ = 0.3." Table 1 contains ρ=0.3 results. But Figure 1's embedded filenames reference `overall_rho0.9_*` plots. A reader checking the figures against the text will find they depict different scenarios. This is a factual inconsistency that would draw an immediate rejection comment from any careful reviewer.

**Action required:** Verify whether Figure 1 shows ρ=0.3 or ρ=0.9, correct the figure file or the text, and ensure Figure 1 and Table 1 depict the same scenario set. If Figure 1 intentionally shows ρ=0.9 to illustrate a different point, this must be stated explicitly.

---

**Major Comment 5 (renumbered from 6): Parallel RNG uses sequential integer seeds — simulation replicates are not independent**

The simulation uses `set.seed(seed)` inside each parallel worker, where `seed ∈ {1, 2, ..., 500}`. Sequential integer seeds from `set.seed()` do not produce independent random streams; the Mersenne Twister (R's default RNG) generates correlated sequences when initialized at consecutive integers. The correct approach for parallel Monte Carlo simulation in R is `RNGkind("L'Ecuyer-CMRG")` with `clusterSetRNGStream()`. The current approach means the 500 "independent" simulations are in fact correlated, potentially inflating precision estimates (narrower SDs than truth) or introducing systematic biases.

**Action required:** Replace the integer-seed approach with L'Ecuyer-CMRG parallel streams. Re-run at least a subset of scenarios to confirm the results are not materially affected.

---

**Major Comment 6 (renumbered from 7): MERF test predictions discard random effects — prediction formula is misleading**

The MERF model equation (line 174) includes the random intercept b_i: Ŝ_i = g(Z_i) + b_i. But all test-set predictions call `predict(merf_model$Forest, data = test_data)`, which uses only the fixed-effects forest g(·) and sets b_i = 0. For subjects in the test set, the random effect is never estimated or applied.

This has two consequences: (1) The MERF C-index reflects only the fixed-effects forest performance, making MERF equivalent to RF at test time. (2) The stated advantage of MERF — capturing individual frailty — is not realized in the predictions being evaluated. If this is the intended "marginal prediction" for new subjects, say so explicitly and update the model equation in the text.

**Action required:** Update the methods to clarify that MERF predictions are marginal (b_i = 0 for test subjects), and discuss whether conditional prediction (using BLUPs for subjects with training history) is a meaningful alternative.

---

### MINOR COMMENTS (should address)

---

**Minor Comment 1: Independent censoring assumption is commented out**

The sentence "and independence between censoring time and recurrent event times" appears commented out in the LaTeX source (line ~50). This is a foundational identifying assumption for pseudo-observation validity. Its absence will draw a reviewer comment. Reinstate it formally: C_i ⊥ {T_{i,j}^(k)*} | X_i. Discuss plausibility in the CARRA application where dropout may be informative.

---

**Minor Comment 2: Overall C-index uses unweighted average across landmark times**

The overall C-index is an equal-weight average across landmark times (line 228). This gives equal influence to late landmark times with sparse risk sets (high variance) and early times with large risk sets. Standard practice weights by the number of comparable pairs at each time. Either adopt weighted averaging or explicitly justify the equal-weight choice.

---

~~**Minor Comment 3: Missing superscript k on at-risk process Y(t,s)**~~ — **RESOLVED**

~~The at-risk process in the KM formula (line 119) lacks a type superscript: Y(t,s) should be Y^(k)(t,s) since the risk set depends on which type's events define the counting process. This is a notational error that would confuse technically expert reviewers.~~

*Fixed: Y(t,s), Y_i(t,s), and Y(t,s^-) throughout the KM block updated to Y^(k)(t,s), Y_i^(k)(t,s), Y^(k)(t,s^-).*

---

**Minor Comment 4: MERF identification conjecture needs supporting evidence**

The Discussion attributes Stratified MERF instability to "a model identification conflict" between history variables and random intercepts. This is plausible but presented as fact. No supporting evidence is given: no variance decomposition, no convergence diagnostics, no comparison of estimated σ²_b across history vs. no-history conditions. Options: (a) provide the evidence (mean σ²_b across 500 replicates, convergence rates), or (b) soften to "one possible explanation is..."

---

~~**Minor Comment 5: Jackknife validity at sparse landmark times**~~ — **RESOLVED**

~~The jackknife approximation for pseudo-observations requires n(t_j) → ∞ at each landmark. At late landmark times (few subjects at risk) and under 60% censoring, this approximation degrades. The code sets NA pseudo-observations when the type-specific risk set is zero, but does not flag near-zero risk sets. Acknowledge this limitation and note the threshold used (minimum event count for valid pseudo-observation generation).~~

*Added to Limitations: jackknife approximation degrades at late landmarks with sparse risk sets; NA excluded but near-threshold pseudo-observations may be noisy.*

---

~~**Minor Comment 6: "Checkin" time included in "no-history" condition**~~ — **RESOLVED**

~~The "without history" RF model still includes the landmark time `checkin` as a predictor. Under high frailty, landmark time is correlated with cumulative event count (long survivors have more events). This means `checkin` partially proxies the history information the condition is supposed to exclude, slightly overstating the marginal contribution of explicit history features. Acknowledge this.~~

*Added to Limitations (fifth point): Z_i^base(t) includes t, which under high frailty partially proxies event history, slightly attenuating the estimated benefit of explicit H_i(t).*

---

~~**Minor Comment 7: Censoring definition inconsistent between code and text**~~ — **RESOLVED**

~~The manuscript reports ~30% and ~60% censoring proportions. The code defines censoring as the fraction of subjects with zero events during follow-up (subject-level "event-free" rate), not the standard observation-level censored interval proportion. These definitions can differ substantially. State which definition is used.~~

*Added to simulation DGP paragraph: censoring proportions are defined as the subject-level event-free rate (proportion of subjects with zero events during follow-up).*

---

~~**Minor Comment 8: Variable importance methods are not fully described**~~ — **RESOLVED**

~~The manuscript mentions Cox |β̂_j × SD(X_j)|, RF permutation importance, and MERF conditional importance, but does not explain how conditional MERF importance is computed or what "conditioning on random effects" means algorithmically. The merFImp function (or equivalent) should be cited.~~

*Expanded the MERF importance description: predictor is permuted in the fixed-effects forest component g(·) while holding estimated b_i fixed, isolating fixed-effect importance beyond the captured frailty.*

---

**Minor Comment 9: C-index only — consider adding at least one calibration metric**

For a methods paper proposing clinical risk prediction tools, discrimination alone is insufficient. Calibration (e.g., integrated Brier score or calibration plots at key horizons) would strengthen the practical case. If this is a deliberate scope restriction, state it explicitly in the Limitations section.

---

~~**Minor Comment 10: Dual history feature sets not described**~~ — **RESOLVED**

~~The with-history models include two overlapping sets of history features: (a) `H1/H2/H3` from Loe et al. (2025) — mean restricted time-to-event, time since last event, event frequency — and (b) `time_since_last_type1`, `n_type1_events`, etc. from the landmark transformation. The overlap is not described, and it is unclear whether both sets are always included simultaneously or separately.~~

*Author confirmed both sets are always included/excluded as a unified block. Added to Z_i(t) definition: H_i(t) is the complete, unified vector of all history predictors — temporal proximity (H_i(t), H_i^(k)(t), L_i(t)), cumulative burden (N_i(t), N_i^(k)(t)), and recurrence frequency (R_i(t), R_i^(k)(t)) — always included or excluded as a single block.*

---

## Part IV: ML Paper Writing Assessment

### Narrative Clarity

**What (contribution):** Clear — first multi-type extension of pseudo-observation RF
**Why (evidence):** Good — 37 scenarios + CARRA application
**So What (impact):** Underdeveloped — the clinical implications of choosing Joint MERF vs. Stratified RF are not made concrete enough for a practitioner audience

**Recommendation:** Add a decision tree or practical guide: "When should a practitioner choose each strategy?" This converts simulation findings into actionable guidance.

### Abstract Quality

The abstract is strong but opens generically ("Longitudinal analysis of recurrent events provides critical insights..."). Per Farquhar's formula, sentence 1 should state the contribution directly.

**Suggested revision of sentence 1:** "We extend the pseudo-observation random forest framework to multi-type recurrent events, proposing four modeling strategies that capture subject-specific heterogeneity and cross-event dependencies without parametric intensity assumptions."

### Introduction

- Contribution bullet list is present ✓
- Methods start ~page 3 ✓
- Background adequately positions relative to Loe et al. (2025) ✓
- **Gap:** The paper does not make explicit what aspect of multi-type settings makes the single-type extension non-trivial. Why can't you just run two separate single-type models? The answer (shared frailty, information borrowing across types) is buried in the Discussion.

### Methods Section Gaps (Summary)

The four strategies are described clearly. The EM algorithm for MERF is appropriately detailed. Beta/coefficient scaling is present in the Simulation Scenarios section ✓. **Remaining gaps:**
1. Formal notation for "without history" condition (see Major Comment 3)
2. Pseudo-observation estimand choice (see Major Comment 1)
3. MERF test-time prediction (see Major Comment 6)

### Results Presentation

- Table 1 is well-organized (mean ± SD format) ✓
- Table 3 (CARRA C-index by tau) is clear ✓
- **Figure 1:** rho inconsistency must be fixed (see Major Comment 4)
- **Figure 3:** Trajectory plots are the paper's strongest visual — keep them prominent

### Discussion Balance

The Discussion correctly identifies:
- Stratified MERF instability ✓
- Joint MERF stability advantage under high frailty ✓
- Practical recommendation by scenario ✓

**Gaps:**
- The identification conjecture is stated as fact (Minor Comment 4)
- Calibration omission is not discussed as a limitation
- The connection to clinical decision-making could be strengthened

### Limitations Section

Present but should add:
1. C-index-only evaluation (no calibration)
2. Independent censoring assumption and its plausibility in CARRA
3. MERF marginal-only test prediction

---

## Priority Action List (Ordered)

| Priority | Comment | Issue |
|----------|---------|-------|
| ~~1 — CRITICAL~~ | ~~KM vs. CIF estimand~~ | ~~RETRACTED — KM correct for multi-type recurrent~~ |
| ~~2 — CRITICAL~~ | ~~DGP language~~ | ~~RESOLVED — "competing risks" → "other event types" throughout~~ |
| ~~3 — MAJOR~~ | ~~Beta/coefficient scaling~~ | ~~RETRACTED — already in manuscript~~ |
| 1 — MAJOR | Fix Figure 1 rho inconsistency | Major 4 |
| 4 — MAJOR | Fix RNG for parallel execution (L'Ecuyer-CMRG) | Major 5 |
| 5 — MAJOR | Add formal Z_i^base(t) notation for without-history condition | Major 3 |
| 6 — MAJOR | Reinstate independent censoring assumption | Minor 1 |
| 7 — MAJOR | Update MERF prediction equation (marginal prediction) | Major 6 |
| ~~8 — SHOULD~~ | ~~Fix superscript k on Y(t,s)~~ | ~~Minor 3~~ — **RESOLVED** |
| 9 — SHOULD | Weight overall C-index or justify equal weighting | Minor 2 |
| 10 — SHOULD | Soften MERF identification conjecture | Minor 4 |
| ~~11 — SHOULD~~ | ~~Address censoring definition inconsistency~~ | ~~Minor 7~~ — **RESOLVED** |
| 12 — SHOULD | Add practical decision guide for strategy selection | Narrative |
| ~~13 — SHOULD~~ | ~~Clarify MERF conditional importance~~ | ~~Minor 8~~ — **RESOLVED** |
| ~~14 — SHOULD~~ | ~~Acknowledge jackknife validity at sparse landmarks~~ | ~~Minor 5~~ — **RESOLVED** |
| ~~15 — SHOULD~~ | ~~Acknowledge checkin proxies history in no-history condition~~ | ~~Minor 6~~ — **RESOLVED** |
| ~~16 — SHOULD~~ | ~~Clarify unified H_i(t) block~~ | ~~Minor 10~~ — **RESOLVED** |

---

## Positive Findings

1. **Subject-level bootstrap is correctly implemented.** The `create_subject_bootstrap` function preserves within-subject correlation. This non-trivial design choice is correctly handled.

2. **Landmark-time-specific C-index is precisely defined and correctly coded.** The concordance rule in `custom_c_index_time_specific` restricts comparisons to subjects at the same landmark, handles ties at 0.5, and correctly implements directionality for Cox vs. RF.

3. **CARRA application is clinically compelling.** The cohort table is thorough; 100 repeated train-test splits for stable C-index estimation is a sound methodological choice.

4. **The Joint MERF finding is genuinely useful.** The identification of when stratified vs. joint approaches work is a practical contribution that practitioners can act on.
