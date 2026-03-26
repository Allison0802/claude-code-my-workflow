# Session Log: 2026-03-18 — Idea Discovery v2: Event Type Prediction

**Status:** COMPLETED

## Objective
Extend the March 16 idea-discovery run to cover the "event type prediction" gap explicitly: P(next event type = k | recurrent history, censoring). Full research-refine-pipeline run for the top new idea.

## Changes Made

| File | Change | Reason |
|------|--------|--------|
| quality_reports/IDEA_REPORT_2026-03-18_recurrent-events-ml-v2.md | Created | Updated IDEA_REPORT with 3 new ideas from event type prediction gap |
| Claude idea/refine-logs/FINAL_PROPOSAL.md | Created | Final method proposal for OLMC after critical revision |
| Claude idea/refine-logs/REVIEW_SUMMARY.md | Created | Review history: death = absorbing state (not missing data) |
| Claude idea/refine-logs/EXPERIMENT_PLAN.md | Created | 6-block experiment plan, 55-70 SLURM node-hours |
| Claude idea/refine-logs/EXPERIMENT_TRACKER.md | Created | Tracker for SLURM runs and gate checks |
| Claude idea/refine-logs/PIPELINE_SUMMARY.md | Created | Dissertation priority and next actions |

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Primary estimand = μ_k(h) (not conditional π_k) | Avoids 1/q(h) denominator instability in EIF; derive π_k by normalization |
| Death = absorbing competing state (not missing data) | Critical correction from GPT reviewer: death inside G() makes estimand unclear |
| Cross-fitting by subject (not by row) | Multiple landmarks per subject violates row-iid assumption |
| Report π_k(h) only where q(h) ≥ 0.10 | Normalization is unstable for rare-event windows |

## Key Learnings

- [LEARN:OLMC] Death must be modeled as absorbing competing transition in at-risk indicator Y(u), NOT inside censoring survival G_C. Treating death as part of G() conflates missingness with competing event.
- [LEARN:OLMC] EIF for μ_k(h) in recurrent setting: counting-process martingale residual ∫G_C^{-1}(dN_k - Y dΛ_k) + outcome regression term + localization weight. Nontriviality comes from subject-level aggregation of repeated landmarks and death in at-risk indicator.
- [LEARN:OLMC] Cross-fitting in landmark models must split by SUBJECT, not by landmark row, to respect the iid unit.

## Incremental Work Log

- [09:00] Phase 1 lit survey: extended prior survey with event type prediction angle; confirmed gap B completely empty
- [09:30] Phase 2 idea generation: GPT-4o → 10 new ideas; top 3: Orthogonal Mark Classifier, Coherent Simplex, Proper Scoring Rules
- [10:00] Phase 3-4 filtering + critical review: Idea A confirmed novel; death-as-missingness flaw identified and corrected
- [10:30] Phase 4.5 refinement: 3-round GPT review → stable proposal with μ_k primary estimand
- [11:00] Experiment planning: 6 blocks, run order, decision gates, compute budget
- [11:30] All refine-logs files written; IDEA_REPORT v2 created

## Open Questions

- [ ] Verify whether arXiv:2602.00194 (Alberge et al.) covers recurrent events calibration at all
- [ ] ALLHAT trial data access — suitable real-data example for OLMC (cardiovascular multi-type recurrent events)
- [ ] Explore whether the proper scoring rules (New Idea C) can be developed jointly with OLMC as one paper

## Next Steps

1. Extend `rate_cox_data_gen_complex()` to output event type J_s per event
2. Implement DR estimator for μ_k(h): EIF, censoring survival, outcome regression
3. Run Block 1 pilot (200 reps, K=2, n=1000) to verify implementation
4. Parallel: begin Idea 7 (DR pseudo-obs) influence function derivation
