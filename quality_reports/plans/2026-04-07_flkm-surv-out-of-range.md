# FL-KM Out-of-Range Survival NA Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `surv_after < 0` bug in `generate_flkm_pseudoEst()` so that IPW/DR groups where the fractional event weight exceeds the risk weight sum produce NA pseudo-observations instead of extreme finite values; update the validation analysis script to distinguish "correctly handled invalidity" (invalid state detected, NA propagated) from "invalid-but-unflagged internal failure" (invalid state present, but extreme finite pseudo produced).

**Architecture:** Two code bugs in `functions.R`: (a) `.flkm_survival_one_group_details()` records `survival_out_of_unit_interval` but does not set `surv_val <- NA_real_; break`; (b) `.flkm_survival_one_group()` fast path has no `surv_after < 0` guard at all; (c) positional arg misalignment in three row-level `.flkm_append_invalid_state()` calls at the jackknife caller level. One pipeline classification bug in `flkm_warning_validation_analysis.R`: `invalid_anchor` audit rows with `pseudo = NA` are misclassified as "invalid-but-unflagged internal failure" instead of "correctly handled invalidity". Fix order: code first → analysis script → delete old Longleaf validation artifacts → rerun first-pass → rerun trace-extract → diagnose.

**Tech Stack:** R 4.4.0, `dplyr`, existing `functions.R` internal helpers (`.flkm_survival_one_group_details`, `.flkm_survival_one_group`, `.flkm_append_invalid_state`). No new packages.

---

## Context for Implementer

### Why this matters

The validation pipeline classifies `Stage: complete, Cause: core FL-KM bug` because 105 of 210 audited rows are `invalid-but-unflagged internal failure`. Investigation shows:

