# Stress-Test Transcript — Schenk et al. (2024)

**Paper:** Modeling the restricted mean survival time using pseudo-value random forests
**Authors:** Alina Schenk, Vanessa Basten, Matthias Schmid
**arXiv:** 2411.01381v1
**Slug:** schenk_2024_modeling_restricted_2026-04-23
**Lenses:** 9 | **Turns:** 43 | **Spawns:** 30

---

## Lens 0 — data (MAJOR)

**One-line finding:** Real-data analysis silently drops 102 SUCCESS-A patients via complete-case deletion with no missing-mechanism justification, sensitivity analysis, or comparison of dropped versus retained patients.

**Why it didn't hold:** The paper neither characterizes the missingness mechanism nor performs a sensitivity analysis or multiple imputation. With 2.2% HER2 missingness (a prognostic variable for breast-cancer DFS) and several smaller missingness pockets, complete-case deletion can induce selection bias in both the conditional RMST estimates and the g-computation treatment contrast. This is a standard ICH-E9(R1)/STRATOS expectation for an observational RMST demonstration; the paper's silence undercuts the causal-inference pitch of Section 5.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: In the SUCCESS-A application (Section 5) you exclude 102 of 3,754 patients by complete-case deletion across 10 covariates — including HER2 (2.2% missing) and lymph-node status (0.8% missing), both of which are prognostic for breast-cancer disease-free survival. Where does the paper justify this design choice relative to the missing-data mechanism (MCAR vs MAR), compare baseline characteristics of dropped versus retained patients, and probe the sensitivity of the RMST estimates and g-computation treatment contrast to this deletion? Without that, the real-data demonstration cannot be interpreted as supporting the causal contrast the method is advertised to deliver.
```

#### Author (round 1, sonnet)

```
ANSWER: the paper does not address this. The closest adjacent content is a single sentence in Section 5 stating 'Patients with missing values in any of the considered covariates were excluded from our analysis. The analyzed data comprised 3,652 patients,' together with Table D1 in Appendix D which reports per-covariate missing counts (23 missing tumor stage, 22 grade, 29 lymph-node status, 22 tumor type, 21 ER, 24 PR, 84 HER2). The paper does not discuss MCAR/MAR assumptions, does not compare characteristics of the 102 excluded patients to the 3,652 retained, does not perform multiple imputation, and does not report a sensitivity analysis.

CITATIONS:
- "Patients with missing values in any of the considered covariates were excluded from our anaylsis. The analyzed data comprised 3,652 patients." — Section 5 Application
- "HER2- 2787 (74.2%), HER2+ 883 (23.5%), Missing 84 (2.2%)" — Table D1, Appendix D
- "lymph node status pN+ 2452 (65.3%), pN0 1273 (33.9%), Missing 29 (0.8%)" — Table D1, Appendix D
```

#### Reviewer (round 2, opus)

```
JUDGMENT: conceded
REASONING: The Author explicitly returned 'the paper does not address this' and supplied the adjacent sentence that merely reports the deletion without justification; Table D1 reports missingness counts but contains no MCAR/MAR discussion, no dropped-vs-retained comparison, and no sensitivity analysis.
NEXT: FINAL
SEVERITY: major
```

#### Moderator (round 2, opus)

```
Signal: converging. Decision: close lens. Reasoning: Author conceded on round 1 and depth=1 permits no follow-up. The dropout is documented but the methodological treatment is absent; severity=major because the real-data demonstration is the paper's only observational-causal showcase and complete-case deletion silently undercuts the g-computation claim.
```

---

## Lens 1 — estimand (MINOR)

**One-line finding:** Estimand definitions are mathematically precise (population mu(tau), conditional mu(tau|X), counterfactual Delta_i(tau) via g-computation), but the SUCCESS-A choice of tau=5 years sits essentially at the follow-up ceiling (max 5.5 years, Q3=5.5) — a regime the simulation study never probes, since simulated tau is restricted to q50-q90 of observed times.

**Why it didn't hold:** The paper's estimand itself is clearly defined — this is not a definitional failure. The issue is that the simulation evidence supporting PVRF is calibrated for interior tau (q50-q90 of observed times) while the application uses a tau at the ceiling, where variance inflation and IPCW tail behavior are known to be worst. No robustness check at tau near q_max is provided. Severity=minor because (i) tau was pre-specified by trial design (Tian-compliant) and (ii) the estimand's mathematical definition is not wrong — only the empirical validation envelope is misaligned.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: Your SUCCESS-A analysis sets tau = 5 years, but Section 5 reports max observation time 5.5 years with third quartile 5.5 years — i.e., tau sits essentially at the follow-up ceiling, where you yourselves cite Tian et al. warning that 'estimation of the RMST may no longer be possible if tau becomes too large.' Your own simulation study explicitly restricts tau to q50-q90 of observed times. So on what empirical or theoretical basis do you claim PVRF and its pseudo-value IPCW weighting remain stable at the applied tau? The simulation gives you no evidence at that regime, and the definition of the conditional estimand mu(tau|X) is only as useful as the region of tau where it is identified and estimable.
```

#### Author (round 1, sonnet)

