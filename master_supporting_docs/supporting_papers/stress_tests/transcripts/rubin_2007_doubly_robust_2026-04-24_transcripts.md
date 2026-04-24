# Stress-Test Transcripts: Rubin & van der Laan (2007)

**Paper:** A Doubly Robust Censoring Unbiased Transformation
**Authors:** Daniel Rubin, Mark J. van der Laan
**Year:** 2007, Int. J. Biostat. 3(1), Article 4
**Slug:** `rubin_2007_doubly_robust_2026-04-24`
**Detected type:** new-estimator (depth=2)
**Disposable notebook:** c234d575-d0bf-4e9f-9279-599d22b8e3c8

---

## Lens 0 — data

**Severity:** major
**Finding:** Stanford illustration vulnerable to post-baseline time-dependent confounding; framework conditions only on baseline W.

### Turn 1 — reviewer (Opus, Round 1)
QUESTION: The paper's entire doubly-robust guarantee rests on the baseline conditioning assumption Y ⊥ C | W, yet the proposed transformation is motivated for use in "modern datasets" and the Stanford heart transplant illustration involves post-baseline events (transplant status) that are canonical time-dependent confounders of survival and censoring — so how can the authors justify applying a method that conditions only on fixed baseline W to a setting where the plausible reason C is informative for Y (e.g., sicker patients are both censored sooner and die sooner via post-baseline trajectories) lives entirely in time-dependent covariates the framework formally excludes, and does the paper anywhere acknowledge that silent violation of (1) makes BOTH F-bar and G-bar misspecified in the same direction, collapsing the "double" robustness to zero robustness?

### Turn 2 — author (Sonnet, Round 1)
ANSWER: The paper does not address this. The reviewer's critique — that transplant status is a post-baseline time-dependent confounder making assumption (1) silently violated — is never raised. However, the paper does partially address the logical structure of the concern. In the Stanford illustration (Section 4), the authors invoke domain knowledge: "Because censoring was caused by the end of the study, domain knowledge also suggested that the censoring time distribution did not depend on the age of the subject, and hence that the Kaplan-Meier estimator of the censoring mechanism should have been reliable. Indeed, one can verify that a Cox model for the censoring distribution does not show any significance for age." The single covariate analyzed is age at transplantation. Separately, in the Discussion, the authors do acknowledge in general terms that double robustness cannot rescue violations of (1): "factors other than misspecification of the nuisance parameters... can also contribute to inaccurate regression fits. Such factors might include violations of the i.i.d. assumption or the conditional independence assumption (1)." However, they do not discuss what happens when (1) is violated because of omitted time-dependent covariates, and never acknowledge that such a violation would collapse both nuisance estimates simultaneously.

### Turn 3 — reviewer (Opus, terminal, close_lens_mode)
JUDGMENT: handwaved
REASONING: Author concedes the time-dependent confounding concern is never addressed for the Stanford data, offering only the paper's age-specific domain argument and a generic assumption-(1) caveat that does not engage post-baseline transplant status as the canonical violation mode.
NEXT: FINAL
SEVERITY: major

---

## Lens 1 — estimand

**Severity:** clean
**Finding:** Y is absorbed-notation for any bounded transformation; Theorem 1 fixes τ as explicit assumption; Stanford fixes τ=3.26.

### Turn 1 — reviewer (Opus, Round 1)
QUESTION: What EXACTLY is the regression target E[Y|W] — is Y the raw event time T (in which case E[T|W] is not nonparametrically identified under right censoring without a tail/support assumption, since the Kaplan-Meier mean is undefined past the last observed event), a truncated version min(T, τ) for some pre-specified τ (which the double-robustness theory requires for bounded moments but which the paper never fixes), or an arbitrary transformation φ(T) whose boundedness and measurability conditions are left implicit — and absent an explicit choice, how can any reader verify that E[Y\*_{F,G}(O) | W] = E[Y | W] is even a well-defined equality rather than an equation between two quantities that may both fail to exist?

