# Session Log: FL-KM Consistency Validation

**Date:** 2026-04-12
**Project:** Missing Types
**Goal:** Validate unbiasedness and consistency of the FL-KM estimator via /research-refine

## Summary

Used /research-refine with 3 rounds of subagent review (Codex MCP unavailable) to rigorously validate the theoretical properties of the Fractional Landmark Kaplan-Meier estimator defined in `method.tex` (Eqs. 3-5). Consulted NotebookLM for domain grounding on IPCW-KM theory and pseudo-observation conditions.

## Key Decisions

- [00:00] Identified that FL-KM targets a different estimand (type-specific event-free probability) than the existing AJ derivation (CIF) — needs its own theory
- [00:10] Round 1 review (5.8/10): proof steps were prose, not math. Need formal lemmas and theorem.
- [00:30] Round 1 revision: Added Lemma 1 (product weight), Lemma 2 (plug-in stability), Theorem 1 (consistency), Proposition 1 (CCA bias)
- [01:00] Round 2 review (7.3/10): Need A9 (type independence), explicit martingale decomposition
- [01:30] Round 2 revision: Discovered key identity E[f_j | T, W] = 1-m_k (observation probability cancels). Added A9, sample-splitting for filtration.
- [02:00] Round 3 review (7.9/10): Only 3 minor fixes remaining. Applied in FINAL_PROPOSAL.md.

## Key Mathematical Result

**Theorem 1:** Under A1-A9, FL-KM is consistent: $\sup_s |\tilde{S}^{(k)}(s) - S^{(k)}(s)| \to 0$ in probability.

**Core insight (Lemma 1):** The per-event factor $f_j = R \cdot I(K \neq k) + (1-R)(1-m_k)$ satisfies $E[f_j \mid T, W] = 1 - m_k$ — the missingness probability $\pi$ drops out entirely.

## Files Created

- `Missing Types/refine-logs/FINAL_PROPOSAL.md` — Clean final derivation (7.9/10)
- `Missing Types/refine-logs/REFINEMENT_REPORT.md` — Full round-by-round record
- `Missing Types/refine-logs/REVIEW_SUMMARY.md` — High-level summary
- `Missing Types/refine-logs/round-{0,1,2}-*.md` — Round files
- `Missing Types/refine-logs/score-history.md` — Score evolution

## Open Questions

- Closed-form variance σ_k^2 (influence function not derived)
- CLT is Conjecture 1, not Theorem (needs influence function)
- Clipped DR implementation not covered by theory
