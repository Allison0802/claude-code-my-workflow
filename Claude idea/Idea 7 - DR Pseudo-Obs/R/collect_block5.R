# ============================================================================
# METADATA
# ============================================================================
# Description: Collect and validate Block 5 results (MCAR vs MAR comparison).
#              Reads per-scenario summary CSVs, checks kill criteria.
# Kill criteria:
#   - DR-PO-CF valid under both MCAR and MAR
#   - Efficiency cost (MAR vs MCAR variance ratio) <= 15%
# Last Updated: 2026-03-22
# ============================================================================

library(here)
library(tidyverse)

# ============================================================================
# CONFIGURATION
# ============================================================================
RESULTS_DIR <- here::here("results")
SCENARIOS <- c("MCAR_20", "MCAR_30", "MCAR_50", "MAR_20", "MAR_30", "MAR_50")

cat("============================================\n")
cat("Block 5 Results Collection\n")
cat("============================================\n\n")

# ============================================================================
# READ FILES
# ============================================================================
files_found <- character(0)
files_missing <- character(0)
results_list <- list()

for (sc in SCENARIOS) {
  fname <- file.path(RESULTS_DIR, paste0("block5_", sc, "_summary.csv"))
  if (file.exists(fname)) {
    files_found <- c(files_found, fname)
    df <- read.csv(fname)
    # Parse scenario into pattern and rate
    parts <- strsplit(sc, "_")[[1]]
    df$miss_pattern <- parts[1]
    df$miss_pct <- as.integer(parts[2])
    df$scenario <- sc
    results_list[[sc]] <- df
    cat(sprintf("  [OK] Found: block5_%s_summary.csv (%d rows)\n", sc, nrow(df)))
  } else {
    files_missing <- c(files_missing, fname)
    cat(sprintf("  [MISSING] block5_%s_summary.csv\n", sc))
  }
}

if (length(files_found) == 0) {
  cat("\nNo Block 5 results found. Has the experiment been run?\n")
  quit(status = 0)
}

cat(sprintf("\nFiles found: %d / %d\n\n", length(files_found), length(SCENARIOS)))

# ============================================================================
# COMBINE
# ============================================================================
combined <- bind_rows(results_list)

# ============================================================================
# KILL CRITERIA
# ============================================================================
cat("--------------------------------------------\n")
cat("Kill Criteria Checks\n")
cat("--------------------------------------------\n")

pass_all <- TRUE

# Identify columns
cov_col <- intersect(c("coverage", "coverage_95", "ci_coverage"), names(combined))
var_col <- intersect(c("variance", "mc_variance", "se", "mc_se"), names(combined))
est_col <- intersect(c("estimator", "method", "model"), names(combined))

# Criterion 1: Valid under both MCAR and MAR (coverage >= 93%)
if (length(cov_col) > 0 && length(est_col) > 0) {
  cov_col <- cov_col[1]
  est_col <- est_col[1]

  dr_rows <- combined %>%
    filter(grepl("DR|dr|drpo|cf", .data[[est_col]], ignore.case = TRUE))

  if (nrow(dr_rows) > 0) {
    # Check MCAR
    mcar_dr <- dr_rows %>% filter(miss_pattern == "MCAR")
    if (nrow(mcar_dr) > 0) {
      min_mcar_cov <- min(mcar_dr[[cov_col]], na.rm = TRUE)
      crit_mcar <- min_mcar_cov >= 0.93
      cat(sprintf("  [%s] DR valid under MCAR: min coverage = %.1f%%\n",
                  ifelse(crit_mcar, "PASS", "FAIL"), min_mcar_cov * 100))
      if (!crit_mcar) pass_all <- FALSE
    }

    # Check MAR
    mar_dr <- dr_rows %>% filter(miss_pattern == "MAR")
    if (nrow(mar_dr) > 0) {
      min_mar_cov <- min(mar_dr[[cov_col]], na.rm = TRUE)
      crit_mar <- min_mar_cov >= 0.93
      cat(sprintf("  [%s] DR valid under MAR: min coverage = %.1f%%\n",
                  ifelse(crit_mar, "PASS", "FAIL"), min_mar_cov * 100))
      if (!crit_mar) pass_all <- FALSE
    }
  } else {
    cat("  [SKIP] No DR estimator rows found\n")
  }
} else {
  cat("  [SKIP] Cannot check coverage -- required columns not found\n")
}

# Criterion 2: Efficiency cost <= 15% (MAR variance / MCAR variance)
if (length(var_col) > 0 && length(est_col) > 0) {
  var_col_use <- var_col[1]
  est_col_use <- ifelse(length(est_col) > 0, est_col[1], NA)

  if (!is.na(est_col_use)) {
    dr_rows <- combined %>%
      filter(grepl("DR|dr|drpo|cf", .data[[est_col_use]], ignore.case = TRUE))

    # Compare at each shared missingness rate
    shared_pcts <- intersect(
      dr_rows$miss_pct[dr_rows$miss_pattern == "MCAR"],
      dr_rows$miss_pct[dr_rows$miss_pattern == "MAR"]
    )

    if (length(shared_pcts) > 0) {
      for (pct in shared_pcts) {
        mcar_var <- dr_rows %>%
          filter(miss_pattern == "MCAR", miss_pct == pct) %>%
          pull(!!sym(var_col_use)) %>%
          mean(na.rm = TRUE)

        mar_var <- dr_rows %>%
          filter(miss_pattern == "MAR", miss_pct == pct) %>%
          pull(!!sym(var_col_use)) %>%
          mean(na.rm = TRUE)

        if (!is.na(mcar_var) && !is.na(mar_var) && mcar_var > 0) {
          eff_cost <- (mar_var - mcar_var) / mcar_var
          crit_eff <- eff_cost <= 0.15
          cat(sprintf("  [%s] Efficiency cost at %d%%: %.1f%% (MAR/MCAR variance ratio)\n",
                      ifelse(crit_eff, "PASS", "FAIL"), pct, eff_cost * 100))
          if (!crit_eff) pass_all <- FALSE
        }
      }
    } else {
      cat("  [SKIP] No matching MCAR/MAR rates for efficiency comparison\n")
    }
  }
} else {
  cat("  [SKIP] Cannot check efficiency -- no variance column found\n")
  cat("         Available columns:", paste(names(combined), collapse = ", "), "\n")
}

# ============================================================================
# VERDICT
# ============================================================================
cat("\n--------------------------------------------\n")
if (length(files_missing) > 0) {
  cat(sprintf("INCOMPLETE: %d of %d scenarios missing\n",
              length(files_missing), length(SCENARIOS)))
} else if (pass_all) {
  cat("VERDICT: PASS -- DR valid under both MCAR and MAR with acceptable efficiency\n")
} else {
  cat("VERDICT: FAIL -- Kill criteria not met (see above)\n")
}
cat("--------------------------------------------\n\n")

# ============================================================================
# SAVE
# ============================================================================
out_path <- file.path(RESULTS_DIR, "block5_combined_summary.csv")
write.csv(combined, out_path, row.names = FALSE)
cat(sprintf("Combined table saved to: %s\n", out_path))
cat(sprintf("Total rows: %d\n", nrow(combined)))

cat("\n")
print(combined, row.names = FALSE)
