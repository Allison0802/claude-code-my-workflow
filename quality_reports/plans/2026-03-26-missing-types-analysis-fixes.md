# Missing Types Analysis Strength Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 10 correctness and quality issues in the Missing Types simulation scripts, ranging from critical bugs that invalidate current results to major methodological improvements.

**Architecture:** Fixes are applied directly to three core files — `functions.R`, `simulation_runner.R`, `simulation_engine.R` — plus a one-line correction in `analyze_missing_types_results.R`. No new files are created. Changes are ordered from most to least blocking.

**Tech Stack:** R 4.4.0, survival, cmprsk, ranger, tidyverse, grf, LongituRF; run on SLURM (Longleaf) via PSOCK parallel

---

## Files Modified

| File | Tasks |
|------|-------|
| `Missing Types/simulation_runner.R` | T1 (training filter), T2 (IPW features), T4 (avg_gap), T5 (double seed), T7 (error logging) |
| `Missing Types/functions.R` | T3 (DR normalization), T6 (KM → AJ pseudo-obs) |
| `Missing Types/simulation_engine.R` | T8 (parallel RNG) |
| `Missing Types/analyze_missing_types_results.R` | T9 (LaTeX bug, figure standards) |

---

## Task 1: Fix RPM/DR training data filter (CRITICAL — current results invalid)

**File:** `Missing Types/simulation_runner.R` lines 429–467

**Problem:** `(train_data$event != 1 | !is.na(train_data$type))` drops all landmark rows where the next event has a missing type — including rows with valid fractional RPM/DR pseudo-observations. RPM and DR currently train on exactly the same rows as CCA.

**Logic for fix:** Include rows when (a) non-event, OR (b) event with observed type, OR (c) event with missing type but the imputation method computed fractional indicators (rows have valid `pseudoEst_km_type1` already, computed by the weighted KM in Phase B).

- [ ] **Step 1: Read the current filter blocks**

Open `simulation_runner.R` and locate lines 428–467. Confirm the three filter sites:
- `train_data_type1` (lines 429–433)
- `train_data_type2` (lines 435–439)
- `train_combined` (lines 462–466)

- [ ] **Step 2: Define a helper logical vector above the filter blocks**

Insert immediately before line 429 (after the `train_data`/`test_data` assignment block, before `# Filter training data`):

```r
    # For RPM/DR methods, fractional indicators allow training on rows with
    # missing type (the weighted pseudo-obs were computed in Phase B).
    # For all other methods (CCA, IPW) we still require observed type.
    imputed_methods <- c("rpm", "rpm_rf", "dr", "dr_rf")
    use_fractional_train <- imputation_method %in% imputed_methods

    # A landmark row is valid for training if:
    #   (a) it is a non-event row, OR
    #   (b) it is an event row with observed type, OR
    #   (c) method uses fractional indicators AND pseudo-obs exist for this row
    type_ok <- function(td) {
      (td$event != 1) |
      (!is.na(td$type)) |
      (use_fractional_train & !is.na(td$pseudoEst_km_type1))
    }
    type_ok2 <- function(td) {
      (td$event != 1) |
      (!is.na(td$type)) |
      (use_fractional_train & !is.na(td$pseudoEst_km_type2))
    }
```

- [ ] **Step 3: Replace `train_data_type1` filter**

Replace lines 429–433:
```r
    train_data_type1 <- train_data[
      !is.na(train_data$pseudoEst_km_type1) &
      !is.na(train_data$event_type1) &
      (train_data$event != 1 | !is.na(train_data$type)),
    ]
```
With:
```r
    train_data_type1 <- train_data[
      !is.na(train_data$pseudoEst_km_type1) &
      !is.na(train_data$event_type1) &
      type_ok(train_data),
    ]
```

- [ ] **Step 4: Replace `train_data_type2` filter**

Replace lines 435–439:
```r
    train_data_type2 <- train_data[
      !is.na(train_data$pseudoEst_km_type2) &
      !is.na(train_data$event_type2) &
      (train_data$event != 1 | !is.na(train_data$type)),
    ]
```
With:
```r
    train_data_type2 <- train_data[
      !is.na(train_data$pseudoEst_km_type2) &
      !is.na(train_data$event_type2) &
      type_ok2(train_data),
    ]
```

- [ ] **Step 5: Replace `train_combined` filter (two occurrences)**

