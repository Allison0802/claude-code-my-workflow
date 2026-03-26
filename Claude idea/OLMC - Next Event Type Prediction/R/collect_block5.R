# =============================================================================
# collect_block5.R
# Collect and summarize Block 5 (Rare-Event Stability) results
# Last Updated: 2026-03-21
# =============================================================================

suppressPackageStartupMessages(library(tidyverse))
library(here)

script_dir <- tryCatch(
  dirname(here::here("R/collect_block5.R")),
  error = function(e) "."
)

results_dir <- file.path(script_dir, "results", "block5")
csv_files   <- list.files(results_dir, pattern = "block5_.*\\.csv$", full.names = TRUE)

if (length(csv_files) == 0) {
  stop("No Block 5 result CSV files found in: ", results_dir)
}

cat(sprintf("Found %d result files:\n", length(csv_files)))
all_results <- bind_rows(lapply(csv_files, read.csv))
cat(sprintf("Total rows: %d\n\n", nrow(all_results)))

# ---- Summary by (w, estimator, stratum, k) ----
summary_df <- all_results %>%
  group_by(w, estimator, history_stratum, k) %>%
  summarise(
    n_reps        = n(),
    pi_true       = mean(pi_true, na.rm = TRUE),
    pi_hat_mean   = mean(pi_hat, na.rm = TRUE),
    pi_bias       = mean(pi_bias, na.rm = TRUE),
    pi_rmse       = sqrt(mean(pi_sq_err, na.rm = TRUE)),
    pi_coverage   = mean(pi_cover_95, na.rm = TRUE),
    q_true        = mean(q_true, na.rm = TRUE),
    q_hat_mean    = mean(q_hat, na.rm = TRUE),
    .groups       = "drop"
  ) %>%
  arrange(w, estimator, history_stratum, k)

summary_file <- file.path(results_dir, "block5_summary.csv")
write.csv(summary_df, summary_file, row.names = FALSE)
cat(sprintf("Summary saved to %s\n\n", summary_file))

# ---- Stability curve: coverage vs q(h) ----
cat("=== STABILITY CURVE: pi_k COVERAGE vs q(h) ===\n\n")
stability <- summary_df %>%
  group_by(w, estimator) %>%
  summarise(
    avg_q_true     = mean(q_true, na.rm = TRUE),
    avg_pi_rmse    = mean(pi_rmse, na.rm = TRUE),
    avg_pi_coverage = mean(pi_coverage, na.rm = TRUE),
    min_pi_coverage = min(pi_coverage, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(w, estimator)
print(as.data.frame(stability), digits = 4)

# ---- Kill criterion ----
cat("\n=== KILL CRITERION CHECK ===\n")
cat("Coverage must be >= 0.90 for q(h) >= 0.15\n\n")

high_q <- stability %>%
  filter(avg_q_true >= 0.15)

if (nrow(high_q) > 0) {
  dr_normalize <- high_q %>% filter(grepl("DR-normalize", estimator))
  if (nrow(dr_normalize) > 0) {
    min_cov <- min(dr_normalize$min_pi_coverage, na.rm = TRUE)
    cat(sprintf("DR-normalize min coverage at q(h) >= 0.15: %.3f\n", min_cov))
    if (min_cov >= 0.90) {
      cat("\n*** BLOCK 5 GATE: PASS ***\n")
      cat("pi_k(h) stable at q(h) >= 0.15. Check 0.10 threshold too.\n")
    } else {
      cat("\n*** BLOCK 5 GATE: FAIL ***\n")
      cat("Instability persists at q(h) >= 0.15.\n")
    }
  }
}

# ---- Threshold recommendation ----
cat("\n=== REPORTING THRESHOLD RECOMMENDATION ===\n")
threshold_check <- stability %>%
  filter(grepl("DR-normalize", estimator)) %>%
  mutate(stable = avg_pi_coverage >= 0.90)
print(as.data.frame(threshold_check %>%
  select(w, avg_q_true, avg_pi_coverage, stable)), digits = 4)
