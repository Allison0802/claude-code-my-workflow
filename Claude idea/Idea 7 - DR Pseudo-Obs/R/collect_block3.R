# ============================================================================
# METADATA
# ============================================================================
# Description: Collect and validate Block 3 results (bias under missingness).
#              Reads per-missingness-rate summary CSVs, checks kill criteria.
# Kill criteria:
#   - DR-PO-CF coverage >= 93% at all missingness rates
#   - Naive estimator shows visible undercoverage
# Last Updated: 2026-03-22
# ============================================================================

library(here)
library(tidyverse)

# ============================================================================
# CONFIGURATION
# ============================================================================
RESULTS_DIR <- here::here("results")
MISS_PCTS <- c(10, 20, 30, 50)

cat("============================================\n")
cat("Block 3 Results Collection\n")
cat("============================================\n\n")

# ============================================================================
# READ FILES
# ============================================================================
files_found <- character(0)
files_missing <- character(0)
results_list <- list()

for (pct in MISS_PCTS) {
  fname <- file.path(RESULTS_DIR, paste0("block3_miss", pct, "_summary.csv"))
  if (file.exists(fname)) {
    files_found <- c(files_found, fname)
    df <- read.csv(fname)
    df$miss_pct <- pct
    results_list[[as.character(pct)]] <- df
    cat(sprintf("  [OK] Found: block3_miss%d_summary.csv (%d rows)\n", pct, nrow(df)))
  } else {
    files_missing <- c(files_missing, fname)
    cat(sprintf("  [MISSING] block3_miss%d_summary.csv\n", pct))
  }
}

if (length(files_found) == 0) {
  cat("\nNo Block 3 results found. Has the experiment been run?\n")
  quit(status = 0)
}

cat(sprintf("\nFiles found: %d / %d\n\n", length(files_found), length(MISS_PCTS)))

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

# Identify coverage column
cov_col <- intersect(c("coverage", "coverage_95", "ci_coverage"), names(combined))
est_col <- intersect(c("estimator", "method", "model"), names(combined))

if (length(cov_col) > 0 && length(est_col) > 0) {
  cov_col <- cov_col[1]
  est_col <- est_col[1]

  # Criterion 1: DR-PO-CF coverage >= 93%
  dr_rows <- combined %>%
    filter(grepl("DR|dr|drpo|cf", .data[[est_col]], ignore.case = TRUE))

  if (nrow(dr_rows) > 0) {
    min_dr_cov <- min(dr_rows[[cov_col]], na.rm = TRUE)
    crit1 <- min_dr_cov >= 0.93
    cat(sprintf("  [%s] DR-PO-CF coverage >= 93%%: min = %.1f%%\n",
                ifelse(crit1, "PASS", "FAIL"), min_dr_cov * 100))
    if (!crit1) pass_all <- FALSE
  } else {
    cat("  [SKIP] No DR estimator rows found\n")
  }

  # Criterion 2: Naive undercoverage visible
  naive_rows <- combined %>%
    filter(grepl("naive|cca|complete", .data[[est_col]], ignore.case = TRUE))

  if (nrow(naive_rows) > 0) {
    max_naive_cov <- max(naive_rows[[cov_col]], na.rm = TRUE)
    crit2 <- max_naive_cov < 0.93
    cat(sprintf("  [%s] Naive undercoverage visible: max naive coverage = %.1f%%\n",
                ifelse(crit2, "PASS", "FAIL"), max_naive_cov * 100))
    if (!crit2) pass_all <- FALSE
  } else {
    cat("  [SKIP] No naive estimator rows found\n")
  }
} else {
  cat("  [SKIP] Cannot check criteria -- required columns not found\n")
  cat("         Available columns:", paste(names(combined), collapse = ", "), "\n")
}

# ============================================================================
# VERDICT
# ============================================================================
cat("\n--------------------------------------------\n")
if (length(files_missing) > 0) {
  cat(sprintf("INCOMPLETE: %d of %d missingness rates missing\n",
              length(files_missing), length(MISS_PCTS)))
} else if (pass_all) {
  cat("VERDICT: PASS -- DR-PO-CF maintains coverage; naive degrades\n")
} else {
  cat("VERDICT: FAIL -- Kill criteria not met (see above)\n")
}
cat("--------------------------------------------\n\n")

# ============================================================================
# SAVE
# ============================================================================
out_path <- file.path(RESULTS_DIR, "block3_combined_summary.csv")
write.csv(combined, out_path, row.names = FALSE)
cat(sprintf("Combined table saved to: %s\n", out_path))
cat(sprintf("Total rows: %d\n", nrow(combined)))

cat("\n")
print(combined, row.names = FALSE)