```
ANSWER: The paper explicitly defines the estimand at all three levels and justifies tau=5 as pre-specified by clinical design. For the population estimand: 'the RMST ... can be expressed as mu(tau) = E[min(T, tau)] = integral_0^tau S(t) dt.' For the patient-specific conditional estimand: 'This paper is concerned with the estimation of individual RMSTs mu(tau|X_i) = integral_0^tau S(t|X_i) dt, i = 1,...,n.' For the causal treatment contrast: Delta_i(tau) = mu(tau|X^{-trt}_i, X^{trt}_i=A) - mu(tau|X^{-trt}_i, X^{trt}_i=B), averaged across patients to yield Delta(tau). The choice of tau=5 years is justified by direct correspondence to 'the length of the follow-up period' and follows Tian et al.'s recommendation to pre-select tau 'based on clinical and feasibility considerations' in the trial-planning phase.

CITATIONS:
- "the RMST ... can be expressed as mu(tau) = E[min(T, tau)] = integral_0^tau S(t) dt" — Section 1
- "This paper is concerned with the estimation of individual RMSTs mu(tau|X_i) = integral_0^tau S(t|X_i) dt" — Section 1
- "Delta_hat_i(tau) = mu_hat(tau|X^{(-trt)}_i, X^{(trt)}_i=A) - mu_hat(tau|X^{(-trt)}_i, X^{(trt)}_i=B)" — Equation (9), Section 2.3
- "The main aim of our analysis was to model the RMST for DFS at tau = 5 years, corresponding to the length of the follow-up period." — Section 5
- "Before data collection ... it is advisable to pre-select tau based on clinical and feasibility considerations." — Section 6 (citing Tian et al.)
```

#### Reviewer (round 2, opus)

```
JUDGMENT: handwaved
REASONING: The Author correctly cites the estimand definitions and the Tian pre-specification justification for tau=5, but sidesteps the core attack: the simulation range (q50-q90) never includes a tau at the follow-up ceiling, so the empirical evidence supporting PVRF does not cover the regime actually used in the application. Pre-specification authority does not substitute for demonstrated estimator stability.
NEXT: FOLLOWUP
FOLLOWUP: Point me to any simulation scenario, appendix figure, or bootstrap analysis where PVRF is evaluated at tau equal to or exceeding the 90th percentile of observed times — i.e., at a regime comparable to the 5-year horizon in a 5.5-year-max-follow-up study. If no such evidence exists in the paper, concede that the applied tau sits outside the empirically validated range.
```

#### Author (round 2, sonnet)

```
ANSWER: the paper does not address this. The simulation study states explicitly that 'In each of the four scenarios, we considered three different censoring proportions (25%, 50%, 75%) and five different values of the time horizon tau. The latter were determined by the 50%, 60%, 70%, 80% and 90% quantiles of the observed times.' No scenario evaluates tau at or beyond q90, and the paper does not report bootstrap stability diagnostics or appendix figures targeting the ceiling regime that matches the SUCCESS-A tau=5 choice. The closest adjacent content is the general remark in Section 6 that 'we expect both the RMSE and RMSE_Delta values to increase with tau,' but this is not a targeted sensitivity analysis for the applied tau.

CITATIONS:
- "In each of the four scenarios, we considered three different censoring proportions (25%, 50%, 75%) and five different values of the time horizon tau. The latter were determined by the 50%, 60%, 70%, 80% and 90% quantiles of the observed times." — Section 3, Experiments
- "Generally, we expect both the RMSE and RMSE_Delta values to increase with tau, since the RMST also rises with tau." — Section 3
```

#### Reviewer (round 3, opus)

```
JUDGMENT: conceded
REASONING: Under close_lens_mode, the Author conceded that simulation coverage stops at q90 and that no targeted stability analysis exists for tau at the follow-up ceiling. The estimand definitions themselves are unambiguous — this is a validation-envelope gap, not a definitional failure — so severity is pinned at minor.
NEXT: FINAL
SEVERITY: minor
```

#### Moderator (round 3, opus)

```
Signal: converging. Decision: close lens under close_lens_mode after one follow-up (depth=2). Reasoning: The core estimand (population, conditional, counterfactual) is precisely defined and the Tian pre-specification argument for tau=5 is legitimate; the surviving weakness is that simulation evidence does not cover the applied tau regime. Severity=minor rather than major because the estimand is not mis-specified — only the empirical support envelope is narrower than the application.
```

---

## Lens 2 — identification (MAJOR)

**One-line finding:** The paper promises 'valid estimands for the causal analysis of treatment contrasts' via g-computation but never states a single formal identification assumption — no unmeasured confounding, exchangeability, positivity, consistency, and SUTVA are entirely absent from the text.

**Why it didn't hold:** Schenk et al. frame PVRF as delivering 'valid estimands for the causal analysis of treatment contrasts' and recommend g-computation for non-randomized studies where 'covariates usually take the roles of confounders.' Causal identification for g-computation requires at minimum (i) conditional exchangeability / no unmeasured confounding given measured baseline covariates, (ii) positivity of the treatment distribution within covariate strata, (iii) consistency linking counterfactuals to observed outcomes, and (iv) SUTVA. None of these appears. The SUCCESS-A RCT partially escapes this because randomization delivers unconditional exchangeability by design, but the Introduction and Abstract advertise the method for 'observational longitudinal trials' and 'medium-sized observational studies containing many potential confounders' where the assumptions are load-bearing. Absence of this discussion leaves the causal claim unsupported in exactly the setting the paper targets.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: Your abstract promises 'valid estimands for the causal analysis of treatment contrasts' and your Introduction claims that applying g-computation to PVRF 'allows for the direct estimation and causal interpretation of RMST differences,' targeting 'medium-sized observational studies containing many potential confounders.' Yet g-computation is identified only under conditional exchangeability (no unmeasured confounding), positivity, consistency, and SUTVA. Where does the paper state, discuss, or even acknowledge these four assumptions? If they are missing, the causal framing in the Abstract and Introduction is unsupported whenever the method is applied outside of an RCT.
```

#### Author (round 1, sonnet)

```
ANSWER: the paper does not address this. The terms 'no unmeasured confounding', 'conditional exchangeability', 'positivity', 'consistency' (as a causal assumption), 'SUTVA', and 'ignorability' do not appear anywhere in the text. The word 'consistent' appears only in the statistical-estimator sense (e.g., 'a consistent estimator of the censoring survival function'). The paper's strongest relevant passage treats g-computation as a practical adjustment tool: 'the calculation of treatment contrasts is less trivial when additional covariates have to be taken into account, particularly in non-randomized studies where the covariates usually take the roles of confounders. In these cases, we propose to apply g-computation to estimate treatment contrasts,' followed by Equations (9) and (10). The only explicitly stated identifying assumption in the paper is the covariate-independent censoring assumption for the pseudo-observations: 'we assume that the censoring times are independent of both the covariates and the event times' (Section 2, following Graw et al.), which identifies the conditional RMST but not the causal contrast.