### Turn 2 — author (Sonnet, Round 1)
ANSWER: Directly resolved. Section 1: "the regression function m(W) = E[Y|W] is often unidentifiable from such observed data... For regression to remain a worthwhile endeavor with right censored data, the response must often first be transformed. We can consider truncating the responses at some value τ and estimating the regression function w → E[Y ∧ τ | W = w]. To simplify notation, we will assume that such transformations have already been incorporated into the response and censoring times Y and C." Theorem 1 imposes: "Assume that Y ≤ τ < ∞ for some τ and that F̄₁(τ|W) = 0 with probability one for some conditional survival function F̄₁(·|W). Suppose further that Ḡ₁(τ|W) ≥ ε > 0 for some ε." Stanford application (eq. 14) fixes target as E[log₁₀(Days of survival) ∧ τ | Age], τ = 3.26. The bounded-support condition ensures E[Y|W] finite; positivity of Ḡ₁ prevents the IPW blow-up the reviewer identifies.

### Turn 3 — reviewer (Opus, Round 2 judgment)
JUDGMENT: cited
REASONING: The Author directly quotes Section 1's truncation convention and Theorem 1's explicit τ assumption (Y ≤ τ < ∞, F̄₁(τ|W)=0, Ḡ₁(τ|W) ≥ ε > 0), plus a concrete τ=3.26 choice in the Stanford application, which collectively pin down the regression target and its identifiability conditions.
NEXT: FINAL
SEVERITY: clean

---

## Lens 2 — identification

**Severity:** minor
**Finding:** Assumption (1) {Y⊥C|W} explicit in intro + Theorem 1; Simulation 3 operationalizes the reviewer's exact concern with V missing from Q but present in G.

### Turn 1 — reviewer (Opus, Round 1)
QUESTION: The DR identity E[Y\*(O)|W] = E[Y|W] presumes conditionally independent censoring C ⊥ T | W — yet the paper frames its assumptions in "random design" language that obscures this. Does the paper explicitly acknowledge that double robustness protects ONLY against misspecification of F-bar or G-bar, and provides NO protection whatsoever when the conditioning set W itself is inadequate (i.e., when an unmeasured covariate induces residual dependence between T and C given W)? If not, the advertised "two chances at validity" is misleading — there is a silent third assumption (correct W) that neither F nor G can rescue, and the Stanford heart transplant application inherits this vulnerability without discussion.

### Turn 2 — author (Sonnet, Round 1)
ANSWER: The paper does treat assumption (1) as explicit, not silent. Section 2 states: "Throughout this work we will also make the standard assumption that the response and censoring time are conditionally independent given the covariates W, or that {Y ⊥ C|W}. (1)" Theorem 1 lists assumption (1) as a precondition. Section 3 (Discussion) acknowledges: "factors other than misspecification of the nuisance parameters in a censoring unbiased transformation can also contribute to inaccurate regression fits. Such factors might include violations of the i.i.d. assumption or the conditional independence assumption (1)." Most decisively, Simulation 3 operationalizes the reviewer's concern: the true independence is {Y ⊥ C | W, V}, and when V is omitted from Q but retained in G, the DR mapping still yields accurate fits because the censoring model correctly includes V. The Stanford application remains vulnerable as the reviewer says (no sensitivity analysis), but this is an incompleteness of the application, not concealment of the assumption.

### Turn 3 — reviewer (Opus, terminal)
JUDGMENT: cited
REASONING: The author cites assumption (1) verbatim from intro and Theorem 1, quotes the discussion's explicit acknowledgment of its violation as a failure mode, and points to Simulation 3 (eq 12) which operationalizes the exact reviewer concern by showing DR recovers when V is omitted from Q but retained in G.
NEXT: FINAL
SEVERITY: minor

---

## Lens 3 — methodology

**Severity:** major
**Finding:** No rate conditions, no Donsker/entropy, no cross-fitting, no efficient-IF. Conditional-mean identity is proved; downstream smoother asymptotics are not.

### Turn 1 — reviewer (Opus, Round 1)
QUESTION: The paper's "double robustness" is a property of the transformation identity E[Y\* | X] = E[Y | X] when either F-bar or G-bar is correct — but for the downstream cubic smoothing spline (or any adaptive smoother) fit to Ŷ\* to inherit a meaningful convergence rate, the plug-in nuisance estimators F̂ and Ĝ must converge fast enough that their product bias is negligible relative to the smoother's variance; what explicit rate conditions (e.g., n^(-1/4) product-rate à la Robins–Rotnitzky, or Donsker/entropy conditions) does the paper impose on F̂ and Ĝ, and if the paper is silent on rates while simultaneously disavowing parametric survival models for F, how can the authors claim the spline fit to Ŷ\* is consistent — let alone efficient — without either (i) a concrete rate theorem, (ii) sample splitting/cross-fitting to control empirical process terms, or (iii) a semiparametric efficiency-bound argument showing Ŷ\* corresponds to the efficient influence function rather than just one algebraically convenient member of the CUT family?

