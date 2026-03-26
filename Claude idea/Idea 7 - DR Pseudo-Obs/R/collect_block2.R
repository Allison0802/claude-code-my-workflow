# ============================================================================
# METADATA
# ============================================================================
# Description: Collect and validate Block 2 results (DR 2x2 matrix).
#              Reads per-estimator summary CSVs, builds the robustness matrix,
#              and checks kill criteria.
# Kill criteria:
#   - One-correct estimators: bias < 0.01
#   - Both-wrong estimator: bias > 0.02
# Last Updated: 2026-03-22
# ============================================================================

library(here)
library(tidyverse)

# ============================================================================
# CONFIGURATION
# ============================================================================
RESULTS_DIR <- here::here("results")
ESTIMATORS <- c("both_correct", "prop_wrong", "out_wrong",
                "both_wrong", "ipw_only", "or_only")

cat("============================================\n")
cat("Block 2 Results Collection\n")
cat("============================================\n\n")

# ============================================================================
# READ FILES
# ============================================================================
files_found <- character(0)
files_missing <- character(0)
results_list <- list()

for (est in ESTIMATORS) {
  fname <- file.path(RESULTS_DIR, paste0("block2_", est, "_summary.csv"))
  if (file.exists(fname)) {
    files_found <- c(files_found, fname)
    df <- read.csv(fname)
    df$estimator <- est
    results_list[[est]] <- df
    cat(sprintf("  [OK] Found: block2_%s_summary.csv (%d rows)\n", est, nrow(df)))
  } else {
    files_missing <- c(files_missing, fname)
    cat(sprintf("  [MISSING] block2_%s_summary.csv\n", est))
  }
}

if (length(files_found) == 0) {
  cat("\nNo Block 2 results found. Has the experiment been run?\n")
  quit(status = 0)
}

cat(sprintf("\nFiles found: %d / %d\n\n", length(files_found), length(ESTIMATORS)))

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

# Identify bias column
bias_col <- intersect(c("bias", "mean_bias", "abs_bias"), names(combined))

if (length(bias_col) > 0) {
  bias_col <- bias_col[1]

  # Criterion 1: One-correct estimators have bias < 0.01
  one_correct <- c("prop_wrong", "out_wrong")  # one nuisance wrong, one correct
  one_correct_data <- combined %>% filter(estimator %in% one_correct)

  if (nrow(one_correct_data) > 0) {
    max_one_correct_bias <- max(abs(one_correct_data[[bias_col]]), na.rm = TRUE)
    crit1 <- max_one_correct_bias < 0.01
    cat(sprintf("  [%s] One-correct bias < 0.01: max |bias| = %.6f\n",
                ifelse(crit1, "PASS", "FAIL"), max_one_correct_bias))
    if (!crit1) pass_all <- FALSE
  } else {
    cat("  [SKIP] No one-correct estimator results available\n")
  }

  # Criterion 2: Both-wrong has bias > 0.02
  both_wrong_data <- combined %>% filter(estimator == "both_wrong")

  if (nrow(both_wrong_data) > 0) {
    both_wrong_bias <- max(abs(both_wrong_data[[bias_col]]), na.rm = TRUE)
    crit2 <- both_wrong_bias > 0.02
    cat(sprintf("  [%s] Both-wrong bias > 0.02: |bias| = %.6f\n",
                ifelse(crit2, "PASS", "FAIL"), both_wrong_bias))
    if (!crit2) pass_all <- FALSE
  } else {
    cat("  [SKIP] No both-wrong estimator results available\n")
  }
} else {
  cat("  [SKIP] Cannot check bias -- no bias column found\n")
  cat("         Available columns:", paste(names(combined), collapse = ", "), "\n")
}

# ============================================================================
# 2x2 MATRIX DISPLAY
# ============================================================================
cat("\n--------------------------------------------\n")
cat("Double-Robustness Matrix\n")
cat("--------------------------------------------\n")
cat("\n                  | Outcome Correct | Outcome Wrong\n")
cat("  ----------------+-----------------+--------------\n")

# Try to build the 2x2 display
if (length(bias_col) > 0) {
  get_bias <- function(est_name) {
    row <- combined %>% filter(estimator == est_name)
    if (nrow(row) > 0) sprintf("%.4f", row[[bias_col]][1]) else "---"
  }
  cat(sprintf("  Prop. Correct   |     %s      |    %s\n",
              get_bias("both_correct"), get_bias("out_wrong")))
  cat(sprintf("  Prop. Wrong     |     %s      |    %s\n",
              get_bias("prop_wrong"), get_bias("both_wrong")))
  cat(sprintf("\n  IPW-only: %s   |   OR-only: %s\n",
              get_bias("ipw_only"), get_bias("or_only")))
}

# ============================================================================
# VERDICT
# ============================================================================
cat("\n--------------------------------------------\n")
if (length(files_missing) > 0) {
  cat(sprintf("INCOMPLETE: %d of %d estimators missing\n",
              length(files_missing), length(ESTIMATORS)))
} else if (pass_all) {
  cat("VERDICT: PASS -- Double robustness confirmed\n")
} else {
  cat("VERDICT: FAIL -- Kill criteria not met (see above)\n")
}
cat("--------------------------------------------\n\n")

# ============================================================================
# SAVE
# ============================================================================
out_path <- file.path(RESULTS_DIR, "block2_combined_summary.csv")
write.csv(combined, out_path, row.names = FALSE)
cat(sprintf("Combined table saved to: %s\n", out_path))
cat(sprintf("Total rows: %d\n", nrow(combined)))

cat("\n")
print(combined, row.names = FALSE)
