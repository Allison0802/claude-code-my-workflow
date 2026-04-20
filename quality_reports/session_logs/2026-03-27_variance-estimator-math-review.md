# Session Log: 2026-03-27 — Variance Estimator Mathematical Review

## Goal
Full mathematical correctness review of `Missing Types/variance estimator/` —
covering the production R script, the derivation document, and the implementation roadmap.

## What Was Reviewed
- `dr_rf_variance_coverage_study.R` (full read, all key functions)
- `variance_derivation.tex` (full read)
- `implementation_roadmap.md` (full read)
- `legacy_custom_ij.R` (full read)
- `CLAUDE.md` for the variance estimator subfolder

## Key Findings

### Correct and sound
- DGP (Cox-linear, exponential inter-event times via inversion method)
- Cross-fitting: subject-level folds, out-of-fold propensity and outcome predictions
- `φ_AIPW` formula: `R/π*(ξ-m̂) + m̂ - m̄` — correct; R=0 case (only centering term) is right
- DR normalization: `dr1/(dr1+dr2)` — theoretically unnecessary (sum = 1 exactly) but safe
- Oracle survival `exp(-rate*τ)`: valid for constant-rate, no-frailty DGP
- `compute_propagated_variance` matrix formula: correct subject-clustered delta-method form
- Fixed landmark spacing from n=5000 reference draw — correct design
- `RNGkind("L'Ecuyer-CMRG")` before `mclapply` — correct

### Structural inconsistency (V1 — requires decision)
The derivation (Section 2.1) says the jackknife pseudo-obs use the DR-corrected KM.
Theorem 1 then adds `φ_AIPW` to `φ_PO` in the propagated term.
If the DR-corrected KM jackknife already captures the DR residual's first-order influence,
adding `φ_AIPW` again double-counts it. The derivation must commit to one of:
- Option A: plain-KM PO + explicit `φ_AIPW` (full decomposition, more moving parts)
- Option B: DR-KM PO only, φ_AIPW = 0 in V_prop (simpler, matches 2026-03-23 calibration)

### Empirical adjustment not in derivation (V3)
The deflation factor `(1/(1-sf))^2 ≈ 4` applied to GRF's raw variance is empirically
calibrated (ratio = 3.637 ≈ 4 from K=20 draws, 2026-03-23) but presented in code
comments as theoretically derived. It is not mentioned at all in `variance_derivation.tex`.
This gap needs a remark in the derivation and corrected code comment.

### Metadata comment is false (V2 — quick fix)
Line 10-13 says "V_prop set to zero in production." `fit_grf_and_predict()` line 813
computes `var_total = var_ij + var_prop` with non-zero V_prop. Comment must be fixed.

### Roadmap out of date with RC2 (V4)
Step 3 of roadmap: `S_aipw = S_po + φ_AIPW`. RC2 changed production code to
`response_aipw = S_po` (plain DR-corrected PO, no double correction). Roadmap never updated.

### Legacy 0/1 inbag functions still in production file (V5)
`fit_subject_bootstrap_rf_trace` and `estimate_variance_components` (the functions
with the 0/1 inbag bug causing 33x overestimation) remain in the production script
(lines 539-631), not just in `legacy_custom_ij.R`. They are not called by
`run_one_replicate`, but are a hazard.

## Action Items
See full plan: `quality_reports/plans/2026-03-27_variance-estimator-fix-plan.md`

Priority order:
1. Fix metadata comment (V2) — 5 min, no decision needed
2. Decide Option A vs B for φ decomposition (V1) — requires advisor input
3. Add deflation remark to derivation (V3) — after decision
4. Update roadmap Step 3 (V4) — after decision
5. Remove legacy functions from production file (V5)
6. Minor fixes: Theorem 1 GRF scope note (V6), var_ij_u rename (V7), m_bar note (V8), oracle frailty guard (V9)

## Open Questions
- Option A vs B: advisor decision needed
- Jackknife validity for fractional DR weights: accept as conjecture or prove?
- Frailty scenarios: needed before submission?