CITATIONS:
- "By applying a g-computation formula [23, 24] to the estimated RMST values, PVRF further allows for the direct estimation and causal interpretation of RMST differences." — Section 1
- "In these cases, we propose to apply g-computation to estimate treatment contrasts." — Section 2.3
- "we assume that the censoring times are independent of both the covariates and the event times." — Section 2
- (Negative citations — terms NOT appearing in the paper: 'no unmeasured confounding', 'conditional exchangeability', 'positivity', 'SUTVA', 'ignorability')
```

#### Reviewer (round 2, opus)

```
JUDGMENT: conceded
REASONING: Author confirmed none of the four g-computation identification assumptions appears in the paper, and the only stated assumption (covariate-independent censoring) identifies the outcome-model conditional expectation, not the causal contrast. With a method pitched for observational studies, the omission materially undermines the causal claim in the Abstract and Introduction.
NEXT: FINAL
SEVERITY: major
```

#### Moderator (round 2, opus)

```
Signal: converging. Decision: close lens. Reasoning: Depth=1 and Author conceded explicitly. The gap is real: causal framing is promised in the abstract and intro, but no formal identification scaffolding exists. Severity=major rather than critical because (i) the paper does separate predictive from causal use-cases in the discussion and (ii) the SUCCESS-A application is on a randomized trial where unconditional exchangeability holds by design — though the paper's target use-case in observational data does leave the causal claim unsupported.
```

---

## Lens 3 — methodology (MAJOR)

**One-line finding:** PVRF uses KM-based jackknife pseudo-values requiring censoring independent of BOTH covariates and event times, with no IPCW fallback, no CD-censoring simulation, and no diagnostic check in the SUCCESS-A application.

**Why it didn't hold:** The estimator inherits Graw/Overgaard's independent-censoring requirement unchanged; when this is violated (as is typical in oncology trials with differential dropout), the KM-based pseudo-values are biased and the forest regresses on biased targets. The paper neither stress-tests nor diagnoses this, so the headline SUCCESS-A DFS claim is not robustness-checked. Additionally, no analytic variance for PVRF RMST predictions or for the g-computation-style treatment contrast is provided; inference is punted to future work with a bootstrap suggestion.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: The paper promotes a 'pseudo-value random forest' that substitutes jackknife pseudo-values for (censored) outcomes and then fits an off-the-shelf regression forest. How exactly are the jackknife pseudo-values constructed under dependent right-censoring - specifically, does the estimator use IPCW pseudo-values (Binder et al. 2014/Overgaard et al.) or naive Kaplan-Meier-based pseudo-values, and under what censoring assumption are the resulting forest predictions consistent for E[min(T, tau) | X]?
```

#### Author (round 1, sonnet)

```
ANSWER: The paper uses leave-one-out jackknife pseudo-values based on the Kaplan-Meier estimator (Equation 2), NOT IPCW-style pseudo-values. The paper explicitly requires the strong 'completely independent censoring' assumption - censoring independent of both covariates AND event times - citing Graw et al. Consistency of covariate effect estimation is invoked via Overgaard et al. (2017) under regularity assumptions. No covariate-dependent censoring correction is built in.

CITATIONS:
- 'theta_hat_i(tau) = n * integral_0^tau S_KM(t) dt - (n-1) * integral_0^tau S^{-i}_KM(t) dt' -- Section 2.1, Eq. (2)
- 'Following Graw et al. [21], we assume that the censoring times are independent of both the covariates and the event times' -- Section 2
- 'Overgaard et al. [22] showed that the replacement of mu_i(tau) with the pseudo-values theta_hat_i(tau) enables the consistent estimation of covariate effects on the RMST' -- Section 2.1
```

#### Reviewer (round 2, opus)

```
JUDGMENT: cited
REASONING: The Author quoted the exact construction equation (KM-based jackknife) and the verbatim independent-censoring assumption. This exposes a methodological vulnerability (no covariate-dependent censoring correction) that I should probe before closing.
NEXT: FOLLOWUP
FOLLOWUP: The paper uses KM-based jackknife pseudo-values and assumes censoring is independent of BOTH covariates and event times. In realistic biomedical applications like SUCCESS-A (breast-cancer trial), censoring is almost certainly covariate-dependent (e.g., differential dropout by age, treatment arm, performance status). Does the paper provide any simulation, diagnostic, or theoretical result showing the PVRF estimator's bias or coverage behavior when this strong assumption is violated? If not, how can the authors justify applying PVRF to SUCCESS-A without IPCW pseudo-values?
```

#### Author (round 2, sonnet)

```
ANSWER: the paper does not address this. The paper acknowledges covariate-dependent censoring exists but does not treat it internally. Section 6 merely points to Rong et al. for CD-censoring RMST adjustment; the SUCCESS-A application reports no diagnostic check that censoring is independent of age, BMI, stage, nodal status, etc. All simulation DGPs (Section 3) use censoring independent of covariates by construction. IPCW pseudo-values are NOT offered as a fallback; IPCW enters the paper only through the WRSS cross-validation error metric, not through the outcome construction.

CITATIONS:
- 'Methods to adjust RMST estimation for covariate-dependent censoring have been studied in Rong et al. [15]' -- Section 6 (Discussion)
- 'Patients were censored at the last date at which they were known to be disease-free' -- Section 5 (SUCCESS-A); no subsequent CD-censoring diagnostic
- 'Following Graw et al. [21], we assume that the censoring times are independent of both the covariates and the event times' -- Section 2
```

