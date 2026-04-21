# Analysis Strength Review: Missing Types Scripts
**Date:** 2026-03-26
**Scope:** All scripts in `Missing Types/` excluding `variance estimator/`
**Files reviewed:** `functions.R`, `simulation_engine.R`, `simulation_runner.R`, `analyze_missing_types_results.R`, all 9 method wrapper scripts

---

## CRITICAL — Current simulation results may be invalid

### C1: RPM and DR train on the same rows as CCA
**File:** `simulation_runner.R` lines 429–438
**Problem:** The training filter `(train_data$event != 1 | !is.na(train_data$type))` removes all landmark rows where the next event has a missing type. For RPM and DR, fractional pseudo-observations (`pseudoEst_km_type1` via `generate_km_pseudoEst_weighted`) exist for these rows, but the filter discards them before model fitting. RPM and DR are therefore training on exactly the same rows as CCA — the fractional indicators are computed but never used.
**Fix:** For RPM/DR methods, relax filter to include rows with valid fractional indicators:
```r
(train_data$event != 1 | !is.na(train_data$type) |
 (!is.na(train_data$event_type1_rpm) & imputation_method %in% c("rpm","rpm_rf","dr","dr_rf")))
```
Same fix needed at lines 435–438 (`train_data_type2`) and lines 463–466 (`train_combined`).

### C2: IPW propensity model misspecified — XX2 omitted
**File:** `functions.R` lines 1252–1258; `simulation_runner.R` line 157
**Problem:** MAR mechanism uses `x`, `z`, AND `xx2` (quadratic term + interaction with x). IPW propensity model uses only `intersect(c("X", "Z"), names(...))` — `XX2` never included. IPW/IPW-RF estimates under MAR are systematically biased. The CLAUDE.md note "IPW-RF uses only covariates that generate MAR missingness (`X`, `Z`)" is also factually wrong.
**Fix:** `ipw_features <- intersect(c("X", "Z", "XX2"), names(event_rows_td))`. Also correct CLAUDE.md.

---

## MAJOR — Fix before submission

### M1: DR normalization eliminates double-robustness
**File:** `functions.R` (DR indicator computation, search `dr_sum`)
**Problem:** Raw AIPW scores `DR_k = m_k(X) + (R/pi)(I_k - m_k(X))` are divided by `DR_1 + DR_2`. After renormalization, `E[DR_k/(DR_1+DR_2)] ≠ P(type=k)` even when both models are correct. Double-robustness property is lost.
**Fix:** Replace renormalization with clipping: `pmax(0, pmin(1, DR_k))`.

### M2: KM pseudo-observations for competing risks target wrong estimand
**File:** `functions.R` lines 746–838 (`generate_km_pseudoEst`), lines ~1716–1775 (`generate_km_pseudoEst_weighted`)
**Problem:** `survfit(Surv(time_to_event, event_type1) ~ 1)` treats competing events as random censoring, estimating cause-specific survival `S_k(tau)`, not the cumulative incidence function (CIF) / mean cumulative function `mu_k(tau)`. The stated estimand is `mu_k(t) = E[N_k(t)]`, which ≠ `1 - S_k(t)` under competing risks. This is a fundamental design error affecting all methods.
**Fix:** Replace with Aalen-Johansen estimator: `survfit(Surv(time, factor(status)) ~ 1)` or `cmprsk::cuminc`. Compute pseudo-observations from AJ-based CIF.

### M3: avg_gap includes censoring intervals — inflates aa and tau
**File:** `simulation_runner.R` lines 331–342
**Problem:** `gap_any` is computed across all rows (events + censored intervals). Censoring intervals inflate `avg_gap`, which inflates `aa = avg_gap/3` and `tau = 5*aa`. `tau` controls the prediction horizon and landmark grid — it should be data-driven from inter-event gaps only, or fixed from DGP parameters.
**Fix:** Filter to event rows before computing gaps:
```r
data_events <- data[data$event == 1, ]
data_with_gaps <- data_events %>% arrange(pid, e.time) %>%
  group_by(pid) %>% mutate(gap_any = e.time - lag(e.time)) %>%
  filter(!is.na(gap_any)) %>% ungroup()
```

### M4: Parallel RNG not L'Ecuyer-CMRG
**File:** `simulation_engine.R` lines 226–258
**Problem:** PSOCK cluster workers are not initialized with `RNGkind("L'Ecuyer-CMRG")` + `clusterSetRNGStream()`. Workers inherit parent RNG state; concurrent workers can draw correlated random variates.
**Fix:** After `makeCluster()`, add:
```r
RNGkind("L'Ecuyer-CMRG")
clusterSetRNGStream(cl, iseed = 20260326)
```

