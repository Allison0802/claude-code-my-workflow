# Stress-Test Briefing: A Closed-Form Variance Estimator for Restricted-Mean-Survival-Time Pseudo-Observations under Right Censoring

**Authors:** Synthetic Authors A., Synthetic Authors B., Synthetic Authors C.
**Year:** 2026
**Source:** master_supporting_docs/supporting_papers/test_papers/testpaper_a_rmst_variance.pdf
**Stress-test date:** 2026-04-24
**Detected paper type:** new-estimator
**Depth:** 1
**Weights:** medium/heavy/medium/heavy/medium/light/heavy/heavy/medium
**Reviewer model:** opus
**Author-surrogate model:** sonnet

---

## TL;DR verdict

The paper proposes an influence-function-based closed-form RMST pseudo-observation, θ̃_i = μ̂ + ÎF_i, and claims a simple closed-form variance σ̂² = n⁻¹ Σ ÎF²_i under independent right censoring. The thematic-notebook check surfaces an exact precedent: **Bouaziz (2023) published the identical closed-form RMST pseudo-observation via Von Mises expansion three years earlier, entirely uncited.** The asymptotic-theory scaffolding (Overgaard et al. 2017, Jacobsen-Martinussen 2016) is also uncited, and the paper provides no rate conditions, no Donsker class, no cross-fitting, no head-to-head jackknife benchmark, and no MC standard errors. **Recommendation: skip** — the headline novelty is a rediscovery, and the theoretical backing is asserted rather than proved.

---

## Top 5 killer questions

1. **[Lens 7/positioning, critical]** Bouaziz (2023, *Biometrical Journal*) already derived the exact closed-form RMST pseudo-observation θ̃_i = μ̂ + ÎF_i via Von Mises expansion of the Kaplan-Meier estimator; why is this paper's "novel" identity a contribution rather than a rediscovery?
   - *Why it matters:* the paper's headline novelty is already in the published literature and uncited.
2. **[Lens 3/methodology, critical]** Where are the Donsker / bracketing-entropy conditions on the KM influence-function class, the uniform consistency rate for Ĝ(t) on [0, τ], and the cross-fitting argument that would justify equating Var(θ̃_i) with Var(ÎF_i)?
   - *Why it matters:* any downstream paper citing this for consistency cites beyond what is proved.
3. **[Lens 1/estimand, critical]** Does the "closed-form" identity target μ(τ) = E[min(T, τ)] or the censoring-dependent functional ∫₀^τ Ŝ(u)du when S(τ) > 0, and how is τ pre-specified relative to the KM plateau?
   - *Why it matters:* without an identifiability rule for τ, the estimand drifts with the censoring distribution.
4. **[Lens 4/overclaims, major]** The "drop-in replacement" claim is made without a head-to-head jackknife benchmark and without Monte Carlo standard errors — on what evidentiary basis is 94.8% distinguishable from jackknife's presumed 95%?
   - *Why it matters:* drop-in-replacement claims must be backed by paired empirical comparison.
5. **[Lens 6/generalizability, major]** How does the estimator degrade under competing risks (Aalen-Johansen), left-truncation, or time-varying covariates, and is there any theoretical guarantee or simulation outside the single-event iid right-censored regime?
   - *Why it matters:* most applied RMST settings have at least one of these extensions.

---

## External novelty-check

Skipped (reason: `user_flag` — `--skip-novelty` passed; synthetic test paper, novelty-check would hallucinate prior work). Prior-art triangulation in Lens 7 via the *ML for Recurrent Events* thematic notebook took its place and returned a decisive hit.

---

## Severity summary

| Lens | Name | Weight | Depth | Severity | Judgment |
|------|------|--------|-------|----------|----------|
| 0 | data | medium | 1 | major | conceded |
| 1 | estimand | heavy | 1 | critical | conceded |
| 2 | identification | medium | 1 | major | conceded |
| 3 | methodology | heavy | 1 | critical | conceded |
| 4 | overclaims | medium | 1 | major | conceded |
| 5 | alternatives | light | 1 | major | conceded |
| 6 | generalizability | heavy | 1 | major | conceded |
| 7 | positioning | heavy | 1 | critical | evaded |
| 8 | reproducibility | medium | 1 | minor | conceded |

**Tally:** critical=3 · major=5 · minor=1 · clean=0 · skipped=0

---

## Per-lens findings

### Lens 0 — data (**major**, conceded)

- **Finding:** Simulation tests a single DGP (n=500, ~30% independent censoring) and fixes every parameter but covariate effect size; no covariate-dependent censoring, heavy ties at τ, small-n, or heavy-censoring regime is tested.
- **Author's best defense:** "the paper does not address this" — scope explicitly narrow.
- **Why it didn't hold:** author conceded the paper does not address the scope-breadth question; single DGP with narrow parameters leaves coverage behavior under practical survival settings unknown.

### Lens 1 — estimand (**critical**, conceded)

- **Finding:** Paper does not distinguish the estimand μ(τ)=E[min(T,τ)] from the censoring-dependent plug-in ∫₀^τ Ŝ(u)du, fixes τ=2 by fiat, and does not address tail identifiability when S(τ)>0.
- **Author's best defense:** "the paper does not address this" — no distinction, no τ-identifiability rule.
- **Why it didn't hold:** tail identifiability beyond the KM plateau is undefined; τ=2 chosen without an ε-threshold rule tying it to the censoring support.

### Lens 2 — identification (**major**, conceded)

- **Finding:** Independent-censoring assumption T⊥C stated once and never defended; no covariate-conditional censoring treatment, no sensitivity analysis, no Discussion limitation.
- **Author's best defense:** "the paper does not address this".
- **Why it didn't hold:** T⊥C is asserted without justification and no sensitivity analysis; Moderator downgraded from reviewer's 'critical' to 'major' because scope is declared in assumptions, not concealed.