#### Reviewer (round 3, opus)

```
JUDGMENT: conceded
REASONING: The Author explicitly conceded with 'the paper does not address this' - the PVRF estimator inherits the independent-censoring assumption from the KM jackknife, provides no CD-censoring robustness check or IPCW alternative, and applies the method to a 10-covariate clinical trial where CD-censoring is virtually guaranteed. This is a major methodological gap affecting both simulation-to-application transport and the headline SUCCESS-A result.
NEXT: FINAL
SEVERITY: major
```

#### Moderator (round 3, opus)

```
Signal: Author conceded R2; depth-2 lens exercised fully. Decision: close lens with severity=major. Reasoning: PVRF's KM-jackknife construction binds it to the independent-censoring assumption; no IPCW fallback, no sensitivity study, no CD-censoring diagnostic on SUCCESS-A. This is a methodology gap, not a presentation issue.
```

---

## Lens 4 — overclaims (MAJOR)

**One-line finding:** Abstract markets 'higher-dimensional' applicability (empirical envelope p=16) and 'causal interpretation' of treatment contrasts with no accompanying positivity/exchangeability caveat or mention of the strict independent-censoring assumption.

**Why it didn't hold:** The paper uses 'higher-dimensional' as a marketing phrase rather than a technical claim; its simulations never exceed p=16 and never approach p/n regimes where dimensionality would bite. The causal interpretation via g-computation requires exchangeability and positivity, which are unmentioned; and the Abstract's framing that PVRF is 'not affected by restrictive assumptions like the proportional hazards assumption' slides past the fact that KM-jackknife pseudo-values require the equally restrictive independent-censoring assumption.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: The Abstract/Introduction market PVRF as a flexible, data-adaptive, nonparametric alternative to Cox that 'does not require pre-specification of effect structures' and recovers 'individual RMST predictions' usable for treatment-contrast estimation. Does the paper ever warn readers that (a) the SUCCESS-A result rests on an assumption-LIGHT causal interpretation of treatment contrasts from observational-style covariate adjustment, (b) the method inherits the strong independent-censoring assumption, and (c) PVRF was only evaluated in low-dimensional (p <= 11) simulations -- or does the paper let these caveats go unsaid while selling generality?
```

#### Author (round 1, sonnet)

```
ANSWER: The paper claims, verbatim in the Abstract: 'PVRF offers a high flexibility in detecting relevant covariate effects from higher-dimensional data'; the Introduction sharpens this to 'a particularly convenient method for applications involving a large number of covariates compared to the number of individuals.' Causal interpretation is promoted in the Abstract ('valid estimands for the causal analysis of treatment contrasts') and the Introduction claims 'applying a g-computation formula... allows for the direct estimation and causal interpretation of RMST differences.' Neither the Abstract nor the Introduction warns about the independent-censoring assumption (deferred to Section 2) nor caveats the causal claim with positivity/exchangeability requirements. The simulation study uses 16 covariates maximum (10 signal + 5 noise + 1 treatment) -- not 'higher-dimensional' by any contemporary benchmark.

CITATIONS:
- 'PVRF offers a high flexibility in detecting relevant covariate effects from higher-dimensional data' -- Abstract
- 'particularly convenient method for applications involving a large number of covariates compared to the number of individuals' -- Introduction
- 'allows for the direct estimation and causal interpretation of RMST differences' -- Introduction
- Simulation DGP: 'five continuous covariates... five dichotomous covariates... dichotomous treatment variable... five independent standard normally distributed noise variables' (total p=16) -- Section 3
- 'Following Graw et al. [21], we assume that the censoring times are independent of both the covariates and the event times' -- Section 2 (not Abstract/Intro)
```

#### Reviewer (round 2, opus)

```
JUDGMENT: handwaved
REASONING: The Author confirmed three clear overclaims: (1) 'higher-dimensional' is marketed in the Abstract but the empirical envelope is p=16 with n=1000 - this is standard, not high-dimensional; (2) 'causal interpretation of RMST differences' via g-computation is asserted without stating positivity, exchangeability, or no-unmeasured-confounding assumptions anywhere in the Abstract/Intro; (3) the strict independent-censoring assumption is mentioned only in Section 2, leaving readers of the Abstract with a false sense of assumption-lightness. The paper's defensive text ('model-free, not affected by restrictive assumptions like proportional hazards') conflates PH-freeness with assumption-freeness, which it is not.
NEXT: FINAL
SEVERITY: major
```

#### Moderator (round 2, opus)

```
Signal: Depth-1 lens closed after 1 author round. Decision: severity=major. Reasoning: Three confirmed overclaims (high-dim marketing, unconditional causal language, buried independent-censoring assumption); handwaved judgment preserved despite Author citing the paper, because the citations support the overclaim characterization, not refute it.
```

---

## Lens 5 — alternatives (MAJOR)

**One-line finding:** PVRF's empirical superiority is largely attributable to deliberately handicapped baselines (main effects only, no splines, no penalization) and crossing-hazards DGPs in half the scenarios, not to intrinsic PVRF merit; no Monte Carlo SEs means narrow ranking gaps cannot be distinguished from noise.

**Why it didn't hold:** When a novel forest method is compared only against under-specified parametric baselines on DGPs that include substantial interactions and crossing hazards, 'winning' is partly a benchmark-construction artifact rather than a method property. Cleaner alternatives -- penalized Cox with interaction basis expansions, AFT with flexible error, BART, survival forests with Breiman-Cutler variance -- would likely close much of the reported RMSE gap. Without MC standard errors, even the present rankings cannot be statistically distinguished from Monte Carlo noise at MC=100.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: PVRF is compared against Cox, a lognormal AFT, and a CART-based pseudo-value forest, and 'wins' particularly in crossing-hazards and non-linear DGPs. Given that the simulation DGPs are explicitly constructed with uniform-from-[-1,1] sampled main effects, interactions between continuous covariates, continuous x dichotomous interactions, and (in scenarios 3-4) a time-varying treatment effect generating crossing curves -- this DGP is almost maximally tilted toward tree ensembles and against PH/parametric baselines. How is the reader supposed to distinguish 'PVRF is genuinely better' from 'the simulation was painted specifically where Cox and lognormal have to lose'? Were baselines tuned (e.g., Cox with splines, penalized Cox, AFT with flexible error, Ridge/Lasso on RMST-GEE)? Were Monte Carlo standard errors computed so that apparent winners in small samples aren't just noise-dominated?
```

