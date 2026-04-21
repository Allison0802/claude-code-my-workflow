# Substance Review: simulation.R (derive-logs)

**Date:** 2026-03-28
**Reviewer:** domain-reviewer agent
**Target file:** `Missing Types/derive-logs/simulation.R`
**Reference document:** `Missing Types/derive-logs/FINAL_DERIVATION.md`
**Context:** Phase 6 of /method-derive; pilot passed 18/18 criteria (500 reps, n=200)

---

## Summary

- **Overall assessment:** MINOR ISSUES (no CRITICAL)
- **Total issues:** 6 (4 MAJOR, 2 MINOR)
- **Blocking issues (prevent submission):** 0
- **Non-blocking:** 4 MAJOR (documentation gaps + 1 missing scenario), 2 MINOR

The estimator code is mathematically correct and the DGP faithfully instantiates assumptions A1–A5. The true CIF formula is correct. The DR AIPW correction formula is correct. Three serious pilot bugs (type-label reversal, nnet column reversal, RNG stream discard) are properly fixed and documented. Remaining issues are documentation gaps or a missing scenario — none invalidate the pilot results.

---

## Lens 1: Statistical Correctness

### Issue 1.1 [MAJOR]: `dr_unclip` applies undisclosed propensity truncation

- **Location:** lines 362 and 365
- **Problem:** Guard `pi_hat[i] > 0.01` means the AIPW correction is silently omitted for events where pi_hat ≤ 0.01. Separate truncation `max(pi_hat[i], 0.01)` at line 365 is then redundant for cases that pass the guard. Net effect: `dr_unclip` is NOT the pure unclipped theoretical estimator — it applies propensity truncation from below at 0.01. FINAL_DERIVATION.md's DR clipping note mentions only output clipping but not propensity truncation.
- **Fix:** Add code comment explicitly noting this is a second implementation deviation from the theorem and add a note to FINAL_DERIVATION.md's clipping note.

### Issue 1.2 [MAJOR]: RPM hybrid estimator undocumented

- **Location:** lines 412–414
- **Problem:** For observed events (R=1), code overrides RPM-model probability with hard indicator (`frac1[observed_events] <- as.numeric(df$K_obs[observed_events] == 1)`). This oracle-augmented RPM is not described in FINAL_DERIVATION.md. Theorem applies to pure-model-weight estimator. Hybrid is statistically valid and consistent (observed events have oracle type), but the gap is undisclosed.
- **Fix:** Add code comment at lines 412–414 explaining the hybrid form and noting the derivation covers the pure model-weight estimator.

### Issue 1.3 [MAJOR]: In-sample propensity estimation unjustified in code

- **Location:** lines 327–341
- **Problem:** `pi_hat` fit and evaluated on same sample. For parametric GLM this satisfies A5(c) via Donsker class, but the justification is not stated in the code. The gap matters if code is extended to non-parametric nuisance (RF).
- **Fix:** Add comment invoking the Donsker-class argument at the propensity fitting step.

### Issue 1.4 [MINOR]: `compute_frac_aj_pseudo` holds nuisance fixed for LOO

- **Location:** lines 239–253
- **Problem:** LOO only removes the AJ step; nuisance weights held at full-sample values (not refit per LOO). Function is defined but not called in the main loop — does NOT affect pilot results. Would introduce finite-sample bias if used in production regression.
- **Fix:** Add docstring note warning about nuisance-fixed LOO.

---

## Lens 2: Simulation Design

### Issue 2.1 [MAJOR]: No misspecification scenario demonstrates double robustness

- **Location:** lines 52–70 (scenario grid)
- **Problem:** All MAR scenarios use a correctly specified outcome model (outcome model includes Tstar, X1, X2; true mechanism depends on Tstar, X1). Cannot empirically distinguish "DR works because DR" from "DR works because outcome model is correct."
- **Fix:** Add scenario with misspecified outcome model (RPM with only X2) and correct propensity to demonstrate double robustness property empirically.

### Issue 2.2 [MINOR]: MAR intercept calibrated per sample, not population

- **Location:** lines 141–145
- **Problem:** `uniroot` calibrates `a0` to achieve the target missing fraction in the current sample (n=200). Cross-replicate variation in `a0` is small (~0.085 SD) and pilot results show this is negligible. Could be improved by computing `a0` once from a large MC population draw.
- **Impact:** No practical effect at current sample sizes; pilot confirmed < 1% bias. Document only.

---

## Lens 3–5: ML Methodology, Missing Data, Results Interpretation

**No issues found.** RPM multinomial logit and propensity GLM are appropriate. MAR mechanism correctly implemented and identified. Results correctly distinguish theoretically-grounded bias criterion from empirical SE/coverage diagnostics.

---

## Priority Recommendations

1. **[MAJOR]** Document propensity truncation at 0.01 in `dr_unclip` + add FINAL_DERIVATION.md note
2. **[MAJOR]** Document RPM hybrid estimator in code comment + clarify in FINAL_DERIVATION.md
3. **[MAJOR]** Add Donsker-class justification comment at propensity estimation step
4. **[MAJOR]** Add double-robustness misspecification scenario to scenario grid
5. **[MINOR]** Add LOO-nuisance-fixed warning to `compute_frac_aj_pseudo` docstring

---

## Positive Findings

1. **True CIF formula exactly correct:** `F_k(tau) = E_W[lam_k/lam * (1 - exp(-lam*tau))]` for exponential competing risks is correctly derived and implemented.
2. **Fractional AJ product-integral correctly implemented:** `compute_fractional_aj` computes `S_hat(t_j-)` via KM, accumulates fractional increments, and weights by left-limit survival — exactly matching FINAL_DERIVATION.md.
3. **G(u-) cancellation correctly achieved:** `censor_time <- runif(n, 0, censor_max)` fully independent of all covariates — stronger than needed, ensures exact G-cancellation from Step 2.
4. **Three pilot bugs properly fixed and documented:** type-label reversal, nnet column reversal, RNG stream discard all repaired with explanatory comments.