### Lens 3 — methodology (**critical**, conceded)

- **Finding:** No derivation, no Donsker / bracketing-entropy conditions, no uniform KM consistency rate, no cross-fitting — the identity Var(θ̃_i) ≈ Var(IF_i) rests on a single appeal to "standard influence-function arguments".
- **Author's best defense:** "the paper does not address this" — no theorem, no lemma, no citation to a regularity result.
- **Why it didn't hold:** the identity Var(θ̃_i) ≈ Var(IF_i) is informally motivated without the rate / Donsker / cross-fitting machinery that would certify consistency.

### Lens 4 — overclaims (**major**, conceded)

- **Finding:** Drop-in-replacement framing plus 2-decimal coverage with no head-to-head jackknife comparison and no Monte Carlo SEs on (0.947, 0.942, 0.933).
- **Author's best defense:** "the paper does not address this" in two ways — no jackknife column in Table 1, no MC SEs.
- **Why it didn't hold:** "drop-in replacement" is declared, not demonstrated; no head-to-head jackknife comparison or MC-SE reporting.

### Lens 5 — alternatives (**major**, conceded)

- **Finding:** Single benign DGP (Exp(1)/Unif(0,4)), no head-to-head against jackknife or infinitesimal-jackknife, so nominal coverage could be a DGP artifact rather than an estimator property.
- **Author's best defense:** "the paper does not address this" — no head-to-head; informal IF justification.
- **Why it didn't hold:** coverage advantage over a generic plug-in is not identifiable from one benign DGP without a paired comparator.

### Lens 6 — generalizability (**major**, conceded)

- **Finding:** Scope is strictly single-event, iid, independent-right-censored; no competing-risks, left-truncation, or time-varying-covariate extension or theoretical guarantee.
- **Author's best defense:** "the paper does not address this" — Graw 2009 is cited but not adopted or extended.
- **Why it didn't hold:** no attempt at any extension or sensitivity analysis beyond single-event iid right-censoring.

### Lens 7 — positioning (**critical**, evaded)

- **Finding:** Bouaziz (2023, *Biometrical Journal*) already published the exact closed-form RMST pseudo-observation θ̃_i = μ̂ + ÎF_i via Von Mises expansion of KM; Overgaard-Parner-Pedersen (2017, *Annals of Statistics*) is the asymptotic-theory precedent. Neither is cited.
- **Author's best defense:** "the paper does not address this" — references list contains only Andersen-Perme (2010) and Graw-Gerds-Schumacher (2009); Bouaziz 2023, Overgaard 2017, Jacobsen-Martinussen 2016 absent.
- **Why it didn't hold:** exact prior-art precedent (Bouaziz 2023) published the same estimator three years earlier; the paper's "novel" closed-form identity is a rediscovery, and the asymptotic-theory foundation (Overgaard 2017) is also uncited.

### Lens 8 — reproducibility (**minor**, conceded)

- **Finding:** No seed, no public code, no Monte Carlo SEs on the reported coverage; parametric DGP (Unif censoring) means no KM-bandwidth tuning applies, but the manuscript makes no such clarifying statement.
- **Author's best defense:** "the paper does not address this in full" — author quantifies MC noise as ~±1.4pp at B=1000, within the range of reported 0.933–0.947.
- **Why it didn't hold:** missing seed, repo, and MC SEs make exact figure reproduction impossible; core method description is sufficient for reimplementation, hence minor (downgraded from reviewer's 'critical').

---

## Skipped lenses

None.

---

## Relevance to user's sub-projects

### Missing Types (`Missing Types/`) — **No (synthetic test paper)**

- **Applies:** No — not a useful reference or comparator.
- **Data match:** *Poor.* Missing Types targets missing event-type labels for recurrent competing-risks events with landmark FL-KM pseudo-observations; this paper is single-event scalar RMST.
- **Warning:** This is a synthetic test paper. The real foundational references for closed-form RMST pseudo-observations are Bouaziz (2023) and Overgaard et al. (2017). Cite those, not this.
- **Missing comparator:** Not a candidate baseline.

### Comparisons (`comparisons/`) — **No (synthetic test paper)**

- **Applies:** No.
- **Data match:** *Poor.* `comparisons/` targets recurrent competing risks with frailty; this paper is single-event iid scalar Y.
- **Warning:** Same as above — for influence-function RMST foundations, use Bouaziz 2023 and Overgaard 2017.
- **Missing comparator:** Not a candidate baseline.

---

## Recommendation

**skip**

**Rationale:** Severity tally across the nine lenses: critical=3 (lenses 1/3/7), major=5 (lenses 0/2/4/5/6), minor=1 (lens 8), clean=0. Mechanical rule: major ≥ 5 (and also critical ≥ 1) → **skip**. The decisive finding is Lens 7: Bouaziz (2023, *Biometrical Journal*) published the identical closed-form RMST pseudo-observation three years prior, entirely uncited. Combined with absence of any asymptotic theory and absence of a paired jackknife benchmark, the paper cannot be cited as either a novel contribution or a theoretically-grounded method.

---

## Disposable notebook

- **Name:** stress-test-testpaper_a_rmst_2026-04-24
- **ID:** `e2c32d6b-dde4-4888-92f9-5bbf64bbc9e6`
- **URL:** https://notebooklm.google.com/notebook/e2c32d6b-dde4-4888-92f9-5bbf64bbc9e6
- **Disposition:** deleted in Phase 6 cleanup

---

## Prior stress-tests of this paper

None on record. This is the first stress-test for `testpaper_a_rmst_*`.
