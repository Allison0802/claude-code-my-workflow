# Stress-Test Briefing: Semiparametric estimation of the proportional rates model for recurrent events data with missing event category

**Authors:** Feng-Chang Lin, Jianwen Cai, Jason P Fine, Elisabeth P Dellon, Charles R Esther
**Year:** 2021
**Source:** *Statistical Methods in Medical Research* 30(7):1624–1639. DOI: 10.1177/09622802211023975
**Local path:** `Missing Types/Papers/Semiparametric estimation of the proportional rates model for recurrent.pdf`
**Stress-test date:** 2026-04-23
**Detected paper type:** new-estimator
**Depth:** 2 (heavy on Lenses 1, 3, 6, 7)
**Reviewer model:** claude-opus-4-7 (one-shot Reviewer per lens, direct NotebookLM querying)
**Thematic notebook:** ML for Recurrent Events

---

## TL;DR verdict

**BUILD ON — with explicit flags.** This paper is the direct source of the **RPM (rate-proportion-method) imputation** that sits in your Missing Types subproject's 5-method menu (CCA / IPW / IPW-RF / **RPM** / DR). The core technical contribution — the rate-proportion identity log{p_ij(t)/p_iJ(t)} = β₀ᵀX_ij(t) + g_0j(t) under proportional rates, plus a √n theorem with plug-in variance correction for nuisance B-spline error — is sound under the paper's stated conditions. Coverage (94.6–96.7% at n=200) and the Taylor-expansion derivation in Appendix A are defensible.

However the paper has **seven major defects and one critical gap** that a hostile referee finds immediately, and that you should inherit as explicit caveats in your RPM implementation and in any dissertation chapter that leans on this method:

| | Defect | Your risk |
|---|---|---|
| 1 | "Never been explored" novelty claim is directly falsified by the paper's own ref [7] (Ye/Zhao/Sun 2015, a semiparametric additive rates model for the same problem) and uncited Ma (2018) on the same CFFPR cohort | You inherit the faulty positioning if you cite Lin (2021) as the RPM origin without triangulating |
| 2 | The "MAR" assumption is strictly stronger than MAR — π_ij(t\|Z) does not depend on j is conditional independence of missingness and type given (t,Z) | Your simulations need to label this "type-independent MAR" or "stratified MAR", not just "MAR" |
| 3 | **CRITICAL: External-validity gap.** Simulations are J=2, n≤400, one Bernoulli covariate, independent U(0,5) censoring; the CF application is J=3 (with a fabricated composite class), n=14,888, 188 clustered sites, multi-level covariates, plausibly informative dropout. No simulation ever matches the deployed regime | Your simulations at J=3, larger n, time-varying covariates, and realistic censoring *are* the missing validation — this is actually a competitive advantage for your dissertation |
| 4 | Efficiency gain over Schaubel-Cai (1.09–1.20 MSE ratio) is conditional on an adversarially misspecified linear-in-t logistic competitor against h₀(t) = exp{-sin(t/3) - 3cos(3t)}; ratio collapses to 0.99–1.00 under correct specification | Do not cite "significant efficiency improvement" unqualified — your comparisons page must flag this |
| 5 | B-spline knot count m never disclosed/sensitized; theoretical rate condition n^{1/(4+2ν)} < m < n^{1/4} asserted but never verified | Your simulations should fix m explicitly, vary it, and report the sensitivity |
| 6 | Variance formula is valid but single-robust (no Neyman-orthogonality, no double robustness) — paper concedes this as future work | Your DR method (item 5 in the Missing Types menu) is the natural next step; cite RPM as the single-robust baseline |
| 7 | No code, no seeds, no package; CFFPR access + variable definitions opaque | You had to reimplement from scratch; document your implementation as the reference artifact |
| 8 | MNAR simulation results suppressed ("we do not report the results here"); sensitivity sweeps γ ∈ [-1.5, 1.5] as a constant, not as a function of (t,Z) | Do not rely on Lin 2021's "MNAR robustness" claim in your own chapter |

---

## Top 5 killer questions

