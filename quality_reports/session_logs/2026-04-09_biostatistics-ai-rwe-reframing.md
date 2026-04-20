# Session Log: Biostatistics AI+RWE Special Collection Reframing

**Date:** 2026-04-09
**Goal:** Reframe comparisons paper for Biostatistics special collection on "Statistical Foundations of AI and Real-World Evidence Generation" — focus more on LM+RWD, less on Stratified vs. Joint
**Skill:** `/auto-paper-improvement-loop` with HUMAN_CHECKPOINT=true, MAX_ROUNDS=4

## Score Progression

| Round | Score | Key Changes |
|-------|-------|-------------|
| 0 | — | Paper framed as "Stratified vs. Joint" methods comparison |
| 1 | 5.0/10 | Identified 3 CRITICAL misalignments with special collection |
| 2 | 6.5/10 | Reframing confirmed successful; new structural issues found |
| 3 | 7.8/10 | All structural issues resolved; MERF algebra added |
| 4 | 8.3/10 | All fixes verified; ready for submission (conditional on R code) |

## Key Changes Made

### Title and Framing
- Retitled: "Pseudo-Observation Landmarking as a Bridge for Machine Learning on Real-World Longitudinal Data"
- Abstract rewritten to lead with RWD challenges, present framework as model-agnostic bridge
- Introduction restructured: RWD revolution → traditional methods → pseudo-obs bridge → 3 contributions

### Methods
- Pipeline roadmap paragraph added at top of Section 2 (4-stage pipeline with forward refs)
- Labels added: `\label{sec:transform}`, `\label{sec:pseudo}`, `\label{sec:simresults}`

### Discussion
- Restructured around 3 RWD themes (not "Stratified vs. Joint")
- MERF identifiability: added 6 lines of formal algebra (collinearity argument)
- AI governance paragraph: drift detection, fairness, transportability (honest about what's future work)
- Discussion reordered: algebra → IQR → broader lesson → recommendations

### Bibliography
- 9 new entries: Goldstein 2017, Vock 2016, van Houwelingen & Putter 2012, DeepHit 2018, Haider 2020, Debray 2015, Cook & Lawless 2007, Graf 1999, Gerds & Schumacher 2006

## Deferred to R Code

5 tasks recorded in `comparisons/Paper/TODO_R_CODE_FOR_PAPER.md` and saved to project memory:
1. IPCW Brier scores + CARRA calibration plot
2. Out-of-range prediction quantification
3. Sex/race-stratified C-indices (CARRA subgroup fairness)
4. Computational cost table (RF vs. MERF vs. Cox timing)
5. EM convergence diagnostics (σ_b^2 trajectories)

## Files Modified
- `comparisons/Paper/RF pseudo.tex` — all LaTeX edits
- `comparisons/Paper/po.bib` — 9 new bibliography entries
- `comparisons/Paper/PAPER_IMPROVEMENT_LOG.md` — full session documentation
- `comparisons/Paper/PAPER_IMPROVEMENT_STATE.json` — state tracking
- `comparisons/Paper/TODO_R_CODE_FOR_PAPER.md` — R code task specifications

## Compilation
- 25 pages, XeLaTeX + biber
- 0 undefined citations, 1 overfull hbox (Table 1 resizebox, cosmetic)