Replace lines 462–466:
```r
    train_combined <- rbind(
      train_data[!is.na(train_data$pseudoEst_km_type1) & (train_data$event != 1 | !is.na(train_data$type)), ] %>%
        mutate(pseudoEst_combined = pseudoEst_km_type1, type_combined = 1),
      train_data[!is.na(train_data$pseudoEst_km_type2) & (train_data$event != 1 | !is.na(train_data$type)), ] %>%
        mutate(pseudoEst_combined = pseudoEst_km_type2, type_combined = 2)
    )
```
With:
```r
    train_combined <- rbind(
      train_data[!is.na(train_data$pseudoEst_km_type1) & type_ok(train_data), ] %>%
        mutate(pseudoEst_combined = pseudoEst_km_type1, type_combined = 1),
      train_data[!is.na(train_data$pseudoEst_km_type2) & type_ok2(train_data), ] %>%
        mutate(pseudoEst_combined = pseudoEst_km_type2, type_combined = 2)
    )
```

- [ ] **Step 6: Verify with test run**

```bash
cd "Missing Types"
SCENARIO_NAME="missing_MAR_30pct_rpm" TEST_RUN=true N_SIMS=2 Rscript missing_types_method_comparison_rpm.R 2>&1 | grep -E "train_data_type|n_train|nrow|ERROR"
```
Expected: no errors; training row counts for RPM should now be larger than CCA (confirms fractional rows are included).

- [ ] **Step 7: Update Last Updated header in simulation_runner.R**