#### Author (round 1, sonnet)

```
ANSWER: The Cox and lognormal baselines were not tuned or regularized; they were given only main-effects specifications on all 15 covariates with NO interaction terms, NO splines, NO penalization, even though Scenarios 2 and 4 contain by-construction continuous x continuous and continuous x dichotomous interactions drawn from U(-1,1). PVRF (both CART and conditional) was given 5-fold CV tuning of mtry. A 'correctly-specified' Cox Reference model is included that DOES match the DGP (including time-varying treatment stratification) and this Reference beats PVRF in Scenario 1 RMSE. The paper reports 100 Monte Carlo replications at n=1000 but no Monte Carlo standard errors or confidence bands on the RMSE curves -- all results are shown as average-lines only. Scenarios 3 and 4 (half of all scenarios) enforce crossing survival curves by construction.

CITATIONS:
- 'For the Cox, Lognormal and [GEE] modeling approaches... we specified the main effects of all available continuous and dichotomous covariates (including the noise variables) but did not consider any interaction terms' -- Section 3 / Appendix B
- 'The number of candidate split variables in each node (mtry) was tuned using five-fold cross validation' -- Appendix B
- 'The simulation study was based on 100 Monte Carlo replications... n = 1000' -- Section 3
- 'ϑtrt(t) = {-2 if t <= t0; 2 if t > t0}... resulting in crossing survival curves' -- Table 1
- 'the best performing model being the Cox model followed by the Lognormal model. This result can be explained by the fact that the Cox model matches the data-generating mechanism' (Scenario 1) -- Section 4
```

#### Reviewer (round 2, opus)

```
JUDGMENT: cited
REASONING: The Author confirmed the alternative-explanation concern with specific citations: (1) baselines are deliberately under-specified (main effects only, no interactions, no splines, no penalization), making the comparison structurally unfair in Scenarios 2 and 4 where the DGP includes up to 8 random interactions; (2) no Monte Carlo SEs are reported, so the paper cannot rule out that PVRF-vs-conditional-forest and other narrow ranking gaps are within sampling noise at MC=100; (3) 50% of scenarios have crossing-hazards by construction; (4) even the paper's own Scenario 1 shows Cox wins when PH holds -- a concession that the empirical superiority is DGP-contingent. JUDGMENT is 'cited' while SEVERITY reflects the underlying alternative-explanation gap.
NEXT: FINAL
SEVERITY: major
```

#### Moderator (round 2, opus)

```
Signal: Depth-1 lens closed after 1 author round; Author cited but the citations confirmed rather than refuted the alternative-explanation hypothesis. Decision: severity=major. Reasoning: apparent empirical superiority of PVRF is confounded by (a) main-effects-only baselines against interaction-rich DGPs, (b) crossing-hazards construction in 2/4 scenarios, (c) absence of Monte Carlo SEs at MC=100 -- a reader cannot attribute the win to the method versus the benchmark design.
```

---

## Lens 6 — generalizability (MAJOR)

**One-line finding:** Simulation envelope is narrow (n=1000, p=16, independent Weibull censoring, tau in q50-q90 of observed times, no competing risks, no p>>n); no evidence supports the Introduction's 'large number of covariates compared to individuals' claim or the SUCCESS-A tau-at-ceiling regime.

**Why it didn't hold:** The paper's empirical support is confined to a single Weibull/Weibull DGP with completely independent censoring, fixed n=1000, and fixed p=16. Every regime that matters for the paper's own marketing claims and for its headline application is outside this support: CD-censoring (realistic in oncology trials), small-n (observational subgroups), p>>n (the Introduction's pitch), competing risks (cause-specific RMST), and tau at the observational ceiling (the SUCCESS-A choice). A 2024 ML-methods paper that does not probe a single one of these is not positioned to support the generalizability claims in its own abstract.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: The paper's simulation DGPs use Weibull event times, independent (completely random) censoring calibrated to 25/50/75% censoring rates, fixed p=11-16 covariates, n=1000, and a pre-selected tau in the q50-q90 range of observed times -- and SUCCESS-A has n=3,652, p=10, tau at the follow-up ceiling. Where does the paper provide evidence that PVRF's bias, RMSE, and C-index behavior hold up outside this narrow operating envelope -- specifically under (a) covariate-dependent censoring, (b) small n (say n <= 300), (c) high-dimensional p >> 16 (e.g., p = 100, 500 with sparse signals), (d) competing-risks settings where a cause-specific RMST is the target, or (e) tau at or near the observational ceiling (the SUCCESS-A regime)?
```

#### Author (round 1, sonnet)

```
ANSWER: the paper does not address this. All simulation evidence is confined to a single operating envelope: n=1000 training + n=1000 test, p=16 (10 signal + 5 noise + 1 treatment), Weibull events with Weibull independent censoring at 25/50/75% rates, and tau in {q50, q60, q70, q80, q90} of observed times. Covariate-dependent censoring, small-n (n<=300), high-dimensional p>>16, and competing risks are never simulated. The only extrapolation to n=3652 and tau at the follow-up ceiling is the SUCCESS-A demonstration, which provides no ground truth.