### M5: Second set.seed(seed) in run_comprehensive_simulation biases the split
**File:** `simulation_runner.R` lines 396–398
**Problem:** `set.seed(seed)` is called again before the train-test split, resetting to the same state as entry. Imputation randomness does not flow into the split. Makes split deterministically coupled to data generation.
**Fix:** Remove the second `set.seed(seed)` call at lines 396–398.

### M6: Seven silent tryCatch blocks swallow all model failures
**File:** `simulation_runner.R` lines 543–545, 582–584, 630–632, 678–680, 768–770, 845–847, 973–975
**Problem:** Model fitting failures produce NA silently. Under 50% MAR, systematic failures in one method appear as better performance because failing replicates are excluded from the mean C-index without being flagged.
**Fix:** Log errors to a `failed_models` vector, include in the returned result list.

### M7: MERF prediction ignores random effects
**File:** `simulation_runner.R` lines 611–613, 659–661
**Problem:** `predict(merf_model_type1$Forest, data = ...)` uses only the forest (fixed effects) component, discarding estimated random intercepts. For subjects also in training, this makes MERF appear weaker than RF. At minimum, document that random effects = 0 for test subjects is intentional.

### M8: No MNAR scenario
**Problem:** All 8 scenarios are MCAR or MAR. In practice, event types are missing precisely because of what type they are (MNAR). Reviewers will ask. Add at least one MNAR scenario (e.g., P(missing | type=1) = 2 × P(missing | type=2)).

### M9: Only n=100
**Problem:** With n=100, 20 test subjects and ~5–10 events per type, C-index is highly unstable. Asymptotic properties of IPW/AIPW cannot be assessed. Add n=300 (and optionally n=500).

### M10: Copy-paste bug in LaTeX method_map — Joint RF Type 2 gold-standard shows CC value
**File:** `analyze_missing_types_results.R` line ~895
**Problem:** `"c_rf_time_type2_mean"` appears twice (as both CC and true-type column for Joint RF Type 2). Published table will show identical values in both columns for this method-type combination.
**Fix:** Change second instance to `"c_rf_time_type2_true_mean"`.

---

## MODERATE — Address before committing

### m1: No here::here() — paths break on SLURM
**Files:** `simulation_engine.R`, `analyze_missing_types_results.R`
Relative paths `"results_missing_types"`, `source("functions.R")` fail when SLURM job's cwd ≠ `Missing Types/`. Replace all with `here::here(...)`.

### m2: Figure standards violations
**File:** `analyze_missing_types_results.R`
- Non-Okabe-Ito colors (`#2E86AB`, `#A23B72`) — replace with sky_blue (#56B4E9), vermilion (#D55E00)
- `theme_minimal()` inline instead of `theme_publication()`
- `ggsave()` missing `bg = "white"`
- `size = 0.5` in `geom_errorbar()` — deprecated, use `linewidth = 0.5`

### m3: options(warn = -1) globally suppresses MERF convergence warnings
**File:** `simulation_runner.R` lines 596, 645, 696
Replace with `withCallingHandlers()` that captures convergence warnings selectively.

### m4: DR propensity fit happens before compute_event_history_features
**File:** `simulation_runner.R` lines 107–114
If `fit_propensity_model_rf` internally selects history columns, it would be misspecified. Clarify order and add comment documenting why propensity model intentionally excludes history features.

### m5: No Monte Carlo SE reported
Compute `mc_se = sd(c) / sqrt(sum(!is.na(c)))` per method-scenario. Report as CI bands on mean C-index. If SE > 0.005, increase to 1000 replicates.

### m6: No frailty variation
All scenarios have `f.alpha = 0`. Add one scenario with `f.alpha = 0.5` (moderate frailty) to assess generalizability.

---

## MINOR

- `analyze_missing_types_results.R` header `Last Updated` stale (2026-02-23 → 2026-03-26)
- `simulation_engine.R` header missing Author, Inputs, Outputs fields
- `sim_seeds <- 1:n_sims` → `seq_len(n_sims)` to handle n_sims=0 edge case
- Figure width 16" in `ggsave` needs comment that it's for supplementary/exploratory use
- `analyze_missing_types_results.R` missing `library(here)` and `set.seed(20260326)`

---

## Positive findings

- Subject-level train-test split is correctly implemented
- RPM fractional indicator computation (`impute_event_types`) is correct
- GRF uses `clusters = as.integer(factor(train_data$id))` correctly for within-subject correlation
- IPW weight trimming uses median (reasonable heuristic, though percentile-based is more principled)
- `type_true` preservation before missingness introduction is correctly placed
