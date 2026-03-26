# ============================================================================
# METADATA
# ============================================================================
# Description: Collect and validate Block 1 results (IF variance sanity check).
#              Reads per-sample-size summary CSVs, checks kill criteria, and
#              combines into a single table.
# Kill criteria:
#   - Oracle bias < 0.005 at all n
#   - Coverage >= 93% at n >= 500
# Last Updated: 2026-03-22
# ============================================================================

library(here)
library(tidyverse)

# ============================================================================
# CONFIGURATION
# ============================================================================
RESULTS_DIR <- here::here("results")
EXPECTED_SIZES <- c(200, 500, 1000, 2000)

cat("============================================\n")
cat("Block 1 Results Collection\n")
cat("============================================\n\n")

# ============================================================================
# READ FILES
# ============================================================================
files_found <- character(0)
files_missing <- character(0)
results_list <- list()

for (n in EXPECTED_SIZES) {
  fname <- file.path(RESULTS_DIR, paste0("block1_n", n, "_summary.csv"))
  if (file.exists(fname)) {
    files_found <- c(files_found, fname)
    df <- read.csv(fname)
    df$n_size <- n
    results_list[[as.character(n)]] <- df
    cat(sprintf("  [OK] Found: block1_n%d_summary.csv (%d rows)\n", n, nrow(df)))
  } else {
    files_missing <- c(files_missing, fname)
    cat(sprintf("  [MISSING] block1_n%d_summary.csv\n", n))
  }
}

if (length(files_found) == 0) {
  cat("\nNo Block 1 results found. Has the experiment been run?\n")
  quit(status = 0)
}

cat(sprintf("\nFiles found: %d / %d\n\n", length(files_found), length(EXPECTED_SIZES)))

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

# Criterion 1: Oracle bias < 0.005 at all sample sizes
if ("bias" %in% names(combined) && "estimator" %in% names(combined)) {
  oracle_rows <- combined %>%
    filter(grepl("oracle", estimator, ignore.case = TRUE))

  if (nrow(oracle_rows) > 0) {
    max_oracle_bias <- max(abs(oracle_rows$bias), na.rm = TRUE)
    crit1 <- max_oracle_bias < 0.005
    cat(sprintf("  [%s] Oracle bias < 0.005: max |bias| = %.6f\n",
                ifelse(crit1, "PASS", "FAIL"), max_oracle_bias))
    if (!crit1) pass_all <- FALSE
  } else {
    cat("  [SKIP] No oracle estimator rows found\n")
  }
} else {
  # Try alternative column names
  if ("mean_bias" %in% names(combined)) {
    max_oracle_bias <- max(abs(combined$mean_bias[grepl("oracle", combined$estimator, ignore.case = TRUE)]), na.rm = TRUE)
    crit1 <- max_oracle_bias < 0.005
    cat(sprintf("  [%s] Oracle bias < 0.005: max |bias| = %.6f\n",
                ifelse(crit1, "PASS", "FAIL"), max_oracle_bias))
    if (!crit1) pass_all <- FALSE
  } else {
    cat("  [SKIP] Cannot check oracle bias -- column 'bias' not found\n")
    cat("         Available columns:", paste(names(combined), collapse = ", "), "\n")
  }
}

# Criterion 2: Coverage >= 93% at n >= 500
cov_col <- intersect(c("coverage", "coverage_95", "ci_coverage"), names(combined))
if (length(cov_col) > 0) {
  cov_col <- cov_col[1]
  large_n <- combined %>% filter(n_size >= 500)
  if (nrow(large_n) > 0) {
    min_coverage <- min(large_n[[cov_col]], na.rm = TRUE)
    crit2 <- min_coverage >= 0.93
    cat(sprintf("  [%s] Coverage >= 93%% at n >= 500: min coverage = %.1f%%\n",
                ifelse(crit2, "PASS", "FAIL"), min_coverage * 100))
    if (!crit2) pass_all <- FALSE
  } else {
    cat("  [SKIP] No results with n >= 500 yet\n")
  }
} else {
  cat("  [SKIP] Cannot check coverage -- no coverage column found\n")
  cat("         Available columns:", paste(names(combined), collapse = ", "), "\n")
}

# ============================================================================
# VERDICT
# ============================================================================
cat("\n--------------------------------------------\n")
if (length(files_missing) > 0) {
  cat(sprintf("INCOMPLETE: %d of %d sample sizes missing\n",
              length(files_missing), length(EXPECTED_SIZES)))
} else if (pass_all) {
  cat("VERDICT: PASS -- Block 1 sanity check passed\n")
} else {
  cat("VERDICT: FAIL -- Kill criteria not met (see above)\n")
}
cat("--------------------------------------------\n\n")

# ============================================================================
# SAVE
# ============================================================================
out_path <- file.path(RESULTS_DIR, "block1_combined_summary.csv")
write.csv(combined, out_path, row.names = FALSE)
cat(sprintf("Combined table saved to: %s\n", out_path))
cat(sprintf("Total rows: %d\n", nrow(combined)))

# Print summary table
cat("\n")
print(combined, row.names = FALSE)
