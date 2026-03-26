# Review Summary: Orthogonal Landmark Mark Classifier

**Date:** 2026-03-18
**Rounds:** 1 (GPT-4o xhigh) + prior idea-creator critical review

---

## Round 1: GPT-4o Critical Review (2026-03-18)

### Status: APPROVED after one revision

### Critical flaw identified (now fixed):
The original proposal modeled death inside G(s+w | H_s) = P(C > s+w, D > s+w | H_s). The reviewer correctly identified this as treating death as missing data, which makes the estimand unclear. The fix: death is an absorbing competing transition, not missing data. Only censoring coarsens the data. The at-risk indicator Y(u) now correctly removes subjects who die before time u.

### Key reviewer insights:

**On EIF nontriviality (objection 1):**
"The reviewer is partly correct that this looks like AIPW multiclass on relabeled outcome. The nontrivial part only appears if you explicitly formulate this as a recurrent multistate next-transition problem from arbitrary post-baseline histories, with death as an absorbing competing state and censoring as the only coarsening mechanism." → Fixed by cleaner process formulation.

**On denominator instability (objection 2):**
"The cleanest stabilization is not ad hoc weight normalization. It is to estimate μ_k(h) first, then normalize. That removes the 1/q(H_s) blow-up from the score itself." → Revised to primary target μ_k, derive π_k by normalization.

**On cross-fitting (new issue raised):**
"Because subjects contribute multiple landmarks, the iid unit is the subject, not the landmark. Cross-fitting must be by subject." → Critical correction to implementation.

**On nuisance completeness (new issue raised):**
"The hazard-based nuisance set needs {λ_1,...,λ_K, λ_D} or an equivalent full outcome regression. λ_k alone is incomplete." → Death hazard must be modeled explicitly.

### Reviewer's ranking of proposal:
"If you recast the paper around estimation of post-landmark next-transition probabilities μ_k(h) and derive the conditional type classifier by normalization, the proposal becomes much sharper and defensible."

---

## Prior Review: Idea-Creator Critical Review (2026-03-18)

**Objection 1:** "This is just AIPW multiclass regression on a relabeled outcome" → Addressed by multistate formulation and death-as-competing-state framing.

**Objection 2:** "AIPW variance blows up when P(event in window | H_s) is small" → Addressed by μ-first estimation then normalization.

**Objection 3:** "Must show naive approaches are materially biased" → Addressed by Block 3 simulation (informative censoring + death scenarios).

**Recommendation:** "Proceed with modification. Strong if positioned as a principled estimation paper with EIF/DR theory."

---

## Remaining Risks

1. **Denominator positivity:** If q(h) is small in real data, the conditional type classifier cannot be reported for those history strata. This is a limitation to state explicitly, not a fatal flaw.

2. **Multiple landmark contributions per subject:** The variance estimator must use subject-level aggregated influence functions. If this is implemented incorrectly, coverage will be off.

3. **Nuisance model misspecification in high dimensions:** Block 6 (flexible nuisance) provides evidence here, but may require very large n (2000-3000) to see DR gain clearly.
