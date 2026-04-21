# Session Log: MAR DGP — add event time T

**Date:** 2026-04-21
**Scope:** Missing Types sub-project

## Goal

Align simulation MAR mechanism with real-data (CARRA) pattern by making
missingness depend on event time T. Motivated by S65 NotebookLM consultation:
for missing event subtypes in competing risks, MAR requires conditioning on
observed failure time T, not just baseline covariates.

## Approach

- Design: Replace old MAR (no T) with MAR_{X,Z,X2,T}. Log-time functional form. β_T = −0.4.
- Scope: DGP + IPW features + paper equation + sub-project critical-details note.
- Out of scope (flagged): RPM/DR outcome model extension — open for follow-up.

## Changes

- [11:12] `Missing Types/functions.R:2227-2266` — introduce_mar_missingness()
  adds `-0.4 * log(e.time)` term; clips log at log(1e-3) for numerical safety.
- [11:15] `Missing Types/simulation_runner.R:215-224` — derive
  `logT = log(checkin + time_to_event)` on landmark rows; IPW features now
  `c("X", "Z", "XX2", "logT")`.
- [11:18] `Missing Types/Papers/method.tex:296-310` — Eq. (eq:mar) updated to
  include `-0.4 log T`; prose explains log-time effect as registry
  workup-incomplete story; flags IPW/RPM/DR need to condition on T.
- [11:25] `Missing Types/Papers/method.tex` — equation split across two lines
  via `split` env to fix Overfull hbox (24pt) after adding log T term.
- [11:20] `Missing Types/CLAUDE.md` — critical-details line updated:
  "IPW MAR features must include `c('X','Z','XX2','logT')`".
- [11:21] New `Missing Types/test_mar_with_time.R` — MAR+logT smoke test.

## Verification

- Smoke test passed: marginal 10.7% / 28.4% / 51.3% for targets 10/30/50%.
- Time dependence confirmed: `P(miss | T below median) / P(miss | T above median) ≈ 1.5`.
- IPW logT coefficient estimated at +0.347 (truth +0.4; model correctly specified).
- `method.tex` compiles clean on XeLaTeX pass 1 (undefined refs are pre-existing,
  resolve after bibtex + 2nd pass).

## Open questions / follow-ups

1. Extend `fit_rate_proportion_model()` `base_vars` to include `log_time`?
   Type may depend on T via `tv.fun`, so complete-case RPM could be biased
   under the new DGP. User decision pending.
2. β_T magnitude: currently −0.4 for primary sim. If cluster results don't
   differentiate T-including vs T-excluding IPW specifications clearly, bump to −0.6.
3. All `results_missing_types/` outputs for MAR scenarios are now obsolete
   — re-run required.

## Quality score (self-assessment)

- Simplicity: 9 — minimal surface area; 2 edits in R code, 1 in TeX, 1 in CLAUDE.md.
- Correctness: 8 — smoke test confirms DGP + IPW wiring; RPM/DR scope still open.
- Traceability: 9 — plan on disk, session log, tests, equation match.