CITATIONS:
- 'each of size n = 1000' -- Section 3
- 'censoring times were generated independently of the survival times, using the same Weibull model with eta_i(t) = 0' -- Section 3
- 'three different censoring proportions (25%, 50%, 75%) and five different values of the time horizon tau. The latter were determined by the 50%, 60%, 70%, 80% and 90% quantiles of the observed times' -- Section 3
- 'five continuous covariates ... five dichotomous covariates ... In addition, we considered a dichotomous treatment variable ... Furthermore, we added five independent standard normally distributed noise variables' -- Section 3 (p=16 total)
- 'particularly convenient method for applications involving a large number of covariates compared to the number of individuals' -- Section 2.2 (claim not simulated)
- 'Methods to adjust RMST estimation for covariate-dependent censoring have been studied in Rong et al. [15]' -- Section 6 (referenced but not implemented or simulated)
```

#### Reviewer (round 2, opus)

```
JUDGMENT: conceded
REASONING: The Author explicitly conceded that (a) CD-censoring is not simulated (censoring generated with eta_i(t)=0), (b) competing risks are not simulated, (c) p>>n is not simulated though the Introduction markets exactly that regime, (d) small-n (n<=300) is not simulated, and (e) no simulation evidence is provided for tau at or near the follow-up ceiling. The generalizability envelope that matters for the SUCCESS-A application and for the Introduction's selling points lies entirely outside the simulation support.
NEXT: FINAL
SEVERITY: major
```

#### Moderator (round 2, opus)

```
Signal: Author conceded on all five probed axes of the generalizability envelope; depth-2 budget does not require a follow-up when judgment is 'conceded'. Decision: close lens at severity=major. Reasoning: the gap between the paper's marketing envelope (large-p, causal, flexible) and the simulation envelope (n=1000, p=16, indep. censoring, Weibull, no competing risks, interior tau) is the substantive generalizability failure.
```

---

## Lens 7 — positioning (MAJOR)

**One-line finding:** The paper cites Mogensen & Gerds (2013) and Schenk & Berger (2024) only as generic grounding; it never writes a delta paragraph differentiating PVRF's estimand (RMST via KM-jackknife) from Mogensen & Gerds' CIF-via-Aalen-Johansen forest, nor PVRF's forest ensemble from Schenk & Berger's single-tree architecture on the same SUCCESS-A dataset.

**Why it didn't hold:** PVRF is essentially Mogensen & Gerds (2013) with the estimand changed from CIF to RMST, and Schenk & Berger (2024) with the architecture changed from a single tree to a forest. The paper cites both priors but never differentiates them, never motivates why the substitution is methodologically nontrivial, and never runs a head-to-head empirical comparison. For a journal submission in 2024, this is the minimum positioning deliverable a referee would expect; its absence makes the contribution look incremental in a way the Abstract does not acknowledge.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: The novelty-check identifies 'Sachs & Gerds (2013)' [actually Mogensen & Gerds (2013), Stat. Med. 32:3102-3114] as 'very high overlap' - same mechanism (jackknife pseudo-values fed to a random forest regressor) applied to competing-risks CIF, and Schenk & Berger (2024, Lifetime Data Analysis) as 'high overlap' - same first author, pseudo-value regression trees on the same SUCCESS-A breast-cancer dataset. Where in the paper does the author team explicitly cite Mogensen & Gerds (2013) and Schenk & Berger (2024), and explicitly differentiate PVRF's methodological contribution from those two works? Merely generalizing Mogensen & Gerds from CIF to RMST, or swapping the tree-building algorithm from Schenk & Berger's single-tree CART to a forest, is an incremental methodological move that demands a precise delta statement rather than a silent substitution.

THEMATIC_QUERY: Sachs Gerds 2013 random forest competing risks pseudo-values; pseudo-value regression tree Schenk Berger 2024; pseudo-observations machine learning RMST forest prior work - compare method contributions across these works.
```

#### Moderator (round 1, opus)

```
THEMATIC_QUERY_RESULT: Thematic notebook confirms the correct attribution is Mogensen & Gerds (2013) Stat Med 32:3102-3114 (not 'Sachs & Gerds' as the novelty-check had it). Mogensen & Gerds proposed exactly PVRF's core mechanism: 'replace the censored event status by a jackknife pseudo-value' + 'apply an implementation of random forests for uncensored data' + 'node variance is chosen as split criterion for growing regression trees'. Differences from PVRF are mechanical: (i) Mogensen & Gerds target the CIF (cumulative incidence for a specific cause) using Aalen-Johansen-based pseudo-values; PVRF targets RMST using Kaplan-Meier-based pseudo-values. (ii) Mogensen & Gerds use standard random forests with node variance; PVRF additionally evaluates partykit's conditional inference forest and recommends it. The thematic notebook also confirms Schenk & Berger (2024) 'formally developed pseudo-value regression trees' as single-tree architecture on pseudo-values.
```

#### Author (round 1, sonnet)