- **30 rows**: `pseudo` = extreme finite value (−0.70 to 5.64), n_t = 12–15, method = IPW/DR. Root cause: `.flkm_survival_one_group_details()` records `survival_out_of_unit_interval` after the KM step produces `surv_after < 0`, but then continues — the bad value propagates into `surv_f`/`surv_m` at the jackknife caller, producing a finite extreme pseudo-obs that does not trigger the first-pass range warning.
- **75 rows**: `pseudo = NA` (correctly NA'd by earlier fixes), but `trace_invalidity = TRUE` because `nrow(invalid_subset) > 0`. The pipeline has no "correctly handled" class — any `invalid_anchor` row with an entry in the invalid_state_table becomes "invalid-but-unflagged internal failure".
- **105 "benign jackknife overshoot" rows**: no issue.

### Why `surv_after < 0` happens

For IPW method: `d_total += current_weight[idx] * ipw_weight_event`. If one subject has extreme IPW weight (e.g., 0.01 censoring probability → weight = 100) and only 12 subjects are at risk (`y_total = 12`), then `d_total = 100 > 12` → `surv_val = 1 * (1 - 100/12) = −7.33` → `surv_after < 0`.

### The fast path gap

`validation_mode = "none"` (main simulation) uses `.flkm_survival_one_group()`. This function already has the `y_total <= 0` guard from the previous fix session, but has **no** `surv_after < 0` guard. The main simulation silently produces extreme pseudo-obs for groups where `d_total > y_total`.

---

## File Map

| File | Change |
|------|--------|
| `Missing Types/functions.R` | Bug A: add `surv_val <- NA_real_; break` in `.flkm_survival_one_group_details()`; Bug B: same guard in `.flkm_survival_one_group()` fast path; Bug C: fix positional args in three row-level calls; update `Last Updated: 2026-04-07` |
| `Missing Types/flkm_warning_validation_analysis.R` | Add "correctly handled invalidity" audit class; update `recommend_flkm_validation_action()`; update `Last Updated: 2026-04-07` |
| `Missing Types/test_flkm_surv_out_of_range.R` | New test: IPW extreme weights → NA pseudo, no finite extreme values; normal groups → non-NA |
| `Missing Types/CLAUDE.md` | Add one-line note about `surv_out_of_unit_interval` guard to Critical Details |
| `quality_reports/session_logs/2026-04-07_flkm-surv-out-of-range.md` | Session log |

`simulation_runner.R` — no change needed.

---

## Task 1: Fix `functions.R` — three bugs

**Files:**
- Modify: `Missing Types/functions.R:1159-1169` (Bug A — detailed path guard)
- Modify: `Missing Types/functions.R:1501-1503` (Bug B — fast path guard)
- Modify: `Missing Types/functions.R:1627-1635` (Bug C — positional args)
- Modify: `Missing Types/functions.R:7` (Last Updated)

### Bug A — detailed path: add `surv_val <- NA_real_; break` after `survival_out_of_unit_interval`

- [ ] **Step 1: Edit the `survival_out_of_unit_interval` block**

Find lines 1159–1169 in `functions.R`:
```r
        if (!is.finite(surv_after) || surv_after < 0 || surv_after > 1) {
            invalid_state_table <- .flkm_append_invalid_state(
                invalid_state_table = invalid_state_table,
                trace_scope = trace_scope,
                event_time = t_j,
                variable_name = "survival_after",
                value = surv_after,
                failure_type = "survival_out_of_unit_interval",
                anchor_type = "event"
            )
        }
```

Replace with:
```r
        if (!is.finite(surv_after) || surv_after < 0 || surv_after > 1) {
            invalid_state_table <- .flkm_append_invalid_state(
                invalid_state_table = invalid_state_table,
                trace_scope = trace_scope,
                event_time = t_j,
                variable_name = "survival_after",
                value = surv_after,
                failure_type = "survival_out_of_unit_interval",
                anchor_type = "event"
            )
            # Fractional event weight exceeded the risk weight sum; the KM estimate is
            # irrecoverable. Break and propagate NA — same pattern as the denominator
            # guards above (nonpositive_denominator, nonfinite_denominator).
            surv_val <- NA_real_
            break
        }
```

### Bug B — fast path: add `surv_after < 0` guard in `.flkm_survival_one_group()`

- [ ] **Step 2: Edit the fast path KM update block**

Find lines 1501–1503 (inside `.flkm_survival_one_group()`):
```r
        if (d_total > 0) {
            surv_val <- surv_val * (1 - d_total / y_total)
        }

        for (idx in event_subject_idx) {
```

Replace with:
```r
        if (d_total > 0) {
            surv_val <- surv_val * (1 - d_total / y_total)
        }
        # Fast path: no invalidity table, but still NA-propagate on out-of-range survival
        # (same condition as survival_out_of_unit_interval in the detailed path).
        if (is.finite(surv_val) && (surv_val < 0 || surv_val > 1)) {
            surv_val <- NA_real_
            break
        }

        for (idx in event_subject_idx) {
```

### Bug C — fix positional arg misalignment in three row-level calls

The three calls at lines ~1627–1635 use positional args, which mis-maps `failure_type` into `event_subject_id`. Fix to named args.

- [ ] **Step 3: Fix the three positional calls**

Find the block (lines ~1627–1635):
```r
                if (!is.finite(surv_f) || surv_f < 0 || surv_f > 1)
                    full_inv <- .flkm_append_invalid_state(full_inv,  row_id_i, "full",
                                    "surv_full", surv_f, "surv_full_out_of_unit_interval", "row")
                if (!is.finite(surv_m) || surv_m < 0 || surv_m > 1)
                    minus_inv <- .flkm_append_invalid_state(minus_inv, row_id_i, "leave_one_out",
                                    "surv_minus_i", surv_m, "surv_minus_i_out_of_unit_interval", "row")
                if (!is.finite(pseudo_val))
                    minus_inv <- .flkm_append_invalid_state(minus_inv, row_id_i, "leave_one_out",
                                    "pseudo", pseudo_val, "nonfinite_pseudo", "row")
```

Replace with:
```r
                if (!is.finite(surv_f) || surv_f < 0 || surv_f > 1)
                    full_inv <- .flkm_append_invalid_state(full_inv,
                                    row_id = row_id_i, trace_scope = "full",
                                    variable_name = "surv_full", value = surv_f,
                                    failure_type = "surv_full_out_of_unit_interval",
                                    anchor_type = "row")
                if (!is.finite(surv_m) || surv_m < 0 || surv_m > 1)
                    minus_inv <- .flkm_append_invalid_state(minus_inv,
                                    row_id = row_id_i, trace_scope = "leave_one_out",
                                    variable_name = "surv_minus_i", value = surv_m,
                                    failure_type = "surv_minus_i_out_of_unit_interval",
                                    anchor_type = "row")
                if (!is.finite(pseudo_val))
                    minus_inv <- .flkm_append_invalid_state(minus_inv,
                                    row_id = row_id_i, trace_scope = "leave_one_out",
                                    variable_name = "pseudo", value = pseudo_val,
                                    failure_type = "nonfinite_pseudo",
                                    anchor_type = "row")
```

- [ ] **Step 4: Update `Last Updated` header**

Line 7 of `functions.R`:
```r
# Last Updated: 2026-04-06
```
→
```r
# Last Updated: 2026-04-07
```

- [ ] **Step 5: Verify with grep**

```bash
grep -n "survival_out_of_unit_interval\|surv_val <- NA_real_\|surv_full_out_of_unit_interval\|row_id = row_id_i" \
  "Missing Types/functions.R"
```

Expected: 
- Three hits for `surv_val <- NA_real_` (one per guard: nonfinite_denominator, nonpositive_denominator, and the new one)
- One hit for `survival_out_of_unit_interval` in the detailed path
- One hit for `surv_full_out_of_unit_interval` (named arg, Bug C fix)
- No hit for the old positional pattern `"surv_full", surv_f, "surv_full_out_of_unit_interval"`

- [ ] **Step 6: Commit**

```bash
cd "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/Missing Types" && \
  git add functions.R && \
  git commit -m "fix(flkm): NA-propagate on surv_after < 0 in both KM paths; fix positional args

Bug A: .flkm_survival_one_group_details() recorded survival_out_of_unit_interval
but continued computing — fractional IPW event weight > risk weight sum caused
surv_after < 0, which propagated to extreme finite pseudo-obs undetected by the
first-pass range warning. Fix: surv_val <- NA_real_; break (same pattern as the
nonpositive_denominator guards from 2026-04-06).

Bug B: .flkm_survival_one_group() fast path (validation_mode='none', used in
the main simulation) lacked any surv_after guard. Fix: add identical NA+break
guard after the KM update step.

Bug C: three .flkm_append_invalid_state() calls at the jackknife caller level
used positional args, placing the failure_type string in event_subject_id and
leaving failure_type = NA in the invalid_state_table. Fix: named args."
```

---

## Task 2: Fix `flkm_warning_validation_analysis.R` — audit classification and recommendation

**Files:**
- Modify: `Missing Types/flkm_warning_validation_analysis.R:~961–995` (audit class + pseudo field)
- Modify: `Missing Types/flkm_warning_validation_analysis.R:1117–1120` (recommendation)
- Modify: `Missing Types/flkm_warning_validation_analysis.R:7` (Last Updated)

### Fix 1: add "correctly handled invalidity" audit class

- [ ] **Step 1: Edit `summarize_flkm_trace_audit` — `audit_class` + `pseudo` field**

Find the block (lines ~961–978):
```r
    trace_invalidity <- flkm_trace_has_invalidity(trace_subset) || nrow(invalid_subset) > 0
    audit_class <- if (identical(req$trace_target_type, "flagged_row")) {
      if (trace_invalidity) "FL-KM invalidity" else "benign jackknife overshoot"
    } else if (trace_invalidity) {
      "invalid-but-unflagged internal failure"
    } else {
      NA_character_
    }

    data.frame(
      scenario_name = req$scenario_name,
      imputation_method = req$imputation_method,
      seed = req$seed,
      row_id = ifelse(is.na(req$row_id), NA_character_, req$row_id),
      invalid_anchor_id = ifelse(is.na(req$invalid_anchor_id), NA_character_, req$invalid_anchor_id),
      event_type = if (nrow(pseudo_subset) > 0) pseudo_subset$event_type[1] else req$event_type,
      n_t = if (nrow(pseudo_subset) > 0) pseudo_subset$n_t[1] else req$n_t,
      pseudo = if (nrow(pseudo_subset) > 0) pseudo_subset$pseudo[1] else req$pseudo,
```

Replace with:
```r
    # Resolve the pseudo value once — used for both the output field and audit_class.
    # Prefer the first-pass pseudo_rows record; fall back to the audit_request_table value.
    pseudo_for_audit <- if (nrow(pseudo_subset) > 0) pseudo_subset$pseudo[1] else req$pseudo

    trace_invalidity <- flkm_trace_has_invalidity(trace_subset) || nrow(invalid_subset) > 0
    audit_class <- if (identical(req$trace_target_type, "flagged_row")) {
      if (trace_invalidity) "FL-KM invalidity" else "benign jackknife overshoot"
    } else if (trace_invalidity) {
      # For invalid_anchor requests: if pseudo = NA, the invalid state was detected and
      # correctly propagated via NA arithmetic (nonpositive_denominator,
      # surv_out_of_unit_interval, etc.) — not a code defect.
      # Only classify as a bug when a finite extreme pseudo survived despite the invalid state.
      if (is.na(pseudo_for_audit)) "correctly handled invalidity" else "invalid-but-unflagged internal failure"
    } else {
      NA_character_
    }

    data.frame(
      scenario_name = req$scenario_name,
      imputation_method = req$imputation_method,
      seed = req$seed,
      row_id = ifelse(is.na(req$row_id), NA_character_, req$row_id),
      invalid_anchor_id = ifelse(is.na(req$invalid_anchor_id), NA_character_, req$invalid_anchor_id),
      event_type = if (nrow(pseudo_subset) > 0) pseudo_subset$event_type[1] else req$event_type,
      n_t = if (nrow(pseudo_subset) > 0) pseudo_subset$n_t[1] else req$n_t,
      pseudo = pseudo_for_audit,
```

### Fix 2: update `recommend_flkm_validation_action()`

- [ ] **Step 2: Edit `has_invalid_state` check**

Find lines 1117–1120:
```r
  has_invalid_state <- (nrow(first_pass_summary) > 0 &&
                          any(first_pass_summary$has_invalid_internal_state %in% TRUE, na.rm = TRUE)) ||
    (nrow(audited_rows) > 0 &&
       any(audited_rows$audit_class %in% c("FL-KM invalidity", "invalid-but-unflagged internal failure"), na.rm = TRUE))
```

Replace with:
```r
  # Recommendation is only made when stage = "complete" (trace_extract_complete = TRUE),
  # so audited_rows is always populated. Rely solely on the trace audit classification —
  # "correctly handled invalidity" rows produced NA pseudo via a detected guard and are
  # not defects. The first_pass_summary$has_invalid_internal_state flag is too coarse:
  # it fires for any invalid state regardless of whether it was handled correctly.
  has_invalid_state <- nrow(audited_rows) > 0 &&
    any(audited_rows$audit_class %in% c("FL-KM invalidity", "invalid-but-unflagged internal failure"),
        na.rm = TRUE)
```

- [ ] **Step 3: Update `Last Updated` header**

Line 7 of `flkm_warning_validation_analysis.R`:
```r
# Last Updated: 2026-04-05 (RNG fix + trace_present for invalid_anchor type)
```
→
```r
# Last Updated: 2026-04-07
```

- [ ] **Step 4: Commit**

```bash
cd "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/Missing Types" && \
  git add flkm_warning_validation_analysis.R && \
  git commit -m "fix(validation): add 'correctly handled invalidity' audit class; refine recommendation

When an invalid state (nonpositive_denominator, surv_out_of_unit_interval) is
detected and the guard correctly sets pseudo = NA, the audit should record this
as 'correctly handled invalidity', not 'invalid-but-unflagged internal failure'.
The cause_classification 'core FL-KM bug' fires on the latter class only, so
after both functions.R and analysis fixes, correctly-NA'd rows no longer trigger
the core-bug classification.

Also refine recommend_flkm_validation_action(): drop the
first_pass_summary\$has_invalid_internal_state check (too coarse — fires for
correctly-handled NA rows) and rely solely on audited_rows classification when
trace extract is complete."
```

---

## Task 3: Write focused test `test_flkm_surv_out_of_range.R`

**Files:**
- Create: `Missing Types/test_flkm_surv_out_of_range.R`

**Purpose:** Verify (a) IPW group where `ipw_weight_event > n_at_risk` produces NA pseudo-obs (not extreme finite); (b) normal IPW group produces non-NA pseudo-obs; (c) no finite pseudo-obs fall outside [−0.5, 1.5].

- [ ] **Step 1: Create the test script**

```r
# ============================================================================
# METADATA
# ============================================================================
# Description: Focused test for generate_flkm_pseudoEst() surv_out_of_unit_interval
#              guard. Verifies that extreme IPW weights (d_total > y_total) produce
#              NA pseudo-obs rather than finite extreme values.
# Last Updated: 2026-04-07
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(here)
})
source(here::here("functions.R"))

set.seed(20260407)

# ---- helpers ----------------------------------------------------------------

make_ipw_event_row <- function(id, time, type = 1L, ipw_weight = 1.0) {
  # One event row for IPW: observed type, ipw_weight_event = ipw_weight.
  # All other weight columns set to values that won't trigger RPM/DR paths.
  data.frame(
    id            = id,
    time          = time,
    gap_time      = time,
    type          = type,
    observed_type = TRUE,
    prob_type1    = NA_real_,
    prob_type2    = NA_real_,
    ipw_weight_event   = ipw_weight,
    event_type1_rpm    = NA_real_,
    event_type2_rpm    = NA_real_,
    event_type1_dr     = NA_real_,
    event_type2_dr     = NA_real_,
    stringsAsFactors = FALSE
  )
}

# ---- build dataset ----------------------------------------------------------
# extreme_group: n=5 subjects at checkin=1, one event has ipw_weight_event=6 > 5
#   → d_total = 6, y_total = 5 → surv_after = 1*(1-6/5) = -0.2 < 0 → NA pseudo
# normal_group:  n=15 subjects at checkin=2, one event has ipw_weight_event=1
#   → d_total = 1, y_total = 15 → surv_after = 14/15 ∈ (0,1) → valid pseudo

tau <- 2.0

extreme_ids <- paste0("e", 1:5)
normal_ids  <- paste0("n", 1:15)

landmark_data <- bind_rows(
  data.frame(id = extreme_ids, checkin = 1, stringsAsFactors = FALSE),
  data.frame(id = normal_ids,  checkin = 2, stringsAsFactors = FALSE)
)

# Extreme group: subject e1 has a type-1 event with extreme IPW weight
extreme_events <- bind_rows(
  make_ipw_event_row("e1", 0.5, type = 1L, ipw_weight = 6.0),  # weight > n=5
  # Other extreme-group subjects have no events (censored before tau)
  data.frame(
    id = paste0("e", 2:5), time = 2.1, gap_time = 2.1,
    type = NA_integer_, observed_type = FALSE,
    prob_type1 = NA_real_, prob_type2 = NA_real_,
    ipw_weight_event = 1.0,
    event_type1_rpm = NA_real_, event_type2_rpm = NA_real_,
    event_type1_dr = NA_real_, event_type2_dr = NA_real_,
    stringsAsFactors = FALSE
  )
)

# Normal group: one type-1 event per subject with ipw_weight=1
normal_events <- lapply(normal_ids, function(id) {
  make_ipw_event_row(id, 0.5, type = 1L, ipw_weight = 1.0)
})
normal_events <- bind_rows(normal_events)

event_data <- bind_rows(extreme_events, normal_events)

# ---- Test 1: extreme IPW group (n=5, weight=6) → NA pseudo ------------------
cat("Test 1: extreme IPW group (d_total > y_total) → NA pseudo ... ")
result <- generate_flkm_pseudoEst(
  landmark_data  = landmark_data,
  event_data     = event_data,
  tau            = tau,
  method         = "ipw",
  min_group_size = 2L  # allow n=5 to be computed (not skipped by size guard)
)

extreme_rows <- result[result$checkin == 1, ]
stopifnot(
  "extreme group type1 pseudo should be NA" = all(is.na(extreme_rows$pseudoEst_km_type1))
)
cat("PASS\n")

# ---- Test 2: normal IPW group (n=15, weight=1) → non-NA pseudo --------------
cat("Test 2: normal IPW group (d_total < y_total) → non-NA pseudo ... ")
normal_rows <- result[result$checkin == 2, ]
stopifnot(
  "normal group type1 pseudo should be non-NA" = any(!is.na(normal_rows$pseudoEst_km_type1))
)
cat("PASS\n")

# ---- Test 3: no finite pseudo-obs outside [-0.5, 1.5] -----------------------
cat("Test 3: no finite pseudo outside [-0.5, 1.5] ... ")
all_pseudo <- c(result$pseudoEst_km_type1, result$pseudoEst_km_type2)
extreme_finite <- is.finite(all_pseudo) & (all_pseudo < -0.5 | all_pseudo > 1.5)
stopifnot(
  "no finite pseudo should be outside [-0.5, 1.5]" = !any(extreme_finite, na.rm = TRUE)
)
cat("PASS\n")

# ---- Test 4: validation_mode="first_pass" also produces NA for extreme group -
cat("Test 4: validation_mode=first_pass, extreme group → NA pseudo ... ")
result_fp <- generate_flkm_pseudoEst(
  landmark_data       = landmark_data,
  event_data          = event_data,
  tau                 = tau,
  method              = "ipw",
  validation_mode     = "first_pass",
  min_group_size      = 2L
)

# first_pass returns a validation payload, not pseudo columns directly.
# The payload's pseudo_rows$pseudo should be NA for the extreme group.
if (is.list(result_fp) && is.data.frame(result_fp$pseudo_rows)) {
  extreme_pseudo_fp <- result_fp$pseudo_rows$pseudo[result_fp$pseudo_rows$checkin == 1]
  stopifnot(
    "first_pass extreme group pseudo should be NA" = all(is.na(extreme_pseudo_fp))
  )
  cat("PASS\n")
} else {
  cat("SKIP (first_pass returned data frame, not payload — pseudo columns checked in Test 1)\n")
}

cat("\nAll tests passed.\n")
```

- [ ] **Step 2: Run the test**

```bash
cd "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/Missing Types" && \
  Rscript test_flkm_surv_out_of_range.R
```

Expected output:
```
Test 1: extreme IPW group (d_total > y_total) → NA pseudo ... PASS
Test 2: normal IPW group (d_total < y_total) → non-NA pseudo ... PASS
Test 3: no finite pseudo outside [-0.5, 1.5] ... PASS
Test 4: validation_mode=first_pass, extreme group → NA pseudo ... PASS (or SKIP)

All tests passed.
```

**If Test 1 fails with non-NA pseudo:** The `generate_flkm_pseudoEst()` return structure may differ from expectation, or `ipw_weight_event = 6` with n=5 wasn't enough to trigger `d_total > y_total` (check whether the formula excludes the triggering subject from y_total). Try `ipw_weight = 10` and verify the formula: `d_total = 1 * 6 = 6`, `y_total = 5 × 1 = 5` → `1 - 6/5 = −0.2`.

**If Test 4 is SKIP:** Not a failure — first_pass mode may return a different structure. Check whether `generate_flkm_pseudoEst(..., validation_mode = "first_pass")` returns a list with `$pseudo_rows` or a data frame. Adjust the check accordingly.

- [ ] **Step 3: Commit**

```bash
cd "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/Missing Types" && \
  git add test_flkm_surv_out_of_range.R && \
  git commit -m "test(flkm): verify surv_after < 0 guard produces NA pseudo for extreme IPW weights"
```

---

## Task 4: Update `Missing Types/CLAUDE.md`

**Files:**
- Modify: `Missing Types/CLAUDE.md` — Critical Details section

- [ ] **Step 1: Add one line to Critical Details**

In the Critical Details section, after the existing `min_group_size` bullet, append:
```markdown
**`surv_out_of_unit_interval` guard:** When the KM step produces `surv_after < 0` (fractional IPW/DR event weight exceeds risk weight sum), `.flkm_survival_one_group_details()` and `.flkm_survival_one_group()` now set `surv_val <- NA_real_; break` and propagate NA to pseudo-obs. Groups n_t = 11–16 triggered this in validation (2026-04-07). Affected methods: IPW, IPW-RF, DR, DR-RF (any method with `ipw_weight_event > 1`).
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/Missing Types" && \
  git add CLAUDE.md && \
  git commit -m "docs(claude-md): document surv_out_of_unit_interval guard in Critical Details"
```

---

## Task 5: Longleaf — delete old validation artifacts and rerun

**Why rerun:** The current first-pass validation payloads were generated with the old (buggy) code, so those 30 `surv_after < 0` rows have extreme finite pseudo-obs in `pseudo_rows`. After fixing `functions.R`, a fresh first-pass run will produce `pseudo = NA` for those rows. The analysis script classification fix only triggers correctly when the first-pass pseudo_rows reflect the fixed code.

- [ ] **Step 1: Sync fixed code to Longleaf**

On your local machine, sync only the changed R files:
```bash
rsync -av \
  "Missing Types/functions.R" \
  "Missing Types/flkm_warning_validation_analysis.R" \
  longleaf:~/Missing\ Types/
```

- [ ] **Step 2: On Longleaf — delete old validation files**

```bash
cd ~/Missing\ Types
# Delete all first-pass and trace-extract RDS files (keeps submit scripts and manifests)
rm -f results_missing_types/flkm_warning_validation/scenario_*_first_pass_validation.rds
rm -f results_missing_types/flkm_warning_validation/scenario_*_trace_extract_*.rds
# Also delete the cached summary CSVs so they're regenerated fresh
rm -f results_missing_types/flkm_warning_validation/audited_row_summary.csv
rm -f results_missing_types/flkm_warning_validation/validation_decision_summary.csv
rm -f results_missing_types/flkm_warning_validation/first_pass_overall_summary.csv
rm -f results_missing_types/flkm_warning_validation/first_pass_warning_summary.csv
```

- [ ] **Step 3: Submit first-pass jobs**

```bash
cd ~/Missing\ Types
sbatch --array=0-20 submit_flkm_warning_validation_first_pass.sh
```

21 jobs (one per scenario × method cell). Expected wall time ~1.5h each.

- [ ] **Step 4: After first-pass finishes — sync results and diagnose**

On local machine:
```bash
rsync -av longleaf:~/Missing\ Types/results_missing_types/flkm_warning_validation/ \
  "Missing Types/results_missing_types/flkm_warning_validation/"
```

Then run diagnosis:
```bash
cd "Missing Types" && R_MAX_VSIZE=32G Rscript run_flkm_warning_validation_diagnosis.R
```

Expected: `Stage: awaiting_trace_extract` (some rows will still have `invalid_internal_state_flag = TRUE` and become `invalid_anchor` audit requests, triggering trace-extract).

**If `Stage: complete` with `Cause: no issues` or a benign cause:** skip Task 5 Step 5 — no trace-extract needed.

**If `Stage: complete, Cause: core FL-KM bug`:** the classification fix in Task 2 didn't take effect for some rows — check whether `pseudo_for_audit` is still finite extreme for any `invalid-but-unflagged` rows using `audited_row_summary.csv`.

- [ ] **Step 5: Submit trace-extract jobs (if awaiting)**

Check the new manifest:
```bash
wc -l results_missing_types/flkm_warning_validation/trace_extract_manifest.tsv
```

On Longleaf:
```bash
cd ~/Missing\ Types
# Delete old trace files (from previous run)
rm -f results_missing_types/flkm_warning_validation/scenario_*_trace_extract_*.rds
# Submit — use array size from manifest row count minus 1
sbatch --array=0-$(( $(wc -l < results_missing_types/flkm_warning_validation/trace_extract_manifest.tsv) - 2 )) \
  submit_flkm_warning_validation_trace_extract.sh
```

Wait for completion, sync, and rerun diagnosis.

Expected final result:
```
Stage: complete
Cause classification: benign jackknife overshoot  (or general small-group jackknife sensitivity)
Final recommendation: rerun full grid as-is  (or rerun full grid after warning/diagnostic patch)
```

---

## Task 6: Write session log

**Files:**
- Create: `quality_reports/session_logs/2026-04-07_flkm-surv-out-of-range.md`

- [ ] **Step 1: Create the session log**

```markdown
# Session Log: FL-KM Out-of-Range Survival NA Fix

**Date:** 2026-04-07
**Goal:** Eliminate remaining `core FL-KM bug` classification after fix 2 (zero-denominator NA).

## Root Cause

Validation pipeline (trace-extract complete) produced 105 `invalid-but-unflagged internal failure` rows:
- 30 rows: extreme finite pseudo (−0.70 to 5.64), n_t = 11–16, IPW/DR methods.
  Root cause: `.flkm_survival_one_group_details()` recorded `survival_out_of_unit_interval`
  when `d_total > y_total` (extreme IPW upweighting) but continued, propagating the negative
  survival value to `pseudo_val`. The fast path `.flkm_survival_one_group()` had no guard at all.
- 75 rows: NA pseudo (correctly handled by earlier fixes), mis-classified as bugs because
  the pipeline had no "correctly handled invalidity" class.
- 3 fixes also: positional arg misalignment in row-level `.flkm_append_invalid_state()` calls.

## Fixes

### functions.R
- Added `surv_val <- NA_real_; break` after `survival_out_of_unit_interval` recording
  in `.flkm_survival_one_group_details()` (detailed path)
- Added identical `surv_val <- NA_real_; break` guard in `.flkm_survival_one_group()`
  fast path (validation_mode="none", used in main simulation)
- Fixed positional arg bug in three row-level `.flkm_append_invalid_state()` calls:
  `failure_type` was landing in `event_subject_id`, leaving `failure_type = NA` in table

### flkm_warning_validation_analysis.R
- Added "correctly handled invalidity" audit class for `invalid_anchor` requests where
  `pseudo = NA` (invalid state detected and NA propagated correctly)
- Updated `recommend_flkm_validation_action()`: removed `has_invalid_internal_state` check
  from first_pass_summary (too coarse); rely solely on audited_rows classification

## Changes

- `Missing Types/functions.R` — three bugs fixed; `Last Updated: 2026-04-07`
- `Missing Types/flkm_warning_validation_analysis.R` — classification + recommendation; `Last Updated: 2026-04-07`
- `Missing Types/test_flkm_surv_out_of_range.R` — new focused test (4 assertions)
- `Missing Types/CLAUDE.md` — documented guard in Critical Details

## Verification

Longleaf: deleted old first-pass + trace-extract files, reran first-pass (21 jobs), then
trace-extract. Final diagnosis: TBD.
```

- [ ] **Step 2: Commit (parent repo)**

```bash
cd "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research" && \
  git add quality_reports/session_logs/2026-04-07_flkm-surv-out-of-range.md \
          quality_reports/plans/2026-04-07_flkm-surv-out-of-range.md && \
  git commit -m "docs: session log and plan for FL-KM surv_out_of_unit_interval fix"
```

---

## Self-Review

**Spec coverage check:**
- [x] `surv_after < 0` guard in detailed path → Task 1 Bug A
- [x] `surv_after < 0` guard in fast path (main simulation) → Task 1 Bug B
- [x] Positional arg fix → Task 1 Bug C
- [x] "correctly handled invalidity" audit class → Task 2 Fix 1
- [x] Recommendation no longer fires for correctly-NA'd rows → Task 2 Fix 2
- [x] Unit test verifies NA outcome for extreme IPW weights → Task 3
- [x] Longleaf rerun to regenerate first-pass pseudo_rows with fixed code → Task 5
- [x] Session log → Task 6

**Placeholder scan:** none found.

**Type consistency:** `pseudo_for_audit` is introduced once (Task 2) and used in two places (`pseudo =` field and `audit_class` logic) — consistent.

**One open question:** After the fix, more NA pseudo-obs will appear in `validation_mode = "none"` (main simulation). Downstream model fitting in `simulation_runner.R` may error if `randomForest`/`ranger` receive NA outcomes. Check the first production-like local run output for "NA/NaN/Inf in 'y'" errors and add `na.omit()` before model fitting if needed. This is a follow-up, not part of this plan.