---
**Context compaction (auto) at 20:24**
Check git log and quality_reports/plans/ for current state.

---

## Fixes Applied (session resumed after compaction)

- [R] `dr_rf_variance_coverage_study.R` — V2: corrected false metadata comment (lines 10–14); V_prop=0 was wrong, now accurately describes V_total = V_IJ_deflated + V_prop
- [R] `dr_rf_variance_coverage_study.R` — V2: updated GRF block comment (~line 678) from outdated "V_total = V_IJ only" to current state with V1 open-question flag
- [R] `dr_rf_variance_coverage_study.R` — V5: added LEGACY warning block before `fit_subject_bootstrap_rf_trace`; function not deleted (diagnostic scripts source via eval/parse)
- [R] `dr_rf_variance_coverage_study.R` — V7: added inline comment on `var_ij_u` line documenting IJ-U ≡ deflated IJ, MC correction internal to grf
- [R] `dr_rf_variance_coverage_study.R` — V9: expanded `compute_true_subject_survival()` comment on conditional vs. marginal estimand mismatch for frailty; noted f.alpha=0 in current study
- [tex] `variance_derivation.tex` — V6: added remark on GRF asymptotic equivalence after clustered IJ formula (eq. 8)
- [tex] `variance_derivation.tex` — V1: added remark documenting Option A vs B open question for training response; advisor decision pending
- [tex] `variance_derivation.tex` — V3: added remark on GRF variance deflation factor (1/(1-sf))^2 and empirical calibration ratio 3.637
- [tex] `variance_derivation.tex` — V8: corrected m_bar definition to sum over event rows only (n_t^{-1} sum_{ell: dN_ell=1}), not all n subjects
- [md] `implementation_roadmap.md` — V8: added note in Step 2b that m_bar is computed over event rows at landmark t only; updated data structures table
- [md] `implementation_roadmap.md` — V4: rewrote Step 3 to document RC2 decision (response = S_po only, not S_po + phi_AIPW); added rationale and V1 flag
- [md] `implementation_roadmap.md` — V4: updated Step 4 Response field to `S_po[i,k,t]` with RC2 note
- [md] `implementation_roadmap.md` — V4: updated pseudocode STEP 3 to `response[i,k,t] = S_po[i,k,t]` with explanatory comments
- [md] `implementation_roadmap.md` — V4: updated pseudocode STEP 4 `response =` argument to match

## Deferred (awaiting advisor decision)
- V1 structural resolution: Option A (plain-KM PO) vs Option B (DR-KM PO only) — documented in all three files as pending
- V5 full deletion: legacy functions `fit_subject_bootstrap_rf_trace` / `estimate_variance_components` pending diagnostic script migration to `legacy_custom_ij.R`

---

## Option A implementation (session continued)

**Decision:** Option A chosen as statistically superior. Option B understates V_prop (misses nuisance uncertainty unless nuisances are refitted per jackknife drop). Current hybrid (DR-KM + phi_AIPW in V_prop) double-counts. Option A gives the correct, non-overlapping influence function decomposition (Bang & Tsiatis 2002, Kennedy 2016).

- [R] `dr_rf_variance_coverage_study.R` — `generate_landmark_weighted_pseudo()`: added plain-KM pseudo-obs (`pseudoEst_km_plain_type1/2`) alongside DR-corrected PO; uses `I(event==1 & !is.na(type) & type==k)` as event indicator (missing types censored)
- [R] `dr_rf_variance_coverage_study.R` — `add_phi_terms()`: phi_PO now uses plain-KM PO; response_aipw = S_po_plain + phi_AIPW (Option A); added Option A rationale comment block; `plain_pseudo_bar` centering added
- [R] `dr_rf_variance_coverage_study.R` — GRF block comment: resolved V1 open question, documented Option A and theoretical basis
- [R] `dr_rf_variance_coverage_study.R` — fit_grf_and_predict(): updated stale RC2 comment to Option A
- [R] `dr_rf_variance_coverage_study.R` — line 1 corrupted file-path artifact removed (pre-existing parse error)
- [tex] `variance_derivation.tex` — V1 remark replaced: "open architectural question" → "Option A resolved"; documents plain-KM PO, non-overlapping decomposition, cites Bang & Tsiatis (2002), Kennedy (2016)
- [md] `implementation_roadmap.md` — Step 3 rewritten to Option A; data structures table updated (S_po_plain, S_bar_plain); Step 4 Response field and pseudocode updated
- [pilot] `dr_rf_variance_coverage_study.R` — TEST_RUN=true MAR 30% pilot: 2 reps completed without errors; V_prop non-zero throughout; output files created