1. **(Positioning — Lens 7)** The paper cites Ye/Zhao/Sun 2015 (ref [7], *Computational Statistics & Data Analysis*) whose title contains *"A semiparametric additive rates model for multivariate recurrent events with missing event categories,"* yet simultaneously claims *"a semiparametric framework for the estimation of p_ij(t) otherwise has never been explored."* Which is wrong: the title of ref [7], or the novelty sentence? And why are Ma et al. (2018, *Biometrics*, GART/IPW on the same CFFPR cohort) and **your own** Lin-Cai-Deng-Esther (2021a, *Statistics in Medicine*, IPW on the same data) both uncited?

2. **(Identification — Lens 2)** Your missingness assumption π_ij(t|Z_ij) = π_i(t|Z_ij) (independence of j) is strictly stronger than MAR. The rate-proportion log-odds identity (eq. 5) loses a γ_j(t|Z) term that is confounded with g_0j(t) the moment missingness depends on type. Your "robustness" evidence sweeps γ as a *constant* in [-1.5, 1.5] — a 4.5× odds ratio that is modest by MNAR standards — and never perturbs the t- or Z-dependent direction where identifiability actually fails. Produce the suppressed MNAR simulation tables, or retract the robustness claim.

3. **(Generalizability — Lens 6, CRITICAL)** The CF application is J=3 (with a *fabricated* third "both nonmucoid+mucoid" class to satisfy mutual exclusivity), n=14,888, 188 clustered sites, continuous and multi-level covariates, and clinically informative dropout. None of these appear in the simulation grid (J=2, n≤400, one binary covariate, independent U(0,5) censoring). The reported CFFPR coefficients are not validated — they are extrapolations beyond the tested envelope. Produce at least one simulation matching the CF regime on three of these axes, or concede.

4. **(Methodology — Lens 3)** If you re-run Scenario 2 but give the Schaubel-Cai comparator a natural cubic spline in t (the standard defensive move any biostatistician would make before concluding "my parametric model is misspecified"), does the 1.09–1.20 MSE advantage survive, or collapse to the 0.99–1.00 ratios seen in Scenario 1? The headline efficiency claim rests on a pre-rigged linear-in-t competitor against a sin+cos nuisance truth.

5. **(Reproducibility + Methodology — Lenses 3, 8)** What knot count m did the simulations actually use, how placed, with what basis, what optimizer, and what seeds? Coverage of 95.2–96.4% in Table 2 is unverifiable without these. Theorem 1 requires m to sit in the band n^{1/(4+2ν)} < m < n^{1/4} — at n=200 with ν=2, that is m between roughly 2 and 3. Does coverage stay nominal at m=0, 1, 2, 3? If m-sensitivity exists, AIC-driven choice in the application needs a stability check the paper does not provide.

---

## Novelty check (external LLM search)

**Score:** 6/10 — **PROCEED WITH CAUTION**

**Key differentiator (genuine novelty):** The specific theoretical insight that under a proportional rates model the log-odds of event type reduces to a generalized partially linear model — exploiting rate proportionality to derive a clean log-linear structure in the baseline — is a precise and novel contribution. No prior paper in the recurrent-events missing-type literature had explicitly derived this connection or used it to build a semiparametric imputation framework within the proportional rates model class *specifically*.

**Closest prior work (and how Lin et al. differentiates):**

| Paper | Year | Venue | Overlap | Key Difference |
|-------|------|-------|---------|----------------|
| Schaubel & Cai | 2006a | *Canadian J. Statistics* | MI for recurrent events with missing category, proportional rates/means | Parametric multinomial logit for event-type; Lin makes it semiparametric |
| Schaubel & Cai | 2006b | *Scand. J. Statistics* | Rate/mean regression, multi-sequence, missing category | Multi-sequence extension; parametric event-type |
| Ye/Zhao/Sun et al. | 2015 | *Comp. Stat. Data Anal.* | **Semiparametric** additive rates for multi-type recurrent events with missing types | Additive (not proportional) rate model; estimating equations (not likelihood). **Misrepresented by Lin as "parametric."** |
| Ma et al. | 2018 | *Biometrics* | GART with IPW/projection on **same CFFPR data** | AFT-type (not proportional rates). **Not cited by Lin.** |
| Lin, Cai, Deng, Esther | 2021a | *Stat. Medicine* | IPW for recurrent events with missing category on **same CFFPR data** | IPW only (no semiparametric event-type model). **Not cited by Lin 2021b despite same authors and same cohort.** |