### Turn 2 — author (Sonnet, Round 1)
ANSWER: The reviewer identifies a genuine gap the paper does not hide. The authors explicitly state they have not derived the asymptotic theory: Discussion section: "We have not derived consistency, rates of convergence, or the distribution theory for specific estimators based on our censoring unbiased transformation. As with previous transformations, performance will depend on the nuisance parameter estimates and full data algorithm into which we plug the imputed responses." No rate conditions, no Donsker/entropy, no sample splitting, no efficient-IF argument. The paper's theoretical claim is narrow: "The theoretical novelty in our work lies in the result that the doubly robust mapping Y\*_{F̄₁,Ḡ₁}(O) not only has the correct mean if one of F̄₁(·|W) or Ḡ₁(·|W) is correctly specified as in (9), but also the correct conditional mean given observed covariates as in (2)." A conditional-mean identity, not an efficiency statement. The spline suggestion is a practical recommendation whose formal asymptotics are deferred: "adaptive smoothing techniques would ideally still be able to estimate the regression function with imputed response data."

### Turn 3 — reviewer (Opus, Round 2 judgment)
JUDGMENT: conceded
REASONING: The author openly admits the paper derives no rate conditions, no Donsker/entropy assumptions, no sample splitting, and no efficiency theory, defending only the narrow conditional-mean identity — an honest concession that leaves the downstream smoother's consistency and rate behavior formally unsupported, which is a major (not critical) gap given that the identity itself is correctly established.
NEXT: FINAL
SEVERITY: major

---

## Lens 4 — overclaims

**Severity:** minor
**Finding:** Paper runs symmetric misspecification scenarios; explicit caveats about outlier risk and two-nuisance burden; does NOT use "dominance" language.

### Turn 1 — reviewer (Opus, Round 1)
QUESTION: Your simulation claim that the DR-IPCW transformation "dominates" Buckley-James and standard IPCW rests on scenarios where either the censoring model G or the conditional failure-time model F (or both) is misspecified in ways that maximally penalize the single-robust competitors while the DR estimator's nuisance pair is configured to exploit exactly that misspecification pattern — so (a) quantify the dominance margin in MSE at realistic sample sizes (n=100, 200) rather than asymptotically, (b) show the results when the competitor's nuisance is correctly specified and yours is not (the symmetric stress test), and (c) justify why, in the known finite-sample regime where the augmentation term inflates variance when F is poorly estimated, you present DR as unambiguously superior rather than as a bias-variance tradeoff — absent these, the "dominance" claim is a straw-man built on hand-picked misspecification, not evidence of a practically better estimator.

### Turn 2 — author (Sonnet, Round 1)
ANSWER: The "straw-man" charge misreads the paper. (a) The paper never uses the word "dominance"; comparisons are VISUAL at n=200 and n=400. (b) The symmetric stress test IS in the paper. Simulation 2 (n=200, mech. 11): G depends on W, marginal KM for G is misspecified; BJ (correct Q) and DR work, IPCW "behaved erratically" — DR's G-arm is wrong yet it succeeds. Simulation 3 (n=400, mech. 12): G correct, Q misspecified by ignoring V; IPCW and DR succeed, BJ "led to a severe underestimate of this line" — DR's Q-arm is wrong yet it succeeds. Both off-diagonal cells covered. (c) Paper explicitly disclaims unambiguous superiority: "While the censoring unbiased transformation introduced in this work has the advantage of double robustness, we do not mean to suggest that it should be favorable to existing transformations in all nonparametric regression problems. Like the IPCW transformation but unlike the Buckley-James transformation, the method depends on inverse weighting by the censoring mechanism Ḡ(·|W), which can lead to outlier problems if inverse weighting by a small quantity." Also: "can be more complicated to implement than traditionally used censoring unbiased transformations, because it necessitates two nuisance parameter estimates instead of one."

### Turn 3 — reviewer (Opus, terminal)
JUDGMENT: cited
REASONING: Author's defense is paper-grounded — symmetric misspecification (Sims 2 and 3) is documented, explicit caveats against unambiguous superiority and outlier risks from inverse weighting appear in the text, and "dominance" language is absent; only residual quibble is that numeric MSE tables with Monte Carlo SEs would be stronger than visual curves at n=200/400.
NEXT: FINAL
SEVERITY: minor

