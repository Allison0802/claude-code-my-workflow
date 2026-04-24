# Stress-Test Briefing — Schenk et al. (2024)

**Paper:** *Modeling the restricted mean survival time using pseudo-value random forests*
**Authors:** Alina Schenk, Vanessa Basten, Matthias Schmid (University of Bonn / Koblenz UAS)
**arXiv:** 2411.01381v1 [stat.ME], 2 Nov 2024
**Paper type:** new-estimator (Reviewer-classified)
**Stress-test date:** 2026-04-23
**Run config:** depth=2, 9 lenses, 3×3 parallel group dispatch, novelty-check concurrent

---

## TL;DR

| | |
|---|---|
| **Verdict** | `skip` (mechanical rule: 8 major findings) |
| **Effective read** | Do not treat PVRF as an empirically validated baseline; cite only for the design choice it illustrates. |
| **Severity tally** | 0 critical · 8 major · 1 minor · 0 clean |
| **Novelty-check** | 5.5 / 10 — PROCEED WITH CAUTION |
| **Headline risk** | Mechanism is Mogensen & Gerds (2013) with the estimand changed from CIF to RMST; no differentiation paragraph. |

Schenk et al. introduce **PVRF** (pseudo-value random forests): feed leave-one-out KM-jackknife pseudo-observations of RMST into a CART or conditional-inference random forest, then plug individual predictions into a g-computation formula to get confounder-adjusted treatment contrasts. Interpretability is claimed via local Shapley values and permutation importance. All nine stress-test lenses returned substantive findings, one minor (Estimand) and eight major (the rest) — a uniform pattern of methodological gaps consistent with a competent extension paper that undersells its position relative to prior work.

---

## Severity table

| Lens | Name | Severity | One-line finding |
|---|---|---|---|
| 0 | data | **major** | Silently drops 102/3,754 SUCCESS-A patients via complete-case deletion; no MCAR/MAR justification, no sensitivity analysis. |
| 1 | estimand | minor | Estimand definitions (population, conditional, counterfactual) are precise, but τ=5 in the application sits at the q_max follow-up ceiling — outside the simulation envelope of q50–q90. |
| 2 | identification | **major** | g-computation causal claim made with **no** formal assumptions stated: conditional exchangeability, positivity, consistency, and SUTVA are entirely absent from the text. |
| 3 | methodology | **major** | KM-jackknife pseudo-values require censoring independent of *both* covariates and event times; no IPCW fallback, no CD-censoring simulation, no diagnostic on SUCCESS-A. No analytic variance/CI for predictions or contrasts. |
| 4 | overclaims | **major** | Three confirmed textual overclaims: (i) "higher-dimensional" with empirical envelope p=16, (ii) "causal interpretation" with no identifying-assumption paragraph, (iii) "not affected by restrictive assumptions like PH" while relying on the equally restrictive independent-censoring assumption. |
| 5 | alternatives | **major** | Empirical superiority is partly a benchmark-design artifact: baselines are main-effects-only (no splines, no penalization) while DGPs include crossing hazards in 2/4 scenarios; no Monte Carlo SEs; Scenario 1 (PH holds) reverses the ranking. |
| 6 | generalizability | **major** | Simulation envelope narrow (n=1000, p=16, indep. Weibull censoring, τ∈q50–q90); CD-censoring, small-n (≤300), p≫16, competing risks, and τ at ceiling are all outside support. |
| 7 | positioning | **major** | Mogensen & Gerds (2013) already proposed PVRF's exact mechanism (jackknife pseudo-value + RF regressor + node-variance splits) for CIF. Cited but not differentiated. Same-first-author Schenk & Berger (2024, same SUCCESS-A data) cited only as generic background. |
| 8 | reproducibility | **major** | R version + 8 package versions pinned; ntree/minsplit disclosed. But: no seeds, no mtry grid, code on `imbie.uni-bonn.de/cloud` (link-rot), DGP coefficients offloaded to the external R code, no variance procedure at all. |

---

## Top killer questions

1. **Positioning vs. Mogensen & Gerds (2013):** The paper's core mechanism (jackknife pseudo-values + RF with node-variance splits) is Mogensen & Gerds' 2013 Stat Med method applied to RMST instead of CIF. *Where is the differentiation paragraph that explains why swapping the Kaplan-Meier functional for Aalen-Johansen is methodologically non-trivial, and why the forest ensemble over pseudo-values is a contribution beyond what Mogensen & Gerds already established?*