**Risk:** The "never been explored" sentence is demonstrably false. The correct framing is: "We are the first to exploit rate proportionality to derive that the event-type log-odds follows a generalized partially linear model *intrinsically*, without imposing a separate semiparametric missingness model (as in Ye/Sun 2015) or a different rate-model class (additive, AFT)."

---

## Severity summary

| Lens | Name | Weight | Depth | Severity |
|------|------|--------|-------|----------|
| 0 | data | medium | 1 | major |
| 1 | estimand | heavy | 2 | major |
| 2 | identification | medium | 1 | major |
| 3 | methodology | heavy | 2 | major |
| 4 | overclaims | medium | 1 | major |
| 5 | alternatives | light | 1 | major |
| 6 | generalizability | heavy | 2 | **critical** |
| 7 | positioning | heavy | 2 | major |
| 8 | reproducibility | medium | 1 | major |

**Totals:** critical = 1, major = 8, minor = 0, clean = 0.

---

## Per-lens findings

### Lens 0 — Data structure & characteristics (major)

**Key gap:** Simulations are J=2; application is J=3 with a *manufactured* composite class ("both nonmucoid and mucoid positive at same visit," 5,445 events, ~12% of events) to dodge the mutual-exclusivity assumption. MAR logistic-model justification and κ ∈ [-1.5, 1.5] MNAR sweep in the application are reasonable; the J mismatch and the ad-hoc third-class construction are real holes.

**Paper quotes:** Simulation — "two types of recurrent events were simulated from two intensity functions sharing the same latent variable G_i... 1.2–1.4 total number of events on average." Application — "Since our method assumes two kinds of events cannot occur simultaneously, we treated those visits with both infections as the third type of recurrent event."

### Lens 1 — Estimand clarity (major)

**Key gap:** β₀ is defined on the full-data counting process N*_ij; the bridge to observed data N_ij runs through γ_j(t|Z_ij) = 0 asserted by citation only ("we adopt the same assumption"). No formal identification theorem of the form "under MAR + regularity, β₀ is identified from the observed-data law." The paper's own concession that "β in model (4) may not be fully identifiable" when covariates share effects across categories is real — the reader must take on faith that contrast-only identification suffices for p_ij(t) consistency.

**Paper quote:** "A common assumption in the previous literature is that π_ij(t|Z_ij) does not depend on j and γ_j(t|Z_ij) = 0 for each j. This assumption corresponds to missing at random (MAR) assumption when the missingness does not depend on unobserved information. In this paper, we adopt the same assumption and assume γ_j(t|Z_ij) = 0."

### Lens 2 — Identification assumptions (major)

**Key gap:** The "MAR" framing is misleading. The paper's assumption — π_ij(t|Z_ij) does not depend on j — is strictly stronger than MAR; it is type-independent-missingness-given-(t,Z), essentially MCAR-in-j conditional on (t,Z). Genuine MAR permits π to depend on (t, Z, j) through observed data. The rate-proportion identity fails under genuine MAR. Separately, the B-spline parameterization g_0j(t;η_j) = η_j0 + Σ_k η_jk b_k(t) with a cubic basis satisfying Σ b_k(t) = 1 is overparameterized (intercept confounded with constant component of the spline) — no sum-to-zero, no boundary, no dropped-basis constraint stated. Condition (d) positive-definite Hessian is asserted but its verification in finite samples is not discussed.

### Lens 3 — Statistical methodology (major)

