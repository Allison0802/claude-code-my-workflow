# =============================================================================
# collect_block1.R
# Collect and summarize Block 1 simulation results
# Checks kill criterion, produces summary table for supplement
# Last Updated: 2026-03-20
# =============================================================================

suppressPackageStartupMessages(library(tidyverse))
library(here)

script_dir <- tryCatch(
  dirname(here::here("R/collect_block1.R")),
  error = function(e) "."
)

results_dir <- file.path(script_dir, "results", "block1")
csv_files   <- list.files(results_dir, pattern = "block1_n.*\\.csv$", full.names = TRUE)

if (length(csv_files) == 0) {
  stop("No Block 1 result CSV files found in: ", results_dir)
}

cat(sprintf("Found %d result files:\n", length(csv_files)))
cat(paste(" ", basename(csv_files), collapse = "\n"), "\n\n")

all_results <- bind_rows(lapply(csv_files, read.csv))
cat(sprintf("Total rows: %d\n\n", nrow(all_results)))

# ---- Summary table ----
summary_df <- all_results %>%
  group_by(n, estimator, history_stratum, k) %>%
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
    eif_var_ratio = mean(se^2, na.rm = TRUE) / pmax(var(mu_hat, na.rm = TRUE), 1e-10),
    .groups      = "drop"
  ) %>%
  arrange(n, estimator, history_stratum, k)

# Save summary
summary_file <- file.path(results_dir, "block1_summary.csv")
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("Summary saved to %s\n\n", summary_file))

# ---- Kill criterion check ----
cat("=== KILL CRITERION CHECK (DR-oracle) ===\n")
oracle_check <- summary_df %>%
  filter(estimator == "DR-oracle") %>%
  arrange(n, history_stratum, k)

print(oracle_check %>%
        select(n, history_stratum, k, n_reps, mu_true, bias, coverage_95, eif_var_ratio),
      digits = 4)

pass <- oracle_check %>%
  filter(n_reps >= 50) %>%
  summarise(
    max_bias       = max(abs(bias), na.rm = TRUE),
    min_coverage   = min(coverage_95, na.rm = TRUE),
    max_eif_ratio  = max(eif_var_ratio, na.rm = TRUE),
    min_eif_ratio  = min(eif_var_ratio, na.rm = TRUE)
  )

cat(sprintf("\nMax |bias| (DR-oracle): %.4f  [kill threshold: 0.005]\n", pass$max_bias))
cat(sprintf("Min coverage (DR-oracle): %.3f  [threshold: 0.93 at n>=1000]\n", pass$min_coverage))
cat(sprintf("EIF variance ratio range: [%.3f, %.3f]  [target: near 1.0]\n",
            pass$min_eif_ratio, pass$max_eif_ratio))

if (pass$max_bias <= 0.005 && pass$min_coverage >= 0.93) {
  cat("\n*** BLOCK 1 GATE: PASS ***\n")
  cat("Proceed to Block 2 pilot.\n")
} else {
  cat("\n*** BLOCK 1 GATE: FAIL ***\n")
  cat("Investigate EIF derivation or implementation before proceeding.\n")
}

# ---- Comparison table: all estimators at n=1000 ----
cat("\n=== ESTIMATOR COMPARISON (n=1000) ===\n")
comp_1000 <- summary_df %>%
  filter(n == 1000) %>%
  select(estimator, history_stratum, k, n_reps, bias, coverage_95)
print(as.data.frame(comp_1000), digits = 4)
