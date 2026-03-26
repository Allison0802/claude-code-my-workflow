# =============================================================================
# collect_block2.R
# Collect and summarize Block 2 (Double-Robustness Matrix) results
# Checks kill criterion, produces 2x2 matrix table for main paper
# Last Updated: 2026-03-21
# =============================================================================

suppressPackageStartupMessages(library(tidyverse))
library(here)

script_dir <- tryCatch(
  dirname(here::here("R/collect_block2.R")),
  error = function(e) "."
)

results_dir <- file.path(script_dir, "results", "block2")
csv_files   <- list.files(results_dir, pattern = "block2_.*\\.csv$", full.names = TRUE)

if (length(csv_files) == 0) {
  stop("No Block 2 result CSV files found in: ", results_dir)
}

cat(sprintf("Found %d result files:\n", length(csv_files)))
cat(paste(" ", basename(csv_files), collapse = "\n"), "\n\n")

all_results <- bind_rows(lapply(csv_files, read.csv))
cat(sprintf("Total rows: %d\n\n", nrow(all_results)))

# ---- Summary table: 2x2 DR matrix ----
summary_df <- all_results %>%
  group_by(estimator, history_stratum, k) %>%
  summarise(
    n_reps       = n(),
    mu_true      = mean(mu_true, na.rm = TRUE),
    mu_hat       = mean(mu_hat, na.rm = TRUE),
    bias         = mean(bias, na.rm = TRUE),
    abs_bias     = mean(abs(bias), na.rm = TRUE),
    rmse         = sqrt(mean(sq_err, na.rm = TRUE)),
    coverage_95  = mean(cover_95, na.rm = TRUE),
    avg_se       = mean(se, na.rm = TRUE),
    mc_sd        = sd(mu_hat, na.rm = TRUE),
    .groups      = "drop"
  ) %>%
  arrange(estimator, history_stratum, k)

summary_file <- file.path(results_dir, "block2_summary.csv")
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("Summary saved to %s\n\n", summary_file))

# ---- 2x2 Matrix display ----
cat("=== DOUBLE-ROBUSTNESS 2x2 MATRIX (averaged over strata and types) ===\n\n")

dr_conditions <- c("DR-both-correct", "DR-G-wrong", "DR-OR-wrong", "DR-both-wrong")
matrix_summary <- summary_df %>%
  filter(estimator %in% dr_conditions) %>%
  group_by(estimator) %>%
  summarise(
    avg_abs_bias = mean(abs(bias), na.rm = TRUE),
    max_abs_bias = max(abs(bias), na.rm = TRUE),
    avg_coverage = mean(coverage_95, na.rm = TRUE),
    min_coverage = min(coverage_95, na.rm = TRUE),
    avg_rmse     = mean(rmse, na.rm = TRUE),
    .groups = "drop"
  )
print(as.data.frame(matrix_summary), digits = 4)

# ---- Kill criterion check ----
cat("\n=== KILL CRITERION CHECK ===\n")
cat("Separation test: one-correct should have bias << both-wrong\n\n")

one_correct <- summary_df %>%
  filter(estimator %in% c("DR-G-wrong", "DR-OR-wrong")) %>%
  summarise(avg_bias = mean(abs(bias), na.rm = TRUE))

both_wrong <- summary_df %>%
  filter(estimator == "DR-both-wrong") %>%
  summarise(avg_bias = mean(abs(bias), na.rm = TRUE))

both_correct <- summary_df %>%
  filter(estimator == "DR-both-correct") %>%
  summarise(avg_bias = mean(abs(bias), na.rm = TRUE))

cat(sprintf("Both-correct avg |bias|:  %.4f\n", both_correct$avg_bias))
cat(sprintf("One-correct avg |bias|:   %.4f\n", one_correct$avg_bias))
cat(sprintf("Both-wrong avg |bias|:    %.4f\n", both_wrong$avg_bias))
cat(sprintf("Separation ratio (both-wrong / one-correct): %.2f\n",
            both_wrong$avg_bias / max(one_correct$avg_bias, 1e-6)))

if (both_wrong$avg_bias > 2 * one_correct$avg_bias) {
  cat("\n*** BLOCK 2 GATE: PASS ***\n")
  cat("Clear separation between one-correct and both-wrong conditions.\n")
} else {
  cat("\n*** BLOCK 2 GATE: FAIL ***\n")
  cat("Insufficient separation. Investigate nuisance model specification.\n")
}

# ---- Comparison with single-robust ----
cat("\n=== COMPARISON: DR vs SINGLE-ROBUST ===\n")
comp_df <- summary_df %>%
  group_by(estimator) %>%
  summarise(
    avg_abs_bias = mean(abs(bias), na.rm = TRUE),
    avg_coverage = mean(coverage_95, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(avg_abs_bias)
print(as.data.frame(comp_df), digits = 4)
