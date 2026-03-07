# Plan: Manuscript Review — RF Pseudo for Multi-Type Recurrent Events

**Status:** APPROVED → COMPLETED
**Date:** 2026-03-01
**Manuscript:** `comparisons/RF pseudo.tex`

## Goal

1. Fidelity check — does the manuscript clearly describe what is implemented in `comparisons/`?
2. External reviewer simulation — what would biostatistics journal reviewers critique?

## Approach

1. Run `20-ml-paper-writing` skill (structure, narrative, clarity)
2. Run `domain-reviewer` agent (5 lenses: statistical correctness, simulation design, ML methodology, missing data, results interpretation)
3. Fidelity check: manuscript claims vs. actual code
4. Synthesize as biostatistics reviewer-style comments

## Key Confirmed Facts (from code exploration)

- 37 scenarios: 3 frailty × 3 complexity × 2 ρ × 2 censoring
- 12 method variants: 4 RF strategies + Cox, each × with/without history
- 500 simulations/scenario
- Beta scaling (1.0/0.5/0.2 by complexity): NOT in manuscript — must add
- History features as 2× factor: NOT formally defined — must add
- High-dim scenarios: abandoned by choice (not a gap)
- Event-based C-index: abandoned by choice (not a gap)
- Figure panels: each of 3 figures has 4 panels in 2×2 grid (confirmed correct)

## Output

See `quality_reports/RF_pseudo_manuscript_review_2026-03-01.md`