2. **Missing causal-identification scaffolding:** The Abstract and Introduction promise "valid estimands for the causal analysis of treatment contrasts" via g-computation, but the paper never states conditional exchangeability, positivity, consistency, or SUTVA. *What does "causal interpretation" mean in an observational RMST context without identifying assumptions?* The SUCCESS-A analysis is on a randomized trial so the causal claim is technically defensible there, but the paper markets the method for "medium-sized observational studies" — where none of these assumptions hold by design.

3. **Independent-censoring dependency:** PVRF uses plain KM-based pseudo-values, inheriting Graw et al.'s assumption that censoring is independent of *both* covariates and event times. The paper names CD-censoring in Section 6 as future work (citing Rong et al.) but provides no IPCW variant, no simulation, and no diagnostic on the SUCCESS-A analysis. *What happens to PVRF bias and coverage when censoring depends on covariates, which is the realistic oncology-trial case?*

4. **Benchmark asymmetry driving empirical wins:** Baselines (Cox, Lognormal, GEE) are specified as main-effects-only on all 15 covariates with no splines or penalization, while PVRF is CV-tuned on mtry. Two of the four DGP scenarios enforce crossing survival curves by construction, dooming PH-based competitors. No Monte Carlo standard errors are reported. Scenario 1 (PH holds) has Cox beating PVRF, which the paper concedes. *How much of PVRF's reported superiority is a benchmark-design artifact versus intrinsic estimator merit?*

5. **Empirical envelope vs. marketing envelope:** The Introduction sells PVRF for "applications involving a large number of covariates compared to the number of individuals." The simulation envelope is n=1000, p=16, independent Weibull censoring, τ∈q50–q90 quantiles. *Where is empirical evidence for performance under small-n, high-p, CD-censoring, competing risks, or τ at the observation ceiling?* The SUCCESS-A application (n=3,652, τ=5y at follow-up ceiling 5.5y) is itself outside the simulation support.

---

## Sub-project relevance

### `comparisons/` — ML method comparisons for recurrent events

- **Applies:** Yes. This is an ML-vs-classical method comparison paper in our exact territory (pseudo-values + RF for survival).
- **Data match:** Partial. Weibull/Weibull event+censoring at 25/50/75% with n=1000 and p=16 is a narrower regime than our 37-scenario grid. Our design already includes CD-censoring and competing risks, which Schenk 2024 does not test.
- **Warning:** When citing Schenk 2024 as a pseudo-value-RF comparator, flag three issues from the stress-test: (i) CART-RF and cforest are tuned only on mtry, with no node-size sweep, (ii) the baselines are deliberately under-specified (main effects only), (iii) no Monte Carlo SEs means ranking differences are not statistically tested. Lens 3 (methodology) and Lens 5 (alternatives) apply directly to our own RF evaluations as a quality-control mirror.
- **Missing comparator:** PVRF can be a baseline in our scenarios, but only if we tune its cforest with the same flexibility we give other methods — importing their quoted performance unfiltered would import their benchmark asymmetry.

### `Missing Types/` — pseudo-observations with missing event types

- **Applies:** Partial. Single-event RMST is not our missing-event-type setting, but the pseudo-value + RF substrate is shared with our pseudo-obs methodology.
- **Data match:** Different DGPs (our MCAR/MAR imputation scenarios vs. their single-event complete-case Weibull). The uncharacterized 102-patient complete-case exclusion from SUCCESS-A (Lens 0) is an instructive negative example of the workflow gap our IPW/RPM/DR methods aim to close.
- **Warning:** Lens 0 (data) cites exactly the complete-case-deletion pattern our missing-types methods are designed to avoid. Worth citing as motivation: "approaches like Schenk et al. (2024) exclude patients with any missing covariate without addressing the missing-data mechanism; our work directly targets this gap."
- **Missing comparator:** Not a direct competitor to missing-event-type work. Cite only as the pseudo-value + RF infrastructure reference.

---

## Novelty-check summary