---

## Lens 5 — alternatives

**Severity:** clean
**Finding:** k chosen by Buckley-James LOO-CV then reused for DR-CUT — tuning asymmetry favors BJ, not DR.

### Turn 1 — reviewer (Opus, Round 1)
QUESTION: In the simulations where DR-CUT outperforms Buckley-James and IPCW, is the advantage genuinely attributable to double robustness, or is it confounded by asymmetric tuning effort — i.e., did the authors optimize bandwidth/smoother hyperparameters for the DR nuisance estimators while leaving Buckley-James and IPCW at default settings, such that any competing method given equivalent tuning budget would close the gap?

### Turn 2 — author (Sonnet, Round 1)
ANSWER: The tuning asymmetry runs in the OPPOSITE direction. Section 3: "we chose the number of nearest neighbors k by implementing the Buckley-James transformation for each k ≤ n−1 ... evaluated the squared error leave-one-out cross-validation criterion for the smooth.spline() regression fit to this data, and selected the k minimizing this criterion." The same k — chosen to minimize Buckley-James error — is reused without adjustment for DR-CUT. DR-CUT receives Buckley-James-tuned nuisance parameters, not preferentially-tuned ones. A single identical smooth.spline is applied to all three imputed datasets. If anything, Buckley-James had the tuning advantage.

### Turn 3 — reviewer (Opus, terminal)
JUDGMENT: cited
REASONING: The paper explicitly specifies that k is selected by minimizing the Buckley-James LOO-CV criterion and then reused verbatim for DR-CUT, so any tuning asymmetry favors BJ rather than DR-CUT, directly refuting the confounding concern.
NEXT: FINAL
SEVERITY: clean

---

## Lens 6 — generalizability

**Severity:** minor
**Finding:** Scope is right-censored scalar Y only; competing risks, recurrent events, counting-process response deferred to companion papers.

### Turn 1 — reviewer (Opus, Round 1)
QUESTION: [Three-part challenge] (i) when failure arises from one of K causes and the target is a cause-specific cumulative incidence F_k(t|W), does the Y=T formulation collapse cause information? (ii) in recurrent-event data where the response is a counting process N(t), what is the DR-CUT replacement? (iii) is DR-CUT a general censored-data estimator, or functionally a right-censored scalar-outcome estimator whose generalizability claims outrun its proofs?

### Turn 2 — author (Sonnet, Round 1)
ANSWER: All three are honest concessions. (i) Observed data is O=(W, Δ=1(Y≤C), Ỹ=Y∧C); no cause indicator, no subdistribution. Target is scalar m(w)=E[Y|W=w]. Competing risks not modeled. (ii) Y is scalar (possibly log-transformed or truncated); transformation operates on Y∧C. Counting-process N(t) has no replacement in the paper. (iii) The paper acknowledges this boundary: "Doubly robust censoring unbiased transformations can be utilized for more general types of censored responses than arise in the right censored data structure. Rubin and van der Laan (2006) discuss the applicability of such imputation schemes to regression problems with missing responses, in causal inference problems, and with current status data, and give an abstract treatment of double robustness for more general censored data structures." Distributional theory also deferred: "We have not derived consistency, rates of convergence, or the distribution theory..." General machinery belongs to vdL & Robins (2003) monograph chapter 3.

### Turn 3 — reviewer (Opus, Round 2 judgment)
JUDGMENT: conceded
REASONING: Author openly concedes the paper is scoped to single-event right-censored scalar outcomes and explicitly defers competing-risks, recurrent-events, and general censored-data structures to Rubin & van der Laan (2006) and van der Laan & Robins (2003), so the scope is honestly stated even if narrow relative to real-world survival applications.
NEXT: FINAL
SEVERITY: minor

---

## Lens 7 — positioning

**Severity:** major
**Finding:** Andersen-Klein-Rosthoj (2003) pseudo-observations predate paper by 4 years with parallel conditional-expectation identity — not cited anywhere.

