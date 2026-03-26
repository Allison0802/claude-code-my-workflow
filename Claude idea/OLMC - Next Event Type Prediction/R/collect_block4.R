# =============================================================================
# collect_block4.R
# Collect and summarize Block 4 (CR Comparison) results
# Last Updated: 2026-03-21
# =============================================================================

suppressPackageStartupMessages(library(tidyverse))
library(here)

script_dir <- tryCatch(
  dirname(here::here("R/collect_block4.R")),
  error = function(e) "."
)

results_dir <- file.path(script_dir, "results", "block4")
csv_files   <- list.files(results_dir, pattern = "block4_.*\\.csv$", full.names = TRUE)

if (length(csv_files) == 0) {
  stop("No Block 4 result CSV files found in: ", results_dir)
}

cat(sprintf("Found %d result files:\n", length(csv_files)))
all_results <- bind_rows(lapply(csv_files, read.csv))
cat(sprintf("Total rows: %d\n\n", nrow(all_results)))

summary_df <- all_results %>%
  group_by(estimator, history_stratum, k) %>%
  summarise(
    n_reps       = n(),
    mu_true      = mean(mu_true, na.rm = TRUE),
    bias         = mean(bias, na.rm = TRUE),
    abs_bias     = mean(abs(bias), na.rm = TRUE),
    rmse         = sqrt(mean(sq_err, na.rm = TRUE)),
    coverage_95  = mean(cover_95, na.rm = TRUE),
    .groups      = "drop"
  ) %>%
  arrange(estimator, history_stratum, k)

summary_file <- file.path(results_dir, "block4_summary.csv")
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("Summary saved to %s\n\n", summary_file))

# ---- Focus on post-recurrence strata (H1, H2, H3) ----
cat("=== POST-RECURRENCE PERFORMANCE (H1, H2, H3 only) ===\n")
post_rec <- summary_df %>%
  filter(history_stratum %in% c("H1", "H2", "H3")) %>%
  group_by(estimator) %>%
  summarise(
    avg_abs_bias = mean(abs(bias), na.rm = TRUE),
    max_abs_bias = max(abs(bias), na.rm = TRUE),
    avg_coverage = mean(coverage_95, na.rm = TRUE),
    n_strata_k   = n(),
    .groups = "drop"
  ) %>%
  arrange(avg_abs_bias)
print(as.data.frame(post_rec), digits = 4)

# ---- Kill criterion ----
cat("\n=== KILL CRITERION CHECK ===\n")

# Check: what fraction of landmark rows have prior events?
if ("pct_with_history" %in% names(all_results)) {
  pct <- mean(all_results$pct_with_history, na.rm = TRUE)
  cat(sprintf("Fraction of landmark rows with prior events: %.1f%%\n", pct * 100))
  if (pct < 0.25) {
    cat("WARNING: < 25%% of rows have prior events. Kill criterion triggered.\n")
  }
}

# Check: CR methods miscalibrated for H1+
cr_methods <- c("Fine-Gray", "CS-Cox-noHist")
cr_post_rec <- summary_df %>%
  filter(estimator %in% cr_methods, history_stratum %in% c("H1", "H2", "H3"))

dr_post_rec <- summary_df %>%
  filter(estimator == "Proposed-DR", history_stratum %in% c("H1", "H2", "H3"))

if (nrow(cr_post_rec) > 0 && nrow(dr_post_rec) > 0) {
  cr_avg_bias <- mean(abs(cr_post_rec$bias), na.rm = TRUE)
  dr_avg_bias <- mean(abs(dr_post_rec$bias), na.rm = TRUE)
  cat(sprintf("\nCR methods avg |bias| (H1-H3): %.4f\n", cr_avg_bias))
  cat(sprintf("DR avg |bias| (H1-H3):         %.4f\n", dr_avg_bias))

  if (cr_avg_bias > 2 * dr_avg_bias) {
    cat("\n*** BLOCK 4 GATE: PASS ***\n")
    cat("CR methods clearly miscalibrated after recurrence vs proposed DR.\n")
  } else {
    cat("\n*** BLOCK 4 GATE: FAIL ***\n")
    cat("CR methods not clearly worse. Check if history effects are strong enough.\n")
  }
}

# ---- Stratum detail for Figure 2 ----
cat("\n=== CALIBRATION BY STRATUM (for Figure 2) ===\n")
print(as.data.frame(summary_df %>%
  select(estimator, history_stratum, k, bias, coverage_95) %>%
  arrange(history_stratum, k, estimator)), digits = 4)
