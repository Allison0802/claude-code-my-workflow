# Pipeline Summary: Orthogonal Landmark Mark Classifier

**Problem:** No method exists for predicting next-event type distribution after recurrent non-competing event histories under censoring and competing death.
**Final Method Thesis:** A cross-fitted doubly robust estimator for the K-vector μ_k(h) = P(next event is type k before death in [s,s+w] | H_s = h), with the conditional classifier π_k(h) derived by normalization and reported where q(h) ≥ 0.10.
**Final Verdict:** READY (after one critical revision: death is absorbing competing state, not missing data)
**Date:** 2026-03-18

---

## Final Deliverables

- Proposal: `refine-logs/FINAL_PROPOSAL.md`
- Review summary: `refine-logs/REVIEW_SUMMARY.md`
- Experiment plan: `refine-logs/EXPERIMENT_PLAN.md`
- Experiment tracker: `refine-logs/EXPERIMENT_TRACKER.md`

---

## Contribution Snapshot

- **Dominant contribution:** First semiparametrically justified prediction method for next-event type from arbitrary recurrent histories — fills completely empty gap in ML and statistical literature
- **Optional supporting contribution:** Normalization gate (q(h) threshold) + subject-clustered variance estimator for repeated-landmark DR estimation
- **Explicitly rejected complexity:** joint frailty model, death-as-missingness, triply-robust hazard layer, joint time+type prediction

---

## Must-Prove Claims

1. **Identification + EIF:** μ_k(h) is identified under conditional independent censoring with death as absorbing; EIF has counting-process form; normalization to π_k introduces ratio term (nontrivial)
2. **Double robustness:** Consistent under one-correct nuisance; naive methods (observed-case, death-as-censoring) show material bias under informative censoring/death
3. **Practical distinction from CR:** Fine-Gray/cause-specific Cox fail or are undefined for post-recurrence landmark states; OLMC remains calibrated

---

## First Runs to Launch

1. **Block 1 pilot** (K=2, n=1000, 200 reps) — verify DR-oracle is unbiased and EIF variance tracks Monte Carlo
2. **Block 2 pilot** (K=3, n=1500, 200 reps) — verify DR robustness mechanism (2×2 nuisance matrix)
3. **Block 3 + Block 4** (1000 reps, parallel) — key novelty signal: naive bias + CR distinction

---

## Main Risks

- **Risk:** Death-censoring independence assumption fails in real data (shared frailty between death and event type)
  - **Mitigation:** Show results with death-as-absorbing-state AND with shared-frailty sensitivity in Block 6; provide guidance on when assumption is unrealistic
- **Risk:** q(h) too small for most H_s states in practice (type prediction moot)
  - **Mitigation:** Block 5 establishes threshold; paper explicitly scopes to q(h) ≥ 0.10 support region
- **Risk:** Multiple-landmark variance estimation is wrong (under-coverage)
  - **Mitigation:** Block 1 oracle check tests this; subject-clustered SE is the required fix

---

## Overall Dissertation Priority (Updated)

| Rank | Paper | Pub Prob | Status |
|---|---|---|---|
| 1 | Idea 7: DR pseudo-obs for missing types | 65% | Theory derivation |
| 2 | **New Idea A: OLMC (this paper)** | 45–55% | → READY TO IMPLEMENT |
| 3 | New Idea C: Proper scoring rules | 40–50% | Plan alongside OLMC |
| 4 | Idea 1: MTLRF | 40% | ML simulation |

---

## Next Action

1. Extend `rate_cox_data_gen_complex()` to output event type J_s per event
2. Implement DR estimator for μ_k(h) with EIF (Block 1 oracle first)
3. Run `/run-experiment` with Block 1 pilot SLURM script
4. Pair with proper scoring rules (New Idea C) for evaluation metrics