### Turn 1 — reviewer (Opus, Round 1, notebooks=[disposable, thematic])
QUESTION: Your paper presents two novelties: (i) a conditional-expectation upgrade of the van der Laan-Robins (2003) marginal DR identity, and (ii) plug-in use of the DR-CUT mapping for adaptive smoothers. Both claims sit in a crowded pre-2007 neighborhood, and the paper must distinguish itself from each neighbor — not just cite them. (a) Andersen, Klein & Rosthoj (2003) pseudo-observations already deliver an impute-then-smooth transformation whose conditional expectation equals the target conditional expectation up to a remainder term... What does DR-CUT deliver that a covariate-stratified / IPCW-augmented pseudo-observation cannot? (b) Bang & Robins (2005) already provide doubly-robust moment equations for censored and missing-data models that are routinely interpreted conditionally on covariates within sub-populations — so your "conditional-expectation upgrade" is at best a re-expression, not a new identity. (c) The Koul-Susarla-Van Ryzin (1981) and Leurgans (1987) synthetic-data transformations are explicit pre-existing CUTs; your paper reads as "Leurgans/KSV + augmentation term." Quantify the incremental contribution.

THEMATIC_FINDINGS: Thematic notebook returned substantive positioning evidence. Verbatim: "Both pseudo-observations and CUTs serve to bridge the gap between complex censored survival data and standard regression techniques. Both methods operate by first replacing the incompletely observed, right-censored survival times with continuous surrogate values..." On pseudo-observations' conditional-expectation property parallel to the paper's headline identity, Andersen et al. (2003, 2004) established: "E[PO_i^tau(t) | R_i(t)=1, Z_i(t)] = E[min{T_i(t), tau} | R_i(t)=1, Z_i(t)]." Jacobsen & Martinussen (2016) and Overgaard et al. (2017) formalized this as a conditional-expectation identity "up to a remainder term." CUT lineage predating 2007: Koul-Susarla-Van Ryzin (1981), Leurgans (1987), Zhou (1992). DR: Bang & Robins (2005) foundational. Steingrimsson et al. (2016) built survival forests "by applying doubly robust estimating equations directly to the transformed loss functions." The paper is squeezed between (i) Bang-Robins DR moments, (ii) Andersen-Klein-Rosthoj pseudo-observations, and (iii) KSV/Leurgans synthetic-data tradition.

### Turn 2 — author (Sonnet, Round 1, notebooks=[disposable])
ANSWER: (a) Pseudo-observations are NEVER cited in the paper. Andersen-Klein-Rosthoj not in reference list. (b) Bang & Robins (2005) not cited. But the paper explicitly locates its contribution vs. vdL-Robins (2003) and vdL-Dudoit (2003), naming the gap: "Theorem 2.1 of van der Laan and Robins implies the weaker form of (8)" — marginal only. Paper claims: "The theoretical novelty in our work lies in the result that the doubly robust mapping ... not only has the correct mean if one of F̄₁(·|W) or Ḡ₁(·|W) is correctly specified as in (9), but also the correct conditional mean given observed covariates as in (2)." (c) KSV and Leurgans ARE explicitly cited and placed in Fan-Gijbels (1994) taxonomy: IPCW is α=−1 (KSV), Leurgans is α=0. Contribution characterized as: "The Buckley-James and IPCW transformations put all of their eggs in one basket. The doubly robust transformation can be applied whenever either ... has been solved ... and is in this sense a superior censoring unbiased transformation."

### Turn 3 — reviewer (Opus, Round 2 CONFRONTATION, notebooks=[disposable, thematic])
CONFRONTATION: Andersen, Klein & Rosthoj (2003, Biometrika 90:15-27) — published four years PRIOR to this paper — introduce pseudo-observations satisfying E[PO | R(t)=1, Z(t)] = E[min{T(t),τ} | R(t)=1, Z(t)], a CONDITIONAL-expectation identity directly parallel to the paper's headline (8), later formalized as a conditional-expectation identity "up to remainder term" by Jacobsen & Martinussen (2016) and Overgaard, Parner & Pedersen (2017). The Author's defense concedes the paper neither cites nor discusses this literature, which means the claimed "theoretical novelty" of upgrading from marginal E[Y\*(O)]=E[Y] (vdL-Robins 2003) to conditional E[Y\*(O)|Z]=E[Y|Z] was already instantiated — with the same impute-then-smooth architecture — in a widely-circulated Biometrika paper predating this manuscript. Citing only the weaker vdL-Robins 2003 marginal result while omitting the contemporaneous conditional-identity construction of Andersen et al. is a material positioning omission, not a re-expression quibble. The positioning claim does not survive this precedent.