```
ANSWER: Both prior works are cited but not explicitly differentiated. Mogensen & Gerds (2013) appears as reference [11] and is invoked only as general grounding for combining pseudo-values with random forests: 'Our method is characterized by a non-parametric approach combining pseudo-value modeling [9] with random forest regression [10, 11]' (Section 1) and 'we propose to model individual RMSTs by using the pseudo-values ... as continuous outcome variable in a random forest regression model [10, 11]' (Section 2.2). Schenk, Berger & Schmid (2024) appears as reference [27] as justification for using decision trees with pseudo-values: 'conventional modeling techniques like linear regression or decision trees [27]' (Section 2.1), and as one of several possible extensions in the Discussion: 'extend our approach to other statistical modeling or machine learning techniques, e.g. to gradient boosting [27] or deep neural networks' (Section 6). The paper provides no passage contrasting PVRF's estimand (RMST via KM-jackknife) against Mogensen & Gerds' estimand (CIF via Aalen-Johansen-jackknife), nor PVRF's forest ensemble against Schenk & Berger's single-tree architecture, nor any empirical head-to-head comparison with either prior.

CITATIONS:
- '[11] U. B. Mogensen and T. A. Gerds. A random forest approach for competing risks based on pseudo-values. Statistics in Medicine, 32:3102-3114, 2013.' -- Reference list
- '[27] A. Schenk, M. Berger, and M. Schmid. Pseudo-value regression trees. Lifetime Data Analysis, 30:439-471, 2024.' -- Reference list
- 'Our method is characterized by a non-parametric approach combining pseudo-value modeling [9] with random forest regression [10, 11]' -- Section 1
- 'we propose to model individual RMSTs by using the pseudo-values theta_i(tau) as continuous outcome variable in a random forest regression model [10, 11]' -- Section 2.2
- 'facilitating the application of conventional modeling techniques like linear regression or decision trees [27]' -- Section 2.1
- 'extend our approach to other statistical modeling or machine learning techniques, e.g. to gradient boosting [27] or deep neural networks [34, 51]' -- Section 6
```

#### Reviewer (round 2, opus)

```
CONFRONTATION: The thematic-notebook query confirms that Mogensen & Gerds (2013, Stat. Med. 32:3102-3114) already proposed the exact mechanism PVRF now deploys: 'replace the censored event status by a jackknife pseudo-value' and then apply 'an implementation of random forests for uncensored data' with 'node variance ... chosen as split criterion for growing regression trees' (Mogensen & Gerds 2013 abstract; confirmed in thematic notebook). The only methodological delta in PVRF is (i) swapping Aalen-Johansen-based CIF pseudo-values for Kaplan-Meier-based RMST pseudo-values -- a substitution that follows trivially from the estimand change -- and (ii) optionally using partykit's conditional inference forest instead of ranger's CART. The Author's defense confirms that PVRF cites Mogensen & Gerds only as generic grounding ('combining pseudo-value modeling with random forest regression'), never as a prior method to be differentiated from. Similarly, Schenk & Berger (2024) -- same first author, same SUCCESS-A dataset -- is cited only as justification for using decision trees with pseudo-values, and as a generic 'gradient boosting' extension option. The paper never writes a delta paragraph of the form 'Unlike Mogensen & Gerds, PVRF targets RMST rather than CIF and uses KM- rather than Aalen-Johansen-based pseudo-values; unlike Schenk & Berger, PVRF uses a forest ensemble rather than a single tree.' The omission is particularly striking given the shared first author with Schenk & Berger (2024) and the shared SUCCESS-A application.
```

#### Author (round 2, sonnet)

```
ANSWER: the paper does not address this. No passage explicitly differentiates PVRF from Mogensen & Gerds (2013) -- the CIF-vs-RMST estimand contrast and the Aalen-Johansen-vs-Kaplan-Meier pseudo-value substrate difference are never drawn. No passage explicitly differentiates PVRF from Schenk & Berger (2024) -- the single-tree-vs-forest-ensemble contrast is never drawn, and the shared SUCCESS-A dataset is never flagged. Both references appear only as generic background.

CITATIONS:
- 'combining pseudo-value modeling [9] with random forest regression [10, 11]' -- Section 1 (generic grounding only)
- 'conventional modeling techniques like linear regression or decision trees [27]' -- Section 2.1 (generic grounding only)
- 'extend our approach to other statistical modeling or machine learning techniques, e.g. to gradient boosting [27] or deep neural networks' -- Section 6 (generic extension example)
```

#### Reviewer (round 3, opus)

```
JUDGMENT: conceded
REASONING: The Author's second answer confirmed verbatim that the paper contains no passage differentiating PVRF's estimand and mechanism from Mogensen & Gerds (2013) or Schenk & Berger (2024). Both priors are cited only as generic grounding. Under close_lens_mode I close the lens.
NEXT: FINAL
SEVERITY: major
```

#### Moderator (round 3, opus)

```
Signal: Author conceded the positioning gap twice across two confrontation turns; thematic notebook independently confirmed Mogensen & Gerds (2013) is the direct mechanistic precursor. Decision: close lens at severity=major. Reasoning: the priors are cited (so not critical) but not differentiated (so not clean or minor). Novelty-check score 5.5 + missing delta paragraph is a major positioning failure for a 2024 Stat Med paper.
```

---

## Lens 8 — reproducibility (MAJOR)

**One-line finding:** R version and package versions are pinned and tree hyperparameters specified, but the paper lacks random seeds, the mtry tuning grid, a permanent code repository (code lives on a rot-prone institutional cloud URL), the DGP coefficient values (offloaded to that same URL), and any variance/CI procedure for PVRF predictions or the g-computation contrast.

**Why it didn't hold:** A 2024 methods paper needs three things to be reproducible: (a) permanent code hosting with version pinning (missing - Bonn cloud URL is not permanent), (b) seeded Monte Carlo and application runs (missing - no seeds mentioned), and (c) an inferential procedure so downstream users can apply the method (missing - no variance, no CI, no test). The paper has strong package-version pinning and full hyperparameter disclosure (except the mtry grid), which is why this is major rather than critical; but the missing seeds + missing inference + institutional-cloud code together block both exact replication and downstream use.

