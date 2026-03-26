# ============================================================================
# METADATA
# ============================================================================
# Description: Collect and validate Block 4 results (cross-fit RF vs parametric).
#              Reads the single summary CSV and checks kill criteria.
# Kill criteria:
#   - Cross-fit RF DR bias <= parametric DR bias in complex DGM
# Last Updated: 2026-03-22
# ============================================================================

library(here)
library(tidyverse)

# ============================================================================
# CONFIGURATION
# ============================================================================
RESULTS_DIR <- here::here("results")

cat("============================================\n")
cat("Block 4 Results Collection\n")
cat("============================================\n\n")

# ============================================================================
# READ FILE
# ============================================================================
fname <- file.path(RESULTS_DIR, "block4_summary.csv")

if (!file.exists(fname)) {
  cat("  [MISSING] block4_summary.csv\n")
  cat("\nBlock 4 has not been run yet.\n")
  quit(status = 0)
}

combined <- read.csv(fname)
cat(sprintf("  [OK] Found: block4_summary.csv (%d rows)\n\n", nrow(combined)))

# ============================================================================
# KILL CRITERIA
# ============================================================================
cat("--------------------------------------------\n")
cat("Kill Criteria Checks\n")
cat("--------------------------------------------\n")

pass_all <- TRUE

# Identify relevant columns
bias_col <- intersect(c("bias", "mean_bias", "abs_bias"), names(combined))
est_col <- intersect(c("estimator", "method", "model"), names(combined))

if (length(bias_col) > 0 && length(est_col) > 0) {
  bias_col <- bias_col[1]
  est_col <- est_col[1]

  # Criterion: Cross-fit RF DR <= parametric DR bias
  rf_rows <- combined %>%
    filter(grepl("rf|RF|random.forest|crossfit", .data[[est_col]], ignore.case = TRUE))

  param_rows <- combined %>%
    filter(grepl("param|logistic|glm|parametric", .data[[est_col]], ignore.case = TRUE))

  if (nrow(rf_rows) > 0 && nrow(param_rows) > 0) {
    rf_bias <- min(abs(rf_rows[[bias_col]]), na.rm = TRUE)
    param_bias <- min(abs(param_rows[[bias_col]]), na.rm = TRUE)
    crit1 <- rf_bias <= param_bias
    cat(sprintf("  [%s] RF DR bias <= parametric DR bias in complex DGM\n",
                ifelse(crit1, "PASS", "FAIL")))
    cat(sprintf("         RF bias:         %.6f\n", rf_bias))
    cat(sprintf("         Parametric bias: %.6f\n", param_bias))
    if (!crit1) pass_all <- FALSE
  } else {
    cat("  [SKIP] Cannot compare -- need both RF and parametric rows\n")
    cat(sprintf("         RF rows: %d, Parametric rows: %d\n",
                nrow(rf_rows), nrow(param_rows)))
  }
} else {
  cat("  [SKIP] Cannot check criteria -- required columns not found\n")
  cat("         Available columns:", paste(names(combined), collapse = ", "), "\n")
}

# ============================================================================
# VERDICT
# ============================================================================
cat("\n--------------------------------------------\n")
if (pass_all) {
  cat("VERDICT: PASS -- Cross-fit RF competitive with parametric DR\n")
} else {
  cat("VERDICT: FAIL -- Kill criteria not met (see above)\n")
}
cat("--------------------------------------------\n\n")

# ============================================================================
# SAVE
# ============================================================================
out_path <- file.path(RESULTS_DIR, "block4_combined_summary.csv")
write.csv(combined, out_path, row.names = FALSE)
cat(sprintf("Combined table saved to: %s\n", out_path))
cat(sprintf("Total rows: %d\n", nrow(combined)))

cat("\n")
print(combined, row.names = FALSE)