### Turn 4 — author (Sonnet, Round 2 defense, notebooks=[disposable])
ANSWER: The paper does not cite Andersen, Klein, or Rosthoj anywhere in its text, and the 2003 Biometrika pseudo-observations paper is entirely absent from its reference list. The paper likewise never discusses pseudo-observations or jackknife pseudo-values as a concept — its imputation machinery is a doubly robust censoring unbiased transformation (CUT), replacing censored responses with surrogates computed from estimated nuisance functions F̄(·|W) and Ḡ(·|W), not from leave-one-out jackknife residuals. The only 2003-vintage citations in the reference list are van der Laan & Dudoit (2003, UC Berkeley Biostatistics Working Paper 130) and van der Laan & Robins (2003, Springer-Verlag) — confirming no engagement with the Biometrika pseudo-observation literature.

### Turn 5 — reviewer (Opus, terminal)
JUDGMENT: conceded
REASONING: Author explicitly acknowledged the paper does not cite Andersen, Klein & Rosthoj (2003) anywhere and does not engage with the pseudo-observation literature, despite that prior work establishing a parallel conditional-expectation identity for the same impute-then-smooth architecture four years earlier in Biometrika.
NEXT: FINAL
SEVERITY: major

---

## Lens 8 — reproducibility

**Severity:** minor
**Finding:** Math + DGPs + tuning + Stanford filters all specified. Missing: MC replicate count, MC standard errors, seed. Single-run visual plots only.

### Turn 1 — reviewer (Opus, Round 1)
QUESTION: Can a reader reproduce the doubly robust transformation Y\*_{F,G}(O) from the paper alone — specifically, do you provide (a) an explicit algorithm box or pseudocode for evaluating the conditional-expectation integral E_F[D(u) | T > u] that defines the DR mapping given plug-in F̂ and Ĝ, (b) the exact simulation DGP for the MSE comparisons (error distribution, censoring hazard, sample size, number of replicates, Monte Carlo SEs, seed), and (c) for the Stanford heart transplant illustration, the covariate set, the F̂/Ĝ fitting procedures, and any tuning choices — or must the reader reverse-engineer all three to replicate your reported MSE advantages?

### Turn 2 — author (Sonnet, Round 1)
ANSWER: (a) No boxed algorithm, but equation (7) gives closed-form Y\*(O), equation (4) defines Q integral, and Section 3 gives the nearest-neighbor Q estimator prose: "We estimated Q(w,y) by taking the mean of the k uncensored responses greater than y, whose covariate value W was closest to w." Tuning: "we chose the number of nearest neighbors k by implementing the Buckley-James transformation for each k ≤ n−1 ... selected the k minimizing this criterion." smooth.spline() named. Determined reader can implement. (b) DGPs explicit: Sim 2 (eq 11): W~U(0,1), ε~2(Beta(4,4)−1/2), {C|W≤1/2}=+∞, {C|W>1/2}~exp(1)−1, Y=W+ε, n=200. Sim 3 (eq 12): W~U(0,1), V~Bernoulli(1/2), similar, n=400. Censoring rates reported (52%, 44%, 51%, 52%, 38%, 32%). GENUINE GAP: no MC replicate count, no MC SEs, no seed. Single-run visual plots. (c) Stanford: 157 patients (55 censored, tissue-type filter), log₁₀(days) scale, τ=3.26, k=6 for Q-hat, G-hat = marginal KM (ignoring age).

### Turn 3 — reviewer (Opus, terminal)
JUDGMENT: handwaved
REASONING: Math, DGPs, tuning, and Stanford filters are fully specified and reimplementable in principle, but single-run visual plots with no seed, no MC replicate count, and no tabulated MSE ± SE mean the reported figures cannot be exactly matched without guessing — a real but bounded gap by 2007 norms.
NEXT: FINAL
SEVERITY: minor

---

## Run metadata

- Total subagent spawns: 21 (1 classification + 8 Reviewer R1 + 8 Author R1 + 3 Reviewer R2 + 1 Author R2 + classification-free terminals captured inline)
- Lens 7 novelty-check: skipped (paper published 2007; thematic-notebook triangulation used instead)
- Phase sequence: 0 (input) → 1 (notebook + upload) → 2 (classify + plan) → 3 (lens loop, flat dispatch) → 4 (synthesis) → 5 (artifacts) → 6 (cleanup)