Change line 9: `# Last Updated: 2026-03-26` (already current — no change needed if today's date).

- [ ] **Step 8: Commit**

```bash
cd "Missing Types"
git add simulation_runner.R
git commit -m "fix: include fractional-indicator rows in RPM/DR training data

Training filter was dropping all event rows with missing type, even
when RPM/DR had computed valid fractional pseudo-observations for them.
RPM and DR were effectively training on identical rows to CCA.
Introduce type_ok/type_ok2 helpers that allow fractional rows through
for rpm/rpm_rf/dr/dr_rf methods only."
```

---

## Task 2: Fix IPW propensity model — add XX2 to features (CRITICAL)

**File:** `Missing Types/simulation_runner.R` line 157

**Problem:** The MAR mechanism (`introduce_mar_missingness`) depends on X, Z, *and* XX2 (quadratic term `1.0*(xx2-0.5)^2` plus interaction `0.8*x*xx2`). The IPW propensity model uses only X and Z, causing systematic bias in IPW/IPW-RF estimates under MAR.

- [ ] **Step 1: Locate the ipw_features line**

In `apply_imputation_phase_b`, line 157:
```r
      ipw_features  <- intersect(c("X", "Z"), names(event_rows_td))
```

- [ ] **Step 2: Add XX2 to the feature set**

Replace line 157:
```r
      ipw_features  <- intersect(c("X", "Z"), names(event_rows_td))
```
With:
```r
      # IPW features must match ALL covariates that drive missingness.
      # introduce_mar_missingness uses X, Z, and XX2 (quadratic + interaction).
      ipw_features  <- intersect(c("X", "Z", "XX2"), names(event_rows_td))
```

- [ ] **Step 3: Verify XX2 is present in transformed_data at that point**

`XX2` is set in `transform_with_covariates_complex` from `baseline$xx2`. Confirm:
```bash
cd "Missing Types"
SCENARIO_NAME="missing_MAR_10pct_ipw" TEST_RUN=true N_SIMS=2 Rscript missing_types_method_comparison_ipw.R 2>&1 | grep -E "ipw_features|XX2|formula|median_weight"
```
Expected: output shows `ipw_features` includes XX2; logistic formula includes XX2; `median_weight` prints.

- [ ] **Step 4: Update CLAUDE.md — fix the incorrect documentation**

In `Missing Types/CLAUDE.md`, under "Critical Technical Details", find:
```
IPW-RF method uses **only covariates that generate MAR missingness** (`X`, `Z`):
```r
# Correct: matches introduce_mar_missingness()
ipw_features <- c("X", "Z")
```
Replace with:
```
IPW-RF method uses **all covariates that generate MAR missingness** (`X`, `Z`, `XX2`):
```r
# Correct: matches introduce_mar_missingness() which depends on x, z, and xx2
ipw_features <- c("X", "Z", "XX2")
```

- [ ] **Step 5: Commit**

```bash
cd "Missing Types"
git add simulation_runner.R CLAUDE.md
git commit -m "fix: add XX2 to IPW propensity model features

MAR mechanism depends on X, Z, and XX2 (quadratic term and interaction).
IPW propensity model was only conditioning on X and Z, causing
systematic misspecification under MAR. Fix ipw_features and correct
erroneous CLAUDE.md documentation."
```

---

## Task 3: Fix DR normalization — replace with clipping (MAJOR)

**File:** `Missing Types/functions.R` lines 1992–1998 and 2112–2118

**Problem:** Raw AIPW scores `DR_k = m_k(X) + (R/pi)(I_k - m_k(X))` are divided by `DR_1 + DR_2`. This renormalization destroys double-robustness: `E[DR_k / (DR_1 + DR_2)] ≠ P(type=k)` even when both models are correct. Replace with per-component clipping to `[0,1]`.

There are two identical normalization blocks: one in `compute_dr_indicators_rf` (~line 1992) and one in `compute_dr_indicators` (~line 2112). Both must be changed identically.

- [ ] **Step 1: Fix compute_dr_indicators_rf (first occurrence, ~lines 1992–1998)**

Locate and replace:
```r
  dr_sum <- dr_type1 + dr_type2
  dr_sum[dr_sum == 0] <- 1
  dr_type1_norm <- dr_type1 / dr_sum
  dr_type2_norm <- dr_type2 / dr_sum

  data$event_type1_dr[is_event] <- dr_type1_norm
  data$event_type2_dr[is_event] <- dr_type2_norm

  type_imputed_hard <- ifelse(dr_type1_norm > dr_type2_norm, 1, 2)
  data$type_imputed[is_missing] <- type_imputed_hard[R == 0]

  p1_entropy <- pmax(pmin(dr_type1_norm, 1 - 1e-10), 1e-10)
  p2_entropy <- pmax(pmin(dr_type2_norm, 1 - 1e-10), 1e-10)
```
With:
```r
  # Clip raw AIPW scores to [0,1] per component.
  # Renormalization (dividing by DR_1 + DR_2) would destroy double-robustness:
  # E[DR_k / (DR_1 + DR_2)] != P(type=k) even when both models are correct.
  dr_type1_norm <- pmax(0, pmin(1, dr_type1))
  dr_type2_norm <- pmax(0, pmin(1, dr_type2))

  data$event_type1_dr[is_event] <- dr_type1_norm
  data$event_type2_dr[is_event] <- dr_type2_norm

  type_imputed_hard <- ifelse(dr_type1_norm > dr_type2_norm, 1, 2)
  data$type_imputed[is_missing] <- type_imputed_hard[R == 0]

  p1_entropy <- pmax(pmin(dr_type1_norm, 1 - 1e-10), 1e-10)
  p2_entropy <- pmax(pmin(dr_type2_norm, 1 - 1e-10), 1e-10)
```

Also update the diagnostic cat lines that reference "Normalized" to say "Clipped":
```r
  cat(sprintf("  Clipped DR type 1: mean=%.3f, min=%.3f, max=%.3f\n",
              mean(dr_type1_norm), min(dr_type1_norm), max(dr_type1_norm)))
  cat(sprintf("  Clipped DR type 2: mean=%.3f, min=%.3f, max=%.3f\n",
              mean(dr_type2_norm), min(dr_type2_norm), max(dr_type2_norm)))
```

Also remove (or comment out) the post-normalization sum check since values no longer necessarily sum to 1:
```r
  # Note: clipped DR scores need not sum to 1 per event — this is correct.
  # indicator_sums <- ...  (removed: normalization check no longer applies)
```

- [ ] **Step 2: Fix compute_dr_indicators (second occurrence, ~lines 2112–2118)**

Apply the identical replacement — same `dr_sum` block → `pmax(0, pmin(1, ...))` clipping, same diagnostic label change, same comment on the sum check — at lines ~2112–2118.

- [ ] **Step 3: Verify**

```bash
cd "Missing Types"
SCENARIO_NAME="missing_MAR_30pct_dr" TEST_RUN=true N_SIMS=2 Rscript missing_types_method_comparison_dr.R 2>&1 | grep -E "Clipped|DR type|outside"
```
Expected: "Clipped DR type 1/2" lines appear; no "Normalized" references.

- [ ] **Step 4: Commit**

```bash
cd "Missing Types"
git add functions.R
git commit -m "fix: replace DR sum-normalization with per-component clipping

Dividing raw AIPW scores by (DR_1 + DR_2) destroys double-robustness:
the ratio is not unbiased for P(type=k) even when both models are
correctly specified. Replace with pmax(0, pmin(1, DR_k)) clipping in
both compute_dr_indicators() and compute_dr_indicators_rf()."
```

---

## Task 4: Fix avg_gap — exclude censoring intervals (MAJOR)

**File:** `Missing Types/simulation_runner.R` lines 331–342

**Problem:** `avg_gap` is computed from all rows (including the final censoring interval per subject), inflating the value. `aa = avg_gap/3` and `tau = 5*aa` are the landmark spacing and prediction horizon — both are inflated, making results hard to interpret.

- [ ] **Step 1: Replace the avg_gap computation block**

Replace lines 331–342:
```r
    # Step 4: Calculate aa from average event gap time
    data_with_gaps <- data %>% arrange(pid, e.time) %>%
      group_by(pid) %>%
      mutate(b.time_any = lag(e.time, default = 0),
             gap_any = e.time - b.time_any) %>%
      ungroup()

    avg_gap <- mean(data_with_gaps$gap_any, na.rm = TRUE)
    if (is.na(avg_gap) || avg_gap <= 0) {
      avg_gap <- 0.3  # Default fallback
    }
    aa  <- avg_gap / 3
    tau <- 5 * aa
```
With:
```r
    # Step 4: Calculate aa from average inter-event gap (events only).
    # Restrict to event rows to exclude the inflating censoring interval.
    data_events_only <- data[data$event == 1, ]
    if (nrow(data_events_only) > 1) {
      data_with_gaps <- data_events_only %>%
        arrange(pid, e.time) %>%
        group_by(pid) %>%
        mutate(gap_any = e.time - lag(e.time)) %>%
        filter(!is.na(gap_any)) %>%
        ungroup()
      avg_gap <- mean(data_with_gaps$gap_any, na.rm = TRUE)
    } else {
      avg_gap <- NA
    }
    if (is.na(avg_gap) || avg_gap <= 0) {
      avg_gap <- 0.3  # Default fallback
    }
    aa  <- avg_gap / 3
    tau <- 5 * aa
```

- [ ] **Step 2: Verify**

```bash
cd "Missing Types"
SCENARIO_NAME="missing_MCAR_10pct_cca" TEST_RUN=true N_SIMS=2 Rscript missing_types_method_comparison_cca.R 2>&1 | grep -E "avg_gap|aa =|tau ="
```
Expected: `aa` and `tau` are smaller than before (censoring gap excluded).

- [ ] **Step 3: Commit**

```bash
cd "Missing Types"
git add simulation_runner.R
git commit -m "fix: exclude censoring intervals from avg_gap computation

avg_gap was computed over all intervals including the final
censoring row per subject, inflating aa and tau. Filter to
event rows only before computing inter-event gaps."
```

---

## Task 5: Remove duplicate set.seed before train-test split (MAJOR)

**File:** `Missing Types/simulation_runner.R` lines 396–398

**Problem:** `set.seed(seed)` is called again just before `sample()`, resetting the RNG to the function entry state. Imputation randomness does not flow into the split.

- [ ] **Step 1: Delete the duplicate set.seed block**

Remove lines 396–398:
```r
    if (!is.null(seed)) {
      set.seed(seed)
    }
```
(The first `set.seed(seed)` at function entry, lines 276–278, is retained.)

- [ ] **Step 2: Verify no duplicate set.seed exists**

```bash
grep -n "set.seed" "Missing Types/simulation_runner.R"
```
Expected: exactly one occurrence (the entry-level `set.seed(seed)` near line 277).

- [ ] **Step 3: Commit**

```bash
cd "Missing Types"
git add simulation_runner.R
git commit -m "fix: remove duplicate set.seed before train-test split

Second set.seed(seed) before sample() was resetting the RNG to the
initial function state, decoupling the split from imputation
randomness and creating spurious determinism."
```

---

## Task 6: Replace KM with Aalen-Johansen for competing-risks pseudo-observations (MAJOR)

**File:** `Missing Types/functions.R` — `generate_km_pseudoEst` function (lines ~746–838)

**Problem:** `survfit(Surv(time_to_event, event_type1) ~ 1)` treats the competing event type as random censoring, estimating cause-specific survival `S_k(tau)` rather than the cumulative incidence function `CIF_k(tau)`. The stated estimand is the mean cumulative function `mu_k(tau) = E[N_k(tau)]`, which equals `CIF_k(tau)` under competing risks. Under a two-type competing-risks DGP, KM is upward-biased relative to CIF.

**Scope:** Replace only `generate_km_pseudoEst` (used for CCA and IPW). The `generate_km_pseudoEst_weighted` function (RPM/DR fractional indicators) uses non-standard soft-event counts that require separate treatment; leave it as-is with an added comment.

- [ ] **Step 1: Add helper function `safe_aj_cif_est` above `generate_km_pseudoEst`**

Insert after `safe_surv_est` (around line 743) and before `generate_km_pseudoEst`:

```r
# Extract CIF estimate from Aalen-Johansen fit at time tau
# type: 1 or 2 (indexes pstate column 2 or 3 respectively)
safe_aj_cif_est <- function(fit, tau, type) {
  col_idx <- type + 1  # type 1 -> col 2, type 2 -> col 3
  tryCatch({
    s <- summary(fit, times = tau, extend = TRUE)
    if (!is.null(s$pstate) && ncol(s$pstate) >= col_idx) {
      return(as.numeric(s$pstate[1, col_idx]))
    }
    # fallback: last observed pstate value
    s2 <- summary(fit, extend = TRUE)
    if (!is.null(s2$pstate) && ncol(s2$pstate) >= col_idx) {
      return(as.numeric(tail(s2$pstate[, col_idx], 1)))
    }
    return(0)
  }, error = function(e) 0)
}
```

- [ ] **Step 2: Rewrite `generate_km_pseudoEst` to use Aalen-Johansen**

Replace the entire `generate_km_pseudoEst` function (lines ~746–839):

```r
# Generate Aalen-Johansen pseudo-observations for competing risks CIF.
# Replaces per-cause KM which treats competing events as censoring and
# targets cause-specific survival S_k(tau) rather than CIF_k(tau).
# CIF_k(tau) = P(event type k by tau) is the correct estimand for mu_k(tau).
#
# IPW weights are supported: pass ipw_weight column in data.
generate_km_pseudoEst <- function(data, tau) {
    data$pseudoEst_km_type1 <- NA
    data$pseudoEst_km_type2 <- NA

    unique_times <- sort(unique(data$checkin))

    for (tp in unique_times) {
        grp_data <- data %>% filter(checkin == tp)
        n_tp <- nrow(grp_data)

        if (n_tp < 2) next

        # Competing-risks status: 0 = censored, 1 = type 1, 2 = type 2
        # 'outcome' encodes the next event type (0 if no event by tau)
        status_cr <- factor(
          ifelse(is.na(grp_data$outcome) | grp_data$outcome == 0, 0, grp_data$outcome),
          levels = c(0, 1, 2)
        )

        use_weights <- "ipw_weight" %in% names(grp_data) &&
                       !all(is.na(grp_data$ipw_weight))
        wts <- if (use_weights) grp_data$ipw_weight else NULL

        # Fit full Aalen-Johansen estimator
        full_fit_aj <- tryCatch({
          if (use_weights) {
            survfit(Surv(grp_data$time_to_event, status_cr) ~ 1, weights = wts)
          } else {
            survfit(Surv(grp_data$time_to_event, status_cr) ~ 1)
          }
        }, error = function(e) NULL)

        if (is.null(full_fit_aj)) {
          next  # leave NAs for this landmark time
        }

        cif_full1 <- safe_aj_cif_est(full_fit_aj, tau, type = 1)
        cif_full2 <- safe_aj_cif_est(full_fit_aj, tau, type = 2)

        pseudo1 <- numeric(n_tp)
        pseudo2 <- numeric(n_tp)

        for (i in seq_len(n_tp)) {
            grp_minus_i   <- grp_data[-i, , drop = FALSE]
            status_minus_i <- status_cr[-i]
            wts_minus_i    <- if (use_weights) wts[-i] else NULL

            leave_fit <- tryCatch({
              if (use_weights) {
                survfit(Surv(grp_minus_i$time_to_event, status_minus_i) ~ 1,
                        weights = wts_minus_i)
              } else {
                survfit(Surv(grp_minus_i$time_to_event, status_minus_i) ~ 1)
              }
            }, error = function(e) NULL)

            cif_leave1 <- if (!is.null(leave_fit)) safe_aj_cif_est(leave_fit, tau, type = 1) else cif_full1
            cif_leave2 <- if (!is.null(leave_fit)) safe_aj_cif_est(leave_fit, tau, type = 2) else cif_full2

            pseudo1[i] <- n_tp * cif_full1 - (n_tp - 1) * cif_leave1
            pseudo2[i] <- n_tp * cif_full2 - (n_tp - 1) * cif_leave2
        }

        data$pseudoEst_km_type1[data$checkin == tp] <- pseudo1
        data$pseudoEst_km_type2[data$checkin == tp] <- pseudo2
    }

    return(data)
}
```

- [ ] **Step 3: Add explanatory comment to `generate_km_pseudoEst_weighted`**

At the top of `generate_km_pseudoEst_weighted` (line ~1717), add:

```r
# NOTE: This function uses a soft-event-weighted KM estimator with fractional
# event counts (from RPM/DR indicators). The AJ extension to fractional
# indicators requires separate theoretical development and is left as future
# work. The estimand is approximately CIF_k(tau) under mild fractional-count
# approximation assumptions.
```

- [ ] **Step 4: Verify pseudo-observations are generated**

```bash
cd "Missing Types"
SCENARIO_NAME="missing_MCAR_10pct_cca" TEST_RUN=true N_SIMS=2 Rscript missing_types_method_comparison_cca.R 2>&1 | grep -E "pseudoEst|CIF|AJ|Aalen|landmark"
```
Expected: no errors; "Pseudo-observation generation" messages appear; C-index values are printed in the summary.

- [ ] **Step 5: Spot-check CIF values are in [0,1]**

Add a temporary cat line after pseudo-obs generation in the test run, or check the RDS output:
```bash
# Check that pseudo-obs are in reasonable range (not ~1.0 as KM would give)
SCENARIO_NAME="missing_MCAR_10pct_cca" TEST_RUN=true N_SIMS=2 Rscript -e '
  source("simulation_engine.R"); source("functions.R"); source("simulation_runner.R")
  conf <- configure_simulation(c("cca"))
  set.seed(42)
  data <- rate_cox_data_gen_complex(n=50, f.alpha=0, r01=0.2, r02=0.15,
    rho=0.3, beta=c(1.5,1,1.2,1.5,0,0,0.5,0.3), complex_params=c(1,1,1,1), censor_max=4)
  data$type_true <- data$type
  avg_gap <- mean(data[data$event==1,] %>%
    arrange(pid,e.time) %>% group_by(pid) %>%
    mutate(g=e.time-lag(e.time)) %>% filter(!is.na(g)) %>% pull(g))
  aa <- avg_gap/3; tau <- 5*aa
  td <- transform_with_covariates_complex(data, aa)
  td <- generate_km_pseudoEst(td, tau)
  cat("pseudoEst_km_type1 range:", range(td$pseudoEst_km_type1, na.rm=TRUE), "\n")
  cat("pseudoEst_km_type2 range:", range(td$pseudoEst_km_type2, na.rm=TRUE), "\n")
' 2>&1 | grep "pseudoEst"
```
Expected: values roughly in [0, 0.5] for each type (CIF, not close to 1.0 as KM would give).

- [ ] **Step 6: Commit**

```bash
cd "Missing Types"
git add functions.R
git commit -m "fix: replace per-cause KM with Aalen-Johansen for pseudo-observations

KM treats competing events as censoring, estimating cause-specific
survival S_k(tau) rather than CIF_k(tau) = P(type k event by tau).
Under a two-type competing-risks DGP, KM is upward-biased.
Replace generate_km_pseudoEst() with AJ-based CIF estimation.
Add safe_aj_cif_est() helper. generate_km_pseudoEst_weighted()
(RPM/DR fractional indicators) is left as-is with explanatory comment."
```

---

## Task 7: Add error logging to silent model-fitting tryCatch blocks (MAJOR)

**File:** `Missing Types/simulation_runner.R` — seven silent `tryCatch` blocks at approx. lines 543, 582, 630, 678, 768, 845, 973

**Problem:** Model-fitting failures return NA with no record of why. Under 50% missingness, systematic failures in one method but not another produce biased mean C-indices without any visible signal.

- [ ] **Step 1: Add `failed_models` accumulator at start of `run_comprehensive_simulation`**

After `tryCatch({` at the start of the function body (around line 280), add:

```r
    # Accumulates model fitting failure messages for diagnostic output
    failed_models <- character(0)
```

- [ ] **Step 2: Replace all seven silent error handlers**

Each currently reads:
```r
      }, error = function(e) {
        # Keep NA if fitting fails
      })
```

Replace each with (using the appropriate model name label):

For RF Stratified Type 1 (~line 543):
```r
      }, error = function(e) {
        failed_models <<- c(failed_models,
          sprintf("rf_strat_type1: %s", conditionMessage(e)))
      })
```

For RF Stratified Type 2 (~line 582):
```r
      }, error = function(e) {
        failed_models <<- c(failed_models,
          sprintf("rf_strat_type2: %s", conditionMessage(e)))
      })
```

For MERFranger Stratified Type 1 (~line 630):
```r
      }, error = function(e) {
        failed_models <<- c(failed_models,
          sprintf("merf_strat_type1: %s", conditionMessage(e)))
      })
```

For MERFranger Stratified Type 2 (~line 678):
```r
      }, error = function(e) {
        failed_models <<- c(failed_models,
          sprintf("merf_strat_type2: %s", conditionMessage(e)))
      })
```

For MERFranger Covariate (~line 768):
```r
      }, error = function(e) {
        failed_models <<- c(failed_models,
          sprintf("merf_cov: %s", conditionMessage(e)))
      })
```

For RF + Time (~line 845):
```r
      }, error = function(e) {
        failed_models <<- c(failed_models,
          sprintf("rf_time: %s", conditionMessage(e)))
      })
```

For Cox PH (~line 973):
```r
      }, error = function(e) {
        failed_models <<- c(failed_models,
          sprintf("cox_hist: %s", conditionMessage(e)))
      })
```

- [ ] **Step 3: Add `failed_models` to the returned result list**

Find the `return(list(success = TRUE, ...))` at the end of `run_comprehensive_simulation`. Add `failed_models` to it:

```r
    return(list(
      success = TRUE,
      failed_models = if (length(failed_models) > 0)
                        paste(failed_models, collapse = "; ")
                      else NA_character_,
      # ... all existing fields ...
    ))
```

- [ ] **Step 4: Verify logging works**

Run a test scenario and check that a deliberately failing model would log:
```bash
cd "Missing Types"
SCENARIO_NAME="missing_MAR_50pct_dr" TEST_RUN=true N_SIMS=2 Rscript missing_types_method_comparison_dr.R 2>&1 | tail -20
```
Expected: simulation completes; any `failed_models` entries would appear in the summary.

- [ ] **Step 5: Commit**

```bash
cd "Missing Types"
git add simulation_runner.R
git commit -m "fix: log model fitting errors instead of silently returning NA

Seven tryCatch blocks were swallowing all model fitting errors with
no output. Under high missingness, systematic failures in one method
produced biased mean C-indices with no visible signal. Accumulate
failure messages in failed_models and include in result list."
```

---

## Task 8: Fix parallel RNG — add L'Ecuyer-CMRG to PSOCK cluster (MAJOR)

**File:** `Missing Types/simulation_engine.R` lines 226–259

**Problem:** PSOCK workers inherit the parent process RNG state. Without `RNGkind("L'Ecuyer-CMRG")` + `clusterSetRNGStream()`, concurrent workers can draw correlated random variates.

- [ ] **Step 1: Add RNG initialization after makeCluster**

In `run_chunked_simulations`, after line 226 (`cl <- makeCluster(...)`), insert:

```r
        # Initialize independent L'Ecuyer-CMRG streams for each worker.
        # Must be set on the master before clusterExport/clusterEvalQ.
        RNGkind("L'Ecuyer-CMRG")
        clusterSetRNGStream(cl, iseed = 20260326)
```

- [ ] **Step 2: Restore default RNG kind on master after stopCluster**

After `stopCluster(cl); rm(cl); aggressive_gc()` (line 259), add:

```r
        RNGkind("default")  # restore master RNG to Mersenne Twister
```

- [ ] **Step 3: Verify**

```bash
cd "Missing Types"
SCENARIO_NAME="missing_MCAR_10pct_cca" TEST_RUN=true N_SIMS=4 CHUNK_SIZE=2 Rscript missing_types_method_comparison_cca.R 2>&1 | grep -E "Cluster|worker|RNG|seed"
```
Expected: cluster setup messages appear; no RNG errors.

- [ ] **Step 4: Commit**

```bash
cd "Missing Types"
git add simulation_engine.R
git commit -m "fix: initialize L'Ecuyer-CMRG RNG streams for PSOCK parallel workers

PSOCK workers were not initialized with independent RNG streams.
Add RNGkind + clusterSetRNGStream after makeCluster to give each
worker a non-overlapping L'Ecuyer-CMRG stream."
```

---

## Task 9: Fix LaTeX table copy-paste bug and figure standards (MODERATE)

**File:** `Missing Types/analyze_missing_types_results.R`

### 9a: Fix Joint RF Type 2 gold-standard column

- [ ] **Step 1: Locate and fix line ~895**

Find the `method_map` tribble. Locate the "Joint RF" row:
```r
    "Joint RF",        "c_rf_time_type1_mean",              "c_rf_time_type1_true_mean",                "c_rf_time_type2_mean",              "c_rf_time_type2_mean",
```
Replace last field:
```r
    "Joint RF",        "c_rf_time_type1_mean",              "c_rf_time_type1_true_mean",                "c_rf_time_type2_mean",              "c_rf_time_type2_true_mean",
```

### 9b: Fix Okabe-Ito color palette

- [ ] **Step 2: Replace non-Okabe-Ito colors**

Search for `#2E86AB` and `#A23B72` in the file. Replace both `scale_fill_manual` / `scale_color_manual` blocks:

```r
# Replace any occurrence of:
scale_fill_manual(values = c("type1" = "#2E86AB", "type2" = "#A23B72"))
# and
scale_color_manual(values = c("type1" = "#2E86AB", "type2" = "#A23B72"))

# With:
scale_fill_manual(
  values = c("type1" = "#56B4E9", "type2" = "#D55E00"),  # Okabe-Ito sky_blue, vermilion
  labels = c("type1" = "Type 1", "type2" = "Type 2"),
  name   = "Event Type"
)
```

### 9c: Add `bg = "white"` to all ggsave calls

- [ ] **Step 3: Add bg = "white" to every ggsave**

Search for `ggsave(` in the file. For each call, add `bg = "white"` if not present:
```r
ggsave(filename = filepath, plot = p, width = ..., height = ..., dpi = 300, units = "in", bg = "white")
```

### 9d: Fix deprecated `size` aesthetic in geom_errorbar

- [ ] **Step 4: Replace size with linewidth**

```bash
sed -i '' 's/geom_errorbar(\(.*\)size = /geom_errorbar(\1linewidth = /g' "Missing Types/analyze_missing_types_results.R"
```
Or manually find `geom_errorbar` occurrences and change `size = 0.5` to `linewidth = 0.5`.

### 9e: Update Last Updated header

- [ ] **Step 5: Update header date**

Line ~9: change `# Last Updated: 2026-02-23` to `# Last Updated: 2026-03-26`

### 9f: Add `library(here)` and `set.seed`

- [ ] **Step 6: Add missing library and seed**

In the package loading block at the top, add:
```r
suppressPackageStartupMessages({
  library(here)        # added: required for here::here() path fixes
  library(dplyr); library(tidyr); library(ggplot2)
  library(stringr); library(purrr); library(tibble)
})
set.seed(20260326)     # project convention: seed at top of every script
```

- [ ] **Step 7: Verify analysis script runs**

```bash
cd "Missing Types"
# Only run if results files exist; otherwise just syntax check
Rscript -e 'source("analyze_missing_types_results.R")' 2>&1 | head -30
```
Expected: no syntax errors; package loads succeed.

- [ ] **Step 8: Commit**

```bash
cd "Missing Types"
git add analyze_missing_types_results.R
git commit -m "fix: LaTeX table copy-paste bug and figure standard violations

- Joint RF Type 2 gold-standard column was duplicating CC value
- Replace non-Okabe-Ito colors with sky_blue/vermilion palette
- Add bg='white' to all ggsave calls
- Change deprecated size= to linewidth= in geom_errorbar
- Add library(here) and set.seed(20260326)
- Update Last Updated header to 2026-03-26"
```

---

## Task 10: Update session log and session summary

- [ ] **Step 1: Append to today's session log**

Append to `quality_reports/session_logs/2026-03-26_missing-types-simplify-review.md`:

```
- [HH:MM] Missing Types/simulation_runner.R — T1: fixed RPM/DR training filter (fractional rows now included); T2: added XX2 to IPW propensity features; T4: excluded censoring from avg_gap; T5: removed duplicate set.seed; T7: added model failure logging
- [HH:MM] Missing Types/functions.R — T3: replaced DR sum-normalization with per-component clipping; T6: replaced per-cause KM with Aalen-Johansen CIF in generate_km_pseudoEst
- [HH:MM] Missing Types/simulation_engine.R — T8: added L'Ecuyer-CMRG initialization for PSOCK workers
- [HH:MM] Missing Types/analyze_missing_types_results.R — T9: fixed LaTeX copy-paste bug, Okabe-Ito colors, bg=white, linewidth, set.seed, library(here)
```

- [ ] **Step 2: Final end-to-end test run**

```bash
cd "Missing Types"
TEST_RUN=true N_SIMS=2 bash run_missing_types_all_methods.sh 2>&1 | grep -E "COMPLETED|ERROR|success|failed_models"
```
Expected: all methods complete with `COMPLETED: 2/2 successful`; no `ERROR` lines.

---

## Self-Review Checklist

### Spec coverage

| Issue | Task | Covered |
|-------|------|---------|
| C1: RPM/DR training filter | T1 | ✓ |
| C2: IPW missing XX2 | T2 | ✓ |
| M1: DR normalization | T3 | ✓ |
| M2: KM → AJ | T6 | ✓ (unweighted; weighted documented) |
| M3: avg_gap censoring | T4 | ✓ |
| M4: L'Ecuyer-CMRG | T8 | ✓ |
| M5: double set.seed | T5 | ✓ |
| M6: silent errors | T7 | ✓ |
| M7: LaTeX copy-paste | T9a | ✓ |
| Figure standards | T9b-f | ✓ |
| CLAUDE.md documentation fix | T2 step 4 | ✓ |

### Out of scope (deferred)

- MNAR scenario: requires new DGP function — separate task
- n=300/500 scenarios: adds 16 new scenarios — separate task after verifying fixes
- Frailty variation: requires new scenario grid — separate task
- Monte Carlo SE in results: analysis-layer addition — separate task
- MERF prediction random effects documentation: minor, add comment when touching those blocks
- `generate_km_pseudoEst_weighted` AJ extension: requires theoretical development — documented with comment in T6
