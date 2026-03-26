# Session Log: RF Pseudo Advisor Revisions

**Date:** 2026-03-24
**Task:** Revise `comparisons/RF pseudo.tex` per advisor comments in `RF pseudo 20260204-jc.pdf`

## Changes

- [21:15] comparisons/RF pseudo.tex — Fix 1: Expanded CARRA abbreviation in abstract on first use
- [21:15] comparisons/RF pseudo.tex — Fix 2: Restructured intro paragraph 1 for logical flow (recurrent → multi-type → cross-event dependencies); clarified "cross-event dependencies" with explicit definition
- [21:15] comparisons/RF pseudo.tex — Fix 3: Added m_ik ≥ 0 to notation; clarified δ = 1 for all indexed events and C_i retained as terminal observation
- [21:16] comparisons/RF pseudo.tex — Fix 4: Removed duplicated N_i^(k)(t) displayed equation (kept inline definition only)
- [21:16] comparisons/RF pseudo.tex — Fix 5: Clarified "elapsed time" as time since study entry (t_0 = 0)
- [21:17] comparisons/RF pseudo.tex — Fix 6: Added explicit cause-specific censoring statement in §2.4 before first use
- [21:17] comparisons/RF pseudo.tex — Fix 7: Corrected notation \hat{S}_k^{(-i)} → \hat{S}^{(k)(-i)} for consistency
- [21:18] comparisons/RF pseudo.tex — Fix 8: Clarified training procedure is across all landmark times simultaneously
- [21:18] comparisons/RF pseudo.tex — Fix 9: Clarified minimum node size = 5 pseudo-observations; added note on subject-level minimum
- [21:19] comparisons/RF pseudo.tex — Fix 10: Added limitation note on exponential waiting time assumption
- [21:19] comparisons/RF pseudo.tex — Fix 11: Renamed "censoring proportion" → "event-free proportion" in §3.1/3.2
- [21:20] comparisons/RF pseudo.tex — Removed pre-existing \DeclareUnicodeCharacter{2013} (pdflatex-only; XeLaTeX handles Unicode natively)
- [21:20] comparisons/PAPER_IMPROVEMENT_LOG.md — Created round 1 improvement log

## Status

All 13 advisor comments addressed. Missing figure files (simulation plots, CARRA time-series) prevent local compilation; compile on Longleaf for full PDF.

- [auto-paper-improvement-loop] comparisons/Paper/RF pseudo.tex — GPT-5.4 2-round review loop: 4→5/10 (Almost). Fixed estimand precision (cause-specific vs subdistribution), notation completeness (C_i(t), eta edge case, competing-event censoring in X_i^(k)), medication leakage, results overclaims; added 4 new limitation paragraphs; corrected figure filenames; fixed all overfull hbox. PDFs: round0_original, round1, round2.
- [auto-review-loop] comparisons/Paper/RF pseudo.tex — GPT-5.4 4-round autonomous review loop: 5→6→7→7.5/10 (Almost, SMMR/LDA/Biometrical Journal). Key fixes: (1) conditional claims replacing blanket "RF beats Cox" (Cox wins in high-censoring + complexity); (2) MERF instability quantified from IQR data (>75% of 500 replicates below C=0.5 at worst scenario); (3) cross-type scope limited to shared-frailty settings throughout; (4) practical recommendations (RF/Joint RF as defaults, MERF conditional); (5) Monte Carlo CI note; (6) limitations expanded (calibration, comparators, cross-type). Remaining: calibration analysis (Brier score), stronger comparators, cross-type simulation scenarios.
