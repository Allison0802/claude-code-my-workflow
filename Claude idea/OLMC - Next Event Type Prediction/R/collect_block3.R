# =============================================================================
# collect_block3.R
# Collect and summarize Block 3 (Naive Bias Demonstration) results
# Last Updated: 2026-03-21
# =============================================================================

suppressPackageStartupMessages(library(tidyverse))
library(here)

script_dir <- tryCatch(
  dirname(here::here("R/collect_block3.R")),
  error = function(e) "."
)

results_dir <- file.path(script_dir, "results", "block3")
csv_files   <- list.files(results_dir, pattern = "block3_.*\\.csv$", full.names = TRUE)

if (length(csv_files) == 0) {
  stop("No Block 3 result CSV files found in: ", results_dir)
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

summary_file <- file.path(results_dir, "block3_summary.csv")
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("Summary saved to %s\n\n", summary_file))

# ---- Bias comparison: DR vs naive methods ----
cat("=== BIAS COMPARISON BY ESTIMATOR AND STRATUM ===\n")
bias_table <- summary_df %>%
  group_by(estimator) %>%
  summarise(
    avg_abs_bias    = mean(abs(bias), na.rm = TRUE),
    max_abs_bias    = max(abs(bias), na.rm = TRUE),
    avg_coverage    = mean(coverage_95, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(avg_abs_bias)
print(as.data.frame(bias_table), digits = 4)

# ---- Kill criterion ----
cat("\n=== KILL CRITERION CHECK ===\n")
cat("Naive methods must show >= 10% absolute bias in at least one stratum.\n\n")

naive_methods <- c("observed-case", "death-as-censoring", "OR-only", "IPCW-only")
naive_max_bias <- summary_df %>%
  filter(estimator %in% naive_methods) %>%
  group_by(estimator) %>%
  summarise(max_abs_bias = max(abs(bias), na.rm = TRUE), .groups = "drop")

print(as.data.frame(naive_max_bias), digits = 4)

any_large_bias <- any(naive_max_bias$max_abs_bias >= 0.10, na.rm = TRUE)
if (any_large_bias) {
  cat("\n*** BLOCK 3 GATE: PASS ***\n")
  cat("At least one naive method shows >= 10% bias. DR advantage demonstrated.\n")
} else {
  cat("\n*** BLOCK 3 GATE: FAIL ***\n")
  cat("No naive method shows >= 10% bias. Practical motivation may be weak.\n")
}

# ---- Stratum-level detail ----
cat("\n=== DETAILED BIAS BY STRATUM (for Figure 1 / Table 2) ===\n")
detail_df <- summary_df %>%
  select(estimator, history_stratum, k, bias, coverage_95) %>%
  pivot_wider(
    names_from = estimator,
    values_from = c(bias, coverage_95),
    names_sep = "_"
  )
print(as.data.frame(detail_df), digits = 4)