| Field | Value |
|---|---|
| Overall score | 5.5 / 10 |
| Recommendation | PROCEED WITH CAUTION |
| Key differentiator | Unified combination of (1) RMST pseudo-values + (2) conditional inference RF + (3) g-computation + (4) SHAP/perm-importance is not found as a single method elsewhere. |

### Closest prior work

| Paper | Year | Overlap | Key difference |
|---|---|---|---|
| Mogensen & Gerds — RF for competing risks via pseudo-values (Stat Med) | 2013 | **very high** | Uses CIF (Aalen-Johansen) instead of RMST (Kaplan-Meier); single tree → forest is already established |
| Schenk & Berger — Pseudo-value regression trees (Lifetime Data Anal.) | 2024 | **high** | Same first author, same SUCCESS-A dataset, single tree architecture |
| Loe, Murray & Wu — Pseudo-obs RF for recurrent events (Biostatistics) | 2025 | **high** | Recurrent-event-free probability windows, not RMST; no g-computation |
| Zhao — DNN for RMST via pseudo-values (Bioinformatics) | 2021 | medium-high | DNN instead of RF; no g-computation; no interpretability tools |
| Cui et al. — Causal survival forests (JRSS-B) | 2023 | medium | Doubly-robust CATE on RMST-like estimand; no pseudo-values |

### Reviewer grounding (from thematic notebook)

> Mogensen & Gerds (2013) Stat Med 32:3102–3114 [note: novelty-check misidentified first author as "Sachs" — correct is **Mogensen**] proposed exactly PVRF's core mechanism: "replace the censored event status by a jackknife pseudo-value" + "apply an implementation of random forests for uncensored data" + "node variance is chosen as split criterion". Differences from PVRF: (i) CIF via Aalen-Johansen → RMST via KM; (ii) PVRF additionally evaluates partykit's cforest.

---

## What the paper *does* do well

- **Estimand definitions are precise.** Three levels — population μ(τ), conditional μ(τ|X), counterfactual Δᵢ(τ) — written out with clean math.
- **R package versions are pinned** at deck level (R 4.1.2; pseudo 1.4.3; ranger 0.15.1; partykit 1.2.20; simstudy 0.7.1; survival 3.5.7; geepack 1.3.9; iml 0.11.2). That is better than most methods-journal papers.
- **Tree/forest hyperparameters disclosed** (ntree=500, CART minsplit=5, cforest minsplit=20 with minleaf=7, mtry via 5-fold CV).
- **τ choice justified** via Tian-pre-specification based on trial design.
- **Real-world application** on a non-trivial dataset (SUCCESS-A breast cancer trial, n=3,652).

These individually usable elements are why severity settles at "major" throughout rather than "critical" — the paper is competently executed on its own narrow terms.

---

## Recommendation

**`skip`** per mechanical rule (8 major severities ≥ 5 threshold).

In practice for this project:
- **Do not** treat PVRF as an empirically validated baseline — the benchmark asymmetry (Lens 5) and narrow simulation envelope (Lens 6) preclude that reading.
- **Do** cite it as illustrating the pseudo-value + RF + RMST design choice.
- **Do** cite Mogensen & Gerds (2013) directly for the underlying pseudo-value + RF mechanism.
- **Do** let Schenk 2024's missing variance procedure and missing seeds inform our own reproducibility discipline.

If you cite this paper in the comparisons manuscript, you must attach explicit caveats on positioning (vs. Mogensen & Gerds), identification (the causal claim), and benchmark design (baselines, MC SEs). Do not invoke it as evidence that "pseudo-value RF beats Cox" without those qualifications.

---

## Run metadata

- Slug: `schenk_2024_modeling_restricted_2026-04-23`
- Disposable notebook: `c7b7c41a-40f0-4cd4-b271-f5687419b0e0`
- Thematic notebook: `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` (ML for Recurrent Events)
- Total spawn count: 30 (classification 1 + novelty-check 1 + group-moderator×3 + Reviewer/Author sub-subagents×25)
- Aggregate gate results: G-3a, G-3b, G-3c, G-3d, G-3d-bis, G-3e — all PASS (0 violations)
- Transcript: `transcripts/schenk_2024_modeling_restricted_2026-04-23_transcript.md`
- State: `state/schenk_2024_modeling_restricted_2026-04-23_state.json`