**Split verdict:** (a) The plug-in variance correction — the C(β,θ)H(θ)⁻¹U_ij(θ) influence-function term — *is* a proper first-order correction for B-spline nuisance error, and the coverage in Table 2 (94.6–96.7%) backs the asymptotics. Variance derivation is clean. (b) But three methodology-adjacent issues remain: no simulation-side sensitivity to knot count m (required by Theorem 1's n^{1/(4+2ν)} < m < n^{1/4} rate condition); the Schaubel-Cai "straw-man" comparator (linear-t logistic vs. sin+cos truth) predetermines the efficiency result; no initial-value / convergence / boundary-case numerics are reported. Scenario 1 (both correctly specified) shows near-identical MSE — the 0.99–1.00 ratios are the honest number.

### Lens 4 — Overclaims vs. evidence (major)

**Split:** The √n theorem with sandwich variance is cited and honest. But (a) the printed novelty sentence is directly contradicted by the paper's own ref [7] (Ye/Zhao/Sun 2015); (b) Ma (2018) on same CFFPR application is uncited; (c) MNAR "robustness" rests on suppressed simulation results ("we do not report the results here") + one supplementary real-data exercise; (d) efficiency rhetoric does not flag that the gain disappears under correct specification.

### Lens 5 — Alternative explanations (major)

**Core gap:** The paper's "significant efficiency improvement" rests on a single rigged head-to-head. The obvious defensive move for any Schaubel-Cai user — put a cubic spline in t inside the logistic p_ij(t) model — is not tested. An intermediate "flexibly parametric" comparator would likely close most of the reported gap. Separately, a *parametric MI* method is never actually benchmarked despite being named in the rhetoric.

### Lens 6 — Generalizability (CRITICAL)

**The deepest problem.** Tested envelope vs. deployed envelope is non-overlapping on multiple axes:

| Axis | Simulation | Application |
|------|-----------|-------------|
| J (event types) | 2 | 3 (with composite class) |
| n | 200, 400 | 14,888 |
| covariates | 1 Bernoulli(0.5) | ≥5 multi-level + continuous |
| clustering | none | 188 sites |
| censoring | independent U(0,5) | plausibly informative (death, transplant) |
| time-varying | not simulated | theoretically allowed |
| events/subject | 1.2–1.4 | 2.6+ |
| MNAR | results suppressed | γ ∈ [-1.5, 1.5] sweep |
| knot count m | unreported | AIC: 0 knots in CF |

The CFFPR coefficient estimates are *not* validated by the simulation — they are extrapolations. This is a critical external-validity gap.

### Lens 7 — Positioning (major, triangulated)

Three independent sources (disposable notebook, thematic notebook, external novelty-check) converge: positioning is not defensible as written. Key finding beyond the novelty-check: the paper **cites Ye/Zhao/Sun 2015 but mischaracterizes it as "parametric multinomial logit"** — a demonstrable misstatement of a same-bibliography paper's method class. This is worse than omission. Plus Ma 2018 and the authors' own Lin-Cai-Deng-Esther 2021a are uncited despite being on the same CFFPR cohort. Thematic corpus also surfaces a missing-cause IPW/AIPW/double-robustness line (Lu-Tsiatis 2001, Ogino 2018, Wang-Lee-Ogino 2024) that the paper's "robust to misspecification" motivation ignores.

### Lens 8 — Reproducibility (major)

Fails on all three axes simultaneously: (a) no code, no repo, no software named; (b) simulation knots m, seeds, basis, optimizer, initial values not reported; (c) CFFPR data access pipeline opaque, "medication use for chronic PA infections" definition not given, "diagnostic method" groupings deferred to Lai et al. (2004). Bordering on critical for simulation reproducibility, stopping short only because the generative DGP is fully written out and *in principle* the pipeline could be rebuilt.

---

## Skipped lenses

None. All 9 lenses ran with positive depth.

---

## Relevance to your sub-projects

### Missing Types subproject (direct, high-relevance)

This paper is the **direct source of the RPM method** in your 5-method imputation menu (CCA / IPW / IPW-RF / **RPM** / DR). Your local copy lives under `Missing Types/Papers/`. Treat it as the canonical citation for rate-proportion-model imputation — but **not** as the authoritative account of its limits. Your own simulation grid already extends beyond the paper's tested envelope on multiple axes (J, n, covariate complexity), which means your dissertation chapter that includes RPM is in a position to make four claims Lin et al. cannot:

1. **RPM's behavior at J=3 and larger n** — you can fill the generalizability gap the paper explicitly leaves open (Lens 6, critical).
2. **RPM under genuine MAR (not type-independent MAR)** — if your missingness DGP has π depending on j, you will observe the identification failure Lin et al. never probe (Lens 2).
3. **RPM under informative censoring** — not touched by Lin et al.
4. **RPM's variance/coverage when knot count m is stressed** — the simulation-side sensitivity Lin omits (Lens 3).

Your DR method is the natural answer to Lin 2021's own "future work" — Neyman-orthogonal / double-robust variance correction. Cite Lin 2021 as the single-robust baseline and your DR as the next step.

**Code gap:** You had to reimplement RPM from scratch because no code was released with Lin 2021 (Lens 8). Document your implementation (knot count, seeds, optimizer, initial values) as the *de facto* reference artifact — this is a small but durable contribution.

**Positioning risk (Lens 7):** if you cite Lin 2021 for RPM without also citing Ye/Zhao/Sun 2015 (semiparametric additive rates, directly related) and Ma et al. 2018 (GART on same CFFPR cohort), a hostile reviewer will catch you the way we caught Lin et al. Add both to your bibliography now.

### Comparisons subproject (indirect, methodological-inspiration)

The paper's simulation grid (J=2, n≤400, one binary covariate) is a useful *baseline* for your 37-scenario comparisons grid — but only as the minimum-complexity corner. Your existing grid with frailty × complexity × correlation × censoring axes is already more demanding than this paper's grid. The B-spline knot-sensitivity gap (Lens 3) is a general lesson: whenever you report nominal coverage for any semiparametric method in the comparisons framework, fix m explicitly, vary it, and report the result.

### CARRA / cross-project

The "MAR assumption is actually stronger-than-MAR" critique (Lens 2) applies to any CARRA analysis that uses a single-stratum missingness model without explicit j-independence justification. If your CARRA missing-types branch uses RPM-style imputation, the identification caveat should appear in the methods section.

---

## Recommendation

**BUILD ON WITH FLAGS — cite as RPM source; inherit critique as dissertation contribution.**

### Rationale

- **Build on** rather than *cite* alone: your Missing Types subproject is in direct methodological descent from this paper (RPM = rate-proportion-model, Lin 2021's core construction). You are not a downstream user; you are a methodological continuation.
- **With flags** because the paper has 1 critical + 8 major defects that a hostile referee surfaces immediately. Silently adopting RPM with Lin 2021's framing inherits the defects; flagging them makes your chapter the stronger artifact.
- **Not *flag***: the paper is not a cite-and-warn on shaky grounds. The core √n result and variance correction are valid under the stated (overly strong) assumptions; the quantitative CF results, while unvalidated by simulation, are not wrong in the sense of mathematical error.
- **Not *skip***: skipping would sever your bibliography's link to the direct predecessor and invite the same positioning critique we just made of Lin et al.

### Concrete actions

1. Add to `Missing Types/Bibliography_base.bib`: Lin et al. (2021) + Ye/Zhao/Sun (2015) + Ma et al. (2018) + Schaubel-Cai (2006a,b) + Lin-Cai-Deng-Esther (2021a IPW). If any are already there, verify.
2. In the Missing Types methods chapter, when introducing RPM, cite Lin 2021 as origin and explicitly note: (a) "MAR" in Lin 2021 is type-independent-MAR, stronger than MAR; (b) generalizability to J>2 / larger n / time-varying covariates is your extension.
3. In your simulation section, fix m explicitly, vary it on at least one scenario (m ∈ {0, 1, 2, 3} at n=200), and report coverage sensitivity. This is the cheapest dissertation contribution on offer.
4. If your DR method is implemented, position it as the answer to Lin 2021's own "future work" on Neyman-orthogonality / double-robustness.

---

## Disposable notebook

- **ID:** `d6782c7f-4e42-4fba-9991-d05512de89c4`
- **Name:** `stress-test-lin_2021_semiparametric_estimation_2026-04-23`
- **URL:** https://notebooklm.google.com/notebook/d6782c7f-4e42-4fba-9991-d05512de89c4
- **Disposition:** Pending. Because this paper is RPM's origin and your subproject maintains 5 imputation methods against it, **promoting** this notebook into `ML for Recurrent Events` (or keeping a dedicated "RPM-origin" notebook) is worth considering — you will return to this paper every time you touch RPM. Confirm or decline at Phase 6.

---

## Prior stress-tests of this paper

None. This is the first stress-test run.
