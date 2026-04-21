# Fix Plan: DR-RF Variance Estimator — Mathematical Consistency

**Status:** DRAFT
**Date:** 2026-03-27
**Scope:** `Missing Types/variance estimator/`
**Files affected:**
- `dr_rf_variance_coverage_study.R` (production)
- `variance_derivation.tex` (theory document)
- `implementation_roadmap.md` (pseudocode reference)
- `CLAUDE.md` (local docs)

---

## Background

A full mathematical review (2026-03-27) of the variance estimator identified two structural
inconsistencies between the derivation document and the implementation, one undocumented
empirical adjustment, and a set of minor documentation/code hygiene issues. This plan
resolves them in priority order.

---

## Issue Registry

| ID | Severity | Component | Short description |
|----|----------|-----------|------------------|
| V1 | **Critical** | Derivation + Code | `φ_PO` uses DR-corrected KM but derivation also adds `φ_AIPW` — potential double-count |
| V2 | **Critical** | Code | Metadata comment says V_prop = 0 in production; code actually adds it |
| V3 | **Major** | Derivation + Code | Deflation factor `(1/(1-sf))^2` not mentioned in derivation; empirical not theoretical |
| V4 | **Major** | Roadmap | Step 3 says `S_aipw = S_po + φ_AIPW`; RC2 changed this to `response_aipw = S_po` only |
| V5 | **Major** | Code | Legacy 0/1 inbag functions still present in production file (unused but dangerous) |
| V6 | **Major** | Derivation | Theorem 1 V_IJ formula is for custom IJ bootstrap; GRF uses a different internal formula |
| V7 | **Minor** | Code | `var_ij_u` column = `var_ij` in GRF path; misleading column name |
| V8 | **Minor** | Derivation | `m_bar` definition: roadmap says mean over all subjects; code uses event rows only |
| V9 | **Minor** | Simulation | Oracle `exp(−rate*τ)` silently wrong for frailty scenarios (f.alpha > 0) |

---

## Resolution Plan

### Step 1 — Resolve the φ_PO / φ_AIPW double-counting question (V1)

This is the central architectural question. The derivation must choose one of two
consistent formulations. The choice determines everything downstream.

**Option A (recommended):** Plain-KM PO + explicit `φ_AIPW`
- `φ_PO` is the jackknife influence of the **unweighted** KM using raw `ξ_{ik}` indicators
- `φ_AIPW` adds the DR residual on top
- `φ_total = φ_PO + φ_AIPW` is a valid first-order decomposition
- **Derivation change:** Remove the sentence in Section 2.1 that says "DR_ik replaces ξ_ik
  in the KM computation prior to taking the jackknife." Instead, describe the jackknife
  as using raw ξ_ik, and the DR correction as an additive first-order term.
- **Code change:** The pseudo-obs currently use `event_type_dr_cf` as the event weight.
  Under Option A, they should use raw `ξ_ik` (1 for the observed type, 0 for
  missing-type events). The DR correction lives entirely in `φ_AIPW` and `response_aipw`.

