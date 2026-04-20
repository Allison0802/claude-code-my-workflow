# Session Log — RF Pseudo Special Collection Revision

**Date:** 2026-04-08
**Branch:** main

## Summary

Targeted framing revision of `comparisons/Paper/RF pseudo.tex` for submission to
*Biostatistics* special collection "Statistical Foundations of AI and Real-World
Evidence Generation." Four text edits plus one keyword addition — scientific content
and all "machine learning" terminology from the 2026-04-07 audit are unchanged.

## Changes

- [08:00] `comparisons/Paper/RF pseudo.tex` — 4 framing edits + 1 keyword:
  - **(Keywords):** Added "artificial intelligence" as first keyword (collection's
    primary search term; does not change scientific content which uses "machine
    learning" throughout).
  - **(Abstract, sentence 1):** "remain underexplored in this context" →
    "remain underdeveloped in real-world evidence (RWE) settings" — surfaces
    both collection themes (statistical foundations + RWE) in sentence 1.
  - **(Intro §1, RWE paragraph closing):** Added "statistically valid and" and
    "---and characterizing their failure modes before deployment---" to strengthen
    the reliability framing. (Reviewer feedback: removed a redundant "constitutes
    a direct contribution" clause.)
  - **(Intro §1, contribution statement):** Added em-dash parenthetical
    "including empirical diagnostic criteria for identifying pre-deployment
    identifiability failures based on event-free proportion and effective sample
    size"; changed "responsible use" → "reliable and responsible deployment."
  - Scientific content unchanged; "machine learning" terminology from 2026-04-07
    audit preserved throughout.

## Result

- Compiles clean: 23 pages, 0 errors.
- Paper framing explicitly aligned with collection themes: statistical foundations,
  RWE settings, pre-deployment reliability diagnostics, responsible deployment.
- All 2026-04-07 terminology fixes intact.

---

---

## 2026-04-09 — Introduction Reference Additions

Added missing references to §1 of `comparisons/Paper/RF pseudo.tex`, guided by NotebookLM.
Four new bib entries added to `po.bib`; five existing bib entries newly cited.

- [09:54] `comparisons/Paper/po.bib` — Added 4 new entries: Ishwaran et al. 2008 (RSF),
  Hajjem et al. 2014 (MERF), Overgaard et al. 2017 (asymptotic theory of pseudo-obs GEE),
  Jacobsen & Martinussen 2016 (large sample properties of GEE pseudo-obs).
- [09:54] `comparisons/Paper/RF pseudo.tex` — 4 citation additions in §1:
  - **(Para 3, RSF):** `ishwaran_random_2008` — motivates pseudo-obs over splitting-rule methods.
  - **(Para 3, pseudo-obs breadth):** `andersen_pseudo-observations_2010`, `mogensen_random_2013`.
  - **(Para 3, XMT + landmarking + asymptotic validity):** `xia_regression_2020`,
    `van_houwelingen_dynamic_2007`, `overgaard_asymptotic_2017`, `jacobsen_note_2016`.
  - **(Para 4, MERF):** `hajjem_mixed-effects_2014`, `capitaine_longitudrf_2021`.
- Compiles clean: 24 pages, 0 new errors.