## Remaining deferred
- Full-scale cluster run (n=500, B=100 reps × 8 scenarios) needed for definitive coverage assessment

---

## Tasks 1–3 (final session)

- [tex] `variance_derivation.tex` — created `references.bib` with all 8 citation keys (`Andersen2003`, `Robins1994`, `LinCai2021`, `Chernozhukov2018`, `Wager2014`, `Wager2018`, `kennedy2016`, `Loe2025`); replaced non-existent `bangTsiatis2002` key with correct `Robins1994`; 3-pass compile clean (311K PDF, one harmless `!h` float warning)
- [R] `dr_rf_variance_coverage_study.R` — V5 complete: legacy block (fit_subject_bootstrap_rf_trace, predict_forest_trace, estimate_variance_components, lines 584–692) deleted; functions already exist in legacy_custom_ij.R which diagnostic scripts source directly via guard-option pattern
- [pilot] 50-rep pilot at n=200, MAR 30%: coverage 68.5% (type 1), 83.6% (type 2) — below 91–99% target

**Coverage diagnosis:** undercoverage is driven by **prediction bias**, not variance underestimation. bias/SE = 0.76 (type 1), 0.49 (type 2). Plain-KM pseudo-obs over-estimate survival (missing types censored → fewer events → inflated KM), and the phi_AIPW DR correction is imperfect at n=200 with 30% missingness. V_prop share is appropriate (~59%), suggesting variance decomposition is working. **Recommendation:** run at n=500 (full scale) before drawing conclusions — bias should shrink with larger n and more stable nuisance estimation.

## Fractional AJ Simulation — Phase 6-8 (method-derive skill)

- [review] Domain reviewer found 5 issues in `Missing Types/derive-logs/simulation.R`; applied all fixes (RNG order, FALLBACK consistency, pi_failed flag, T variable rename, PASS criterion split)
- [fix] Cross-scenario RNG: `rng_streams <- nextRNGStream(...)` → `.Random.seed <- nextRNGStream(...)` (result was silently discarded; all scenarios shared same seed)
- [fix] `compute_metrics()` pass criterion split: `pass_bias` (theoretically grounded, bias < 5%) vs `pass_se_empirical` (empirical diagnostic only, no SE validity claimed)
- [pilot-bug] DGP type labeling: `rbinom(n,1,prob=lam1/lam)+1L` → `2L-rbinom(...)` (off-by-one; P(K=1) was lam2/lam not lam1/lam; caused complete type swap, 24-33% bias)
- [pilot-bug] `nnet::multinom` 2-class predict returns P(K=second level) as vector, not matrix; `is.vector` branch in `fit_rpm_weights` had `matrix(c(probs,1-probs))` assigning P(K=2) to frac1 and P(K=1) to frac2; fixed to `matrix(c(1-probs,probs))` — caused persistent 6-8% bias at all n
- [pilot-pass] After fixes: 18/18 scenarios pass; max relative bias 0.83%, SE ratios 0.93-1.07, coverage 0.93-0.96
- [slurm] Wrote `run_full.slurm` (array=1-9, 8 cores, 60 min), `simulation_longleaf.R` (one-scenario wrapper), `simulation_collect.R` (aggregation), `run_instructions.md`
- [state] DERIVE_STATE.json: phase=done, status=completed; pilot_results.md written

---
**Context compaction (auto) at 14:08**
Check git log and quality_reports/plans/ for current state.

---
**Context compaction (auto) at 14:42**
Check git log and quality_reports/plans/ for current state.