**Option B (simpler):** DR-KM PO only, no separate `φ_AIPW` in `V_prop`
- `φ_PO` is the jackknife influence of the **DR-corrected** KM (current code state)
- Set `φ_total = φ_PO` (zero out `φ_AIPW` contribution in `V_prop`)
- `V_total = V_IJ` only (consistent with 2026-03-23 session log's finding)
- **Derivation change:** Remove `φ_AIPW` from eq (6); Theorem 1 eq (9) becomes
  `V_total = V_IJ_clust` only.
- **Code change:** In `add_phi_terms()`, set `phi_total_col = phi_po_col` (drop
  `phi_aipw` contribution). In `fit_grf_and_predict()`, keep `var_prop = 0`.

**Decision needed from Alison:**
> Which option is correct given the paper's estimand?
> Option A is more theoretically complete (full AIPW influence function).
> Option B is simpler and matches the 2026-03-23 calibration finding.
> If the goal is coverage ≈ 95%, empirical calibration should guide the choice.

**Action:** Before editing any files, run a quick diagnostic:
- Compute `φ_PO` variance (from DR-corrected PO jackknife) and `φ_AIPW` variance at a few
  representative subjects. If `Var(φ_AIPW) << Var(φ_PO)`, Option B is adequate and simpler.
- Check current coverage results: if coverage is ~95% with V_prop active, Option A is
  working; if it's over-covered, Option B (drop V_prop) may be better.

---

### Step 2 — Fix the metadata comment vs. code mismatch (V2) [Quick fix]

The metadata comment (line 10–13) says:
> "V_prop is retained for diagnostics but set to zero in production."

But `fit_grf_and_predict()` line 813: `var_total <- var_ij + var_prop`.

**Action:** Update the metadata comment to accurately describe the current state:
- If V_prop is intentionally active: update comment to say so
- If V_prop should be zero: set `var_prop <- 0` in `fit_grf_and_predict()` and remove
  the `compute_propagated_variance()` call from the production path

This is a one-line or one-sentence fix that should be done immediately regardless of
the Step 1 decision, since the comment is currently false.

---

### Step 3 — Document the deflation factor correctly (V3)

**In the derivation (`variance_derivation.tex`):**
Add a new subsection under Section 4 (or as a remark after Theorem 1):

> *Remark (Implementation: GRF variance deflation).* The production implementation uses
> `grf::regression_forest` (Athey, Tibshirani, Wager 2019) rather than the custom
> subject-bootstrap RF described in Theorem 1. GRF's internal IJ variance applies a
> finite-population correction `(1/(1-sf))^2` (Wager et al. 2014) that overcorrects
> for honest forests. We apply a deflation divisor of `(1/(1-sf))^2` to GRF's raw
> variance output. At the study's operating point (n=500, sf≈0.5), this equals 4.0.
> Empirical calibration on K=20 DGP draws confirmed ratio ≈ 3.637 ≈ 4. The factor is
> thus empirically validated at this design point; generalizability to other n or sf
> values is not theoretically guaranteed. See session log 2026-03-23 for calibration
> details.

**In the code (`fit_grf_and_predict()` comment block):**
Change "removes grf's Wager et al. (2014) finite-population bias correction, which
overcorrects for honest forests" to:
> "Empirically calibrated deflation (K=20 DGP draws, 2026-03-23): ratio ≈ 3.637 ≈ 4 =
> (1/(1-0.5))^2. Theoretically motivated by Wager et al. (2014) finite-population
> correction for non-honest forests, but not formally derived for honest forests with
> cluster subsampling. Valid at n=500, sf≈0.5; re-calibrate if design changes."

---

### Step 4 — Update the roadmap to match RC2 (V4)

**In `implementation_roadmap.md`, Step 3:**

Current text:
```
S_aipw[i,k,t] = S_po[i,k,t] + phi_AIPW[i,k,t]
```

Replace with (if Option A is chosen):
```
# S_po uses raw xi indicators; S_aipw adds the DR correction
S_aipw[i,k,t] = S_po_raw[i,k,t] + phi_AIPW[i,k,t]
```

Or (if Option B is chosen):
```
# RC2: response is the DR-corrected pseudo-obs directly (no double correction)
# The KM already uses DR event weights; phi_AIPW enters only through phi_total
# for the V_prop propagation term.
response_aipw[i,k,t] = S_po_dr[i,k,t]   # DR-corrected PO
```

Also update the pseudocode block at the bottom of the roadmap to match.

**Depends on:** Step 1 decision.

---

### Step 5 — Remove legacy functions from production file (V5)

`fit_subject_bootstrap_rf_trace` (lines 539–566) and `estimate_variance_components`
(lines 579–631) are defined in both `dr_rf_variance_coverage_study.R` (production) and
`legacy_custom_ij.R` (archive). The production versions contain the 0/1 inbag bug that
caused 33× overestimation.

**Action:**
1. Delete lines 539–631 from `dr_rf_variance_coverage_study.R`
2. Add a comment above the GRF section (line ~670):
   ```r
   # Legacy custom IJ functions removed 2026-03-27.
   # See legacy_custom_ij.R for archived implementation and bug documentation.
   ```
3. Verify diagnostic scripts (`diagnose_ciz.R`, `diagnose_bootstrap_variance.R`) source
   from `legacy_custom_ij.R` directly, not from the production file.

---

### Step 6 — Fix Theorem 1 V_IJ formula scope (V6)

**In `variance_derivation.tex`, Section 3.2 (eq 8):**

The clustered IJ formula `((n-1)/n)(n/(n-s))^2 Σ_i C_iz^2` describes the custom
subject-bootstrap RF, not GRF. Add a remark:

> *Remark (Correspondence with GRF implementation).* Equation \eqref{eq:IJ_clust}
> gives the theoretical clustered IJ formula for the custom subject-bootstrap RF
> described in Section 3.1. In the production implementation, `grf::regression_forest`
> computes an analogous quantity internally via paired tree comparisons (ci.group.size=2).
> The two estimates are asymptotically equivalent under the conditions of Wager (2018)
> Theorem 6, but differ in finite samples. The empirical deflation factor described in
> the implementation remark (Section 4.3) corrects for this finite-sample discrepancy.

---

### Step 7 — Minor fixes (V7, V8, V9) [Can batch]

**V7 — `var_ij_u` column naming:**
In `fit_grf_and_predict()` output tibble (line 818):
```r
var_ij_u  = var_ij,   # rename to: var_ij_deflated or add inline comment
```
Change to:
```r
var_ij_u  = var_ij,   # GRF path: mc correction internal; ij_u == deflated ij
```

**V8 — `m_bar` centering definition:**
In `implementation_roadmap.md` Step 2b, update:
```
m_bar[k, t] = mean_i(m_hat[i, k, t])   # average over all n subjects
```
To:
```
m_bar[k, t] = mean over event rows at landmark t of m_hat[i,k,t]
# Note: centering over events only (not all landmark rows) ensures sum(phi_AIPW)=0
# within each landmark group. This matches the code; differs from roadmap notation.
```

**V9 — Oracle guard for frailty:**
In `compute_true_subject_survival()`, add after the function signature:
```r
# Valid only for constant-rate DGP (f.alpha = 0). For f.alpha > 0, this
# gives the subject-specific conditional survival given frailty, which is
# correct for the conditional estimand but not for the marginal estimand.
# Coverage evaluation should exclude landmark rows where checkin + tau > C_i.
```

---

## Verification Steps (after all fixes)

1. **Compile the derivation:** `xelatex variance_derivation.tex` — confirm no errors,
   new remark renders correctly.
2. **Check roadmap internal consistency:** Read the roadmap start-to-finish and verify
   the pseudocode at the bottom matches Steps 1–8.
3. **Run test simulation:** `TEST_RUN=true Rscript dr_rf_variance_coverage_study.R`
   — confirm no errors, coverage output present.
4. **Confirm V_prop state:** Print `mean(variance_df$var_prop)` in a test run —
   should be non-zero (if Option A) or exactly 0 (if Option B).
5. **Check diagnostic scripts still run:** Source `diagnose_ciz.R` and
   `diagnose_bootstrap_variance.R` — confirm they load functions correctly without
   the removed legacy code block.

---

## Execution Order

```
Step 2 (metadata comment — 5 min, no decision needed)
  ↓
Step 1 decision (requires diagnostic run or discussion with advisor)
  ↓
Steps 3 + 4 + 6 (derivation + roadmap edits, ~1 hour writing)
  ↓
Step 5 (remove legacy functions from production, ~15 min)
  ↓
Step 7 (minor fixes, ~15 min)
  ↓
Verification (run test + compile)
```

---

## Open Questions for Advisor

1. **Option A vs B for φ decomposition:** Is the goal to have `V_total` capture
   both survival-curve uncertainty AND individual DR residual uncertainty (→ Option A),
   or is the DR correction small enough that `V_total = V_IJ` alone is sufficient
   (→ Option B)?

2. **Jackknife validity for fractional DR weights:** The WKM pseudo-obs with
   fractional DR event indicators has not been proven to satisfy von Mises
   differentiability (Graw et al. 2009). Is this acceptable as a stated conjecture
   in the paper, or does it need a proof or simulation evidence?

3. **Frailty scenarios:** Should the variance study be extended to f.alpha > 0 before
   submission? This would require fixing the oracle (Issue V9) and re-running the
   cluster simulations.