### Transcript

#### Reviewer (round 1, opus)

```
QUESTION: For a 2024 methods paper proposing a new estimator (PVRF) with g-computation-style treatment contrasts applied to SUCCESS-A, what concrete reproducibility artifacts does the paper commit to? Specifically: (a) is simulation R code posted at a permanent repository with version/commit pinning (not an institutional cloud link that may rot), (b) are exact package versions (randomForestSRC, party/partykit, prodlim, pseudo, etc.) declared, (c) are random seeds fixed for each Monte Carlo scenario and for the SUCCESS-A analysis, (d) are the tuning grids for mtry/ntree/minsplit and the cross-validation procedure fully specified, (e) is a variance-estimation / confidence-interval procedure provided for PVRF predictions and the g-computation contrast, and (f) can the SUCCESS-A analysis be re-derived (patient exclusions, covariate coding, tau selection) from what is in the paper?
```

#### Author (round 1, sonnet)

```
ANSWER: The paper provides partial reproducibility. Pinned: R 4.1.2; pseudo 1.4.3 (for jackknife pseudo-values via pseudomean); ranger 0.15.1 (CART forest); partykit 1.2.20 (conditional inference forest via cforest); simstudy 0.7.1 (DGP); survival 3.5.7 (Cox/Lognormal/Reference); geepack 1.3.9 (GEE); iml 0.11.2 (Shapley values). Hyperparameters: ntree=500 for both forests; CART random forest uses minsplit=5, no leaf or depth restriction, sampling fraction 0.632 without replacement; conditional forest uses minsplit=20, minimum 7 per leaf, same sampling fraction. mtry is 'tuned using five-fold cross validation' for both. Missing: (a) R code is hosted on an institutional cloud URL 'https://www.imbie.uni-bonn.de/cloud/index.php/s/6gmJQmayFAMJZHk', not GitHub/Zenodo; no commit hash, no DOI; (b) random seeds are never stated anywhere in Section 3, Appendix B, or Section 5; (c) the specific mtry grid evaluated in the 5-fold CV is not disclosed; (d) DGP coefficient values delta_j, psi_lm, phi_rs are sampled once from U(-1,1) but 'for the values of the coefficients ... we refer to the R code' -- not tabulated in the paper; (e) no analytic variance or confidence interval for PVRF predictions or the g-computation contrast is provided; (f) SUCCESS-A complete-case exclusion of 102 patients is stated but not characterized (no dropped-vs-retained comparison, no sensitivity analysis).

CITATIONS:
- 'The simulation study and the application were carried out in R, version 4.1.2. Data for the simulation study were generated using the R package simstudy, version 0.7.1. Pseudo values for the RMST ... were calculated using the pseudomean function of the R package pseudo, version 1.4.3. The CART random forest was implemented using the R package ranger, version 0.15.1. The number of trees was set to 500. ... The number of candidate split variables in each node (mtry) was tuned using five-fold cross validation. In each tree, the minimum number of observations required to perform an additional split was set to 5. There were no restrictions on the tree depth and the minimum number of observations in the leaf nodes.' -- Appendix B
- 'The conditional random forest was implemented using cforest function of the R package partykit, version 1.2.20. The number of trees was set to 500. ... In each tree, a minimum of 20 observations was required to perform a split, and each leaf node was required to contain a minimum of 7 observations.' -- Appendix B
- 'The R-code for the simulation study is available at https://www.imbie.uni-bonn.de/cloud/index.php/s/6gmJQmayFAMJZHk.' -- Appendix B
- 'For the values of the coefficients delta_j, psi_lm and phi_rs, we refer to the R code at https://www.imbie.uni-bonn.de/cloud/index.php/s/6gmJQmayFAMJZHk.' -- Section 3
- 'An important topic for future research is the development of hypothesis tests and confidence intervals for PVRF-based RMST differences. ... Confidence intervals for treatment contrasts could, e.g., be constructed using bootstrap methods, along the lines of Hernan & Robins [47], Chapter 13.' -- Section 6
- 'Patients with missing values in any of the considered covariates were excluded from our anaylsis. The analyzed data comprised 3,652 patients.' -- Section 5
```

#### Reviewer (round 2, opus)

```
JUDGMENT: handwaved
REASONING: The Author cited extensive pinning of R version and package versions and specified most hyperparameters, but conceded five reproducibility gaps: (1) no random seeds are fixed or reported anywhere; (2) the mtry tuning grid is not disclosed; (3) the R code is hosted on a University of Bonn institutional cloud (link-rot risk) rather than a permanent repository with commit hash or DOI, and DGP coefficient values live only in that code; (4) no variance estimator or confidence-interval procedure is provided for PVRF predictions or the g-computation contrast -- explicitly deferred to future work; (5) the SUCCESS-A complete-case exclusion of 102 patients is not characterized. For a 2024 methods paper proposing a new estimator applied to a clinical trial (SUCCESS-A), these gaps prevent bit-exact reproduction and any inferential use of the method. Handwaved judgment ordinarily maps to minor, but the combination of missing seeds + missing variance procedure + rot-prone code URL + offloaded DGP coefficients raises severity to major.
NEXT: FINAL
SEVERITY: major
```

#### Moderator (round 2, opus)

```
Signal: Author gave strong positive evidence for versioning/hyperparameters and full concession on seeds/grid/CIs/code hosting. Decision: close lens at severity=major. Reasoning: handwaved -> minor by default, but the missing variance procedure is a structural methodological gap (not just documentation), which forces an upgrade to major. This aligns with the Lens 3 (methodology) finding that variance/CIs are deferred to future work.
```

---
