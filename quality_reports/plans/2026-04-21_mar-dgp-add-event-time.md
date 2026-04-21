# Plan: Add event time T to MAR missingness DGP (Missing Types)

**Status:** APPROVED 2026-04-21
**Scope:** Missing Types sub-project
**Motivation:** CARRA registry MAR depends on event time T; current simulation
MAR uses only baseline covariates X, Z, XX2, so the sim cannot stress-test
IPW/RPM/DR mis-specification from omitting T (see session S65, observation 845).

## Design choices (user-approved)

- (A) Replace — old MAR formulation dropped; results_missing_types/ MAR outputs will be regenerated.
- (ii) log T — no centering; `rate_cox_data_gen_complex` guarantees `e.time > b.time + 0.001 > 0`.
- β_T = −0.4 — earlier events more likely missing; odds ratio T=5 vs T=0.1 ≈ 0.21.

## New MAR formula

```
logit Pr(type missing | X, Z, X2, T)
  = -1.5 + 1.5(X-0.5)^2 + 1.0(X2-0.5)^2 + 1.2*Z*X + 0.8*X*X2 - 0.4*log(T)
```

Marginal target rates (10/20/30/50%) preserved by existing rescale step
(`combined_prob <- pmin(raw_prob * scale_factor, 0.95)`).

## Files to edit

| # | File | Change |
|---|------|--------|
| 1 | `Missing Types/functions.R:2227-2266` | Add `-0.4 * log(e.time)` to score; read `e.time` from event_data (present in columns) |
| 2 | `Missing Types/simulation_runner.R:216-244` | Derive `logT = log(checkin + time_to_event)` on event rows; extend `ipw_features <- c("X", "Z", "XX2", "logT")` |
| 3 | `Missing Types/Papers/method.tex:296-307` | Update Eq. (eq:mar); explain log-T term as link to registry missingness (workup-incomplete story) |
| 4 | `Missing Types/CLAUDE.md` | Update "IPW MAR features must include" critical-detail line |
| 5 | `Missing Types/test_rpm_small.R` | Run locally to verify no NaN/Inf, marginal missingness ≈ target |

## Out of scope (flagged for user decision)

- **RPM/DR outcome model extension** — `fit_rate_proportion_model()` base_vars
  do not include `log(e.time)`. Under the new DGP, type may depend on T via
  `tv.fun`, so complete-case RPM could be biased. Ask user whether to extend
  RPM/DR base_vars to include `log_time` as well. Not in this plan.

## Verification

1. `Rscript test_rpm_small.R` or local small-scale run:
   - No NaN/Inf in final results
   - `actual_missing_pct` hits target ± tolerance
   - IPW model summary includes `logT` coefficient with the expected sign (positive,
     since `observed = 1 - missing`, so logT coefficient ≈ +0.4)
2. Spot-check marginal Pr(miss) at T=1 matches baseline + covariate terms.
3. Session log appended to parent repo.

## Risks

- **Existing MAR cluster results obsoleted** — user confirmed acceptable.
- **β_T too small / too large** — fallback to −0.6 if sim doesn't differentiate
  T-including vs T-excluding IPW specifications.
