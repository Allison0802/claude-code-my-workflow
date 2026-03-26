# ============================================================================
# METADATA
# ============================================================================
# Script:       block4_crossfit.R
# Description:  Block 4 -- Cross-fitting benefit experiment. Compares
#               cross-fitted vs non-cross-fitted DR pseudo-observation
#               estimators under a nonlinear DGM (complex_params = c(1,1,1,1))
#               where cross-fitting matters most. Shows that cross-fitting
#               removes overfitting bias and improves coverage.
# Project:      Idea 7 - DR Pseudo-Obs
# Author:       Alison
# Last Updated: 2026-03-22
# ============================================================================
#
# Estimators (4):
#   DR-PO-CF-RF    : Cross-fitted DR with RF propensity + RF outcome (5-fold)
#   DR-PO-CF-param : Cross-fitted DR with logistic + multinomial (5-fold)
#   DR-param-noCF  : Non-cross-fitted parametric DR (n_folds=1)
#   IPW-RF-noCF    : RF propensity IPW, no cross-fitting (Missing Types method)
#
# DGM: K=2, n=500, MAR 30%, censoring 25%, full nonlinear interactions
#
# Usage:
#   Rscript block4_crossfit.R [N_REPS] [RESULTS_DIR]
#   Rscript block4_crossfit.R 500 results/
#   Rscript block4_crossfit.R  # defaults: 500 reps, results/
# ============================================================================

set.seed(20260322)

# ============================================================================
# PACKAGES
# ============================================================================
suppressPackageStartupMessages({
  library(here)
  library(survival)
  library(nnet)
  library(ranger)
})

# ============================================================================
# SOURCE SHARED INFRASTRUCTURE
# ============================================================================
source(here::here("R", "source_missing_types.R"))
source(here::here("R", "dr_pseudo_obs.R"))

# ============================================================================
# COMMAND-LINE ARGUMENTS
# ============================================================================
args <- commandArgs(trailingOnly = TRUE)

N_REPS      <- if (length(args) >= 1) as.integer(args[1]) else 500L
RESULTS_DIR <- if (length(args) >= 2) args[2] else here::here("results")

# Make RESULTS_DIR absolute
if (!startsWith(RESULTS_DIR, "/")) {
  RESULTS_DIR <- here::here(RESULTS_DIR)
}
if (!dir.exists(RESULTS_DIR)) {
  dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
}

cat("============================================================\n")
cat("BLOCK 4: CROSS-FITTING BENEFIT\n")
cat("============================================================\n")
cat("N_REPS:     ", N_REPS, "\n")
cat("RESULTS_DIR:", RESULTS_DIR, "\n")
cat("============================================================\n\n")

# ============================================================================
# DGM PARAMETERS
# ============================================================================
N_SUBJECTS   <- 500L
MISSING_PCT  <- 30         # MAR at 30%
CENSOR_MAX   <- 5
FRAILTY_VAR  <- 0.5        # f.alpha
R01          <- 0.5        # baseline rate type 1
R02          <- 0.3        # baseline rate type 2
RHO          <- 0.3        # correlation
BETA_VEC     <- c(0.5, -0.3, 0.3, -0.2, 0.1, -0.1, 0.2, -0.15)
COMPLEX_PAR  <- c(1, 1, 1, 1)  # full nonlinear interactions

AA  <- 0.5    # landmark spacing
TAU <- 2.5    # pseudo-obs horizon = 5 * aa

# ============================================================================
# GROUND TRUTH: Monte Carlo theta_k with no missingness
# ============================================================================
cat("Computing ground truth theta_k (50 reps x n=5000, no missingness)...\n")

N_TRUTH_REPS <- 50L
N_TRUTH_SUBJ <- 5000L

truth_theta1 <- numeric(N_TRUTH_REPS)
truth_theta2 <- numeric(N_TRUTH_REPS)

set.seed(20260322 + 9999)
for (tt in seq_len(N_TRUTH_REPS)) {
  tryCatch({
    truth_data <- rate_cox_data_gen_complex(
      n              = N_TRUTH_SUBJ,
      f.alpha        = FRAILTY_VAR,
      r01            = R01,
      r02            = R02,
      rho            = RHO,
      beta           = BETA_VEC,
      complex_params = COMPLEX_PAR,
      censor_max     = CENSOR_MAX
    )

    truth_lm <- transform_with_covariates_complex(truth_data, aa = AA)
    truth_lm <- generate_km_pseudoEst(truth_lm, tau = TAU)

    truth_theta1[tt] <- mean(truth_lm$pseudoEst_km_type1, na.rm = TRUE)
    truth_theta2[tt] <- mean(truth_lm$pseudoEst_km_type2, na.rm = TRUE)
  }, error = function(e) {
    cat("  Ground truth rep", tt, "failed:", conditionMessage(e), "\n")
    truth_theta1[tt] <<- NA
    truth_theta2[tt] <<- NA
  })
}

THETA_TRUE <- c(
  type1 = mean(truth_theta1, na.rm = TRUE),
  type2 = mean(truth_theta2, na.rm = TRUE)
)

cat(sprintf("Ground truth theta: type1 = %.6f, type2 = %.6f\n\n",
            THETA_TRUE["type1"], THETA_TRUE["type2"]))

rm(truth_data, truth_lm)
gc(verbose = FALSE)

# ============================================================================
# HELPER: Coverage indicator
# ============================================================================
compute_coverage <- function(theta_hat, se, theta_true, alpha = 0.05) {
  z <- qnorm(1 - alpha / 2)
  lo <- theta_hat - z * se
  hi <- theta_hat + z * se
  as.integer(theta_true >= lo & theta_true <= hi)
}

# ============================================================================
# SIMULATION LOOP
# ============================================================================
ESTIMATOR_NAMES <- c("DR-PO-CF-RF", "DR-PO-CF-param", "DR-param-noCF", "IPW-RF-noCF")

results_list <- vector("list", N_REPS)

cat("Starting simulation (", N_REPS, " reps, ", MISSING_PCT, "% MAR, nonlinear DGM)...\n", sep = "")
t_start <- Sys.time()

for (rep in seq_len(N_REPS)) {

  set.seed(20260322 + rep)

  rep_results <- tryCatch({

    # --- (a) Generate data with nonlinear effects ---
    raw_data <- rate_cox_data_gen_complex(
      n              = N_SUBJECTS,
      f.alpha        = FRAILTY_VAR,
      r01            = R01,
      r02            = R02,
      rho            = RHO,
      beta           = BETA_VEC,
      complex_params = COMPLEX_PAR,
      censor_max     = CENSOR_MAX
    )

    raw_data$type_true <- raw_data$type

    # --- (b) Introduce MAR missingness ---
    data_miss <- introduce_mar_missingness(raw_data, MISSING_PCT)

    # ==================================================================
    # ESTIMATOR 1: DR-PO-CF-RF (cross-fitted, RF nuisance models)
    # ==================================================================
    dr_cf_rf <- tryCatch({
      res <- run_dr_po_pipeline(
        data              = data_miss,
        aa                = AA,
        tau               = TAU,
        n_folds           = 5,
        propensity_method = "rf",
        outcome_method    = "rf",
        seed              = 20260322 + rep
      )
      data.frame(
        rep       = rep,
        estimator = "DR-PO-CF-RF",
        theta1    = res$theta["type1"],
        theta2    = res$theta["type2"],
        se1       = res$se_twostage["type1"],
        se2       = res$se_twostage["type2"],
        cov1      = compute_coverage(res$theta["type1"], res$se_twostage["type1"],
                                     THETA_TRUE["type1"]),
        cov2      = compute_coverage(res$theta["type2"], res$se_twostage["type2"],
                                     THETA_TRUE["type2"]),
        status    = "success",
        error_msg = NA_character_,
        stringsAsFactors = FALSE, row.names = NULL
      )
    }, error = function(e) {
      data.frame(rep = rep, estimator = "DR-PO-CF-RF",
                 theta1 = NA_real_, theta2 = NA_real_,
                 se1 = NA_real_, se2 = NA_real_,
                 cov1 = NA_integer_, cov2 = NA_integer_,
                 status = "error", error_msg = conditionMessage(e),
                 stringsAsFactors = FALSE, row.names = NULL)
    })

    # ==================================================================
    # ESTIMATOR 2: DR-PO-CF-param (cross-fitted, parametric nuisance)
    # ==================================================================
    dr_cf_param <- tryCatch({
      res <- run_dr_po_pipeline(
        data              = data_miss,
        aa                = AA,
        tau               = TAU,
        n_folds           = 5,
        propensity_method = "logistic",
        outcome_method    = "multinomial",
        seed              = 20260322 + rep
      )
      data.frame(
        rep       = rep,
        estimator = "DR-PO-CF-param",
        theta1    = res$theta["type1"],
        theta2    = res$theta["type2"],
        se1       = res$se_twostage["type1"],
        se2       = res$se_twostage["type2"],
        cov1      = compute_coverage(res$theta["type1"], res$se_twostage["type1"],
                                     THETA_TRUE["type1"]),
        cov2      = compute_coverage(res$theta["type2"], res$se_twostage["type2"],
                                     THETA_TRUE["type2"]),
        status    = "success",
        error_msg = NA_character_,
        stringsAsFactors = FALSE, row.names = NULL
      )
    }, error = function(e) {
      data.frame(rep = rep, estimator = "DR-PO-CF-param",
                 theta1 = NA_real_, theta2 = NA_real_,
                 se1 = NA_real_, se2 = NA_real_,
                 cov1 = NA_integer_, cov2 = NA_integer_,
                 status = "error", error_msg = conditionMessage(e),
                 stringsAsFactors = FALSE, row.names = NULL)
    })

    # ==================================================================
    # ESTIMATOR 3: DR-param-noCF (non-cross-fitted parametric, n_folds=1)
    # ==================================================================
    dr_nocf <- tryCatch({
      res <- run_dr_po_pipeline(
        data              = data_miss,
        aa                = AA,
        tau               = TAU,
        n_folds           = 1,
        propensity_method = "logistic",
        outcome_method    = "multinomial",
        seed              = 20260322 + rep
      )
      data.frame(
        rep       = rep,
        estimator = "DR-param-noCF",
        theta1    = res$theta["type1"],
        theta2    = res$theta["type2"],
        se1       = res$se_twostage["type1"],
        se2       = res$se_twostage["type2"],
        cov1      = compute_coverage(res$theta["type1"], res$se_twostage["type1"],
                                     THETA_TRUE["type1"]),
        cov2      = compute_coverage(res$theta["type2"], res$se_twostage["type2"],
                                     THETA_TRUE["type2"]),
        status    = "success",
        error_msg = NA_character_,
        stringsAsFactors = FALSE, row.names = NULL
      )
    }, error = function(e) {
      data.frame(rep = rep, estimator = "DR-param-noCF",
                 theta1 = NA_real_, theta2 = NA_real_,
                 se1 = NA_real_, se2 = NA_real_,
                 cov1 = NA_integer_, cov2 = NA_integer_,
                 status = "error", error_msg = conditionMessage(e),
                 stringsAsFactors = FALSE, row.names = NULL)
    })

    # ==================================================================
    # ESTIMATOR 4: IPW-RF-noCF (RF propensity IPW, no cross-fitting)
    # ==================================================================
    ipw_rf <- tryCatch({
      # Fit RF propensity on full raw data (no cross-fitting)
      prop_rf <- fit_propensity_model_rf(data_miss)

      # Transform to landmark format
      lm_data <- transform_with_covariates_complex(data_miss, aa = AA)

      # Assign IPW weights
      lm_data$ipw_weight <- 1.0
      event_idx <- which(lm_data$event == 1)

      if (length(event_idx) > 0) {
        pred_df <- lm_data[event_idx, , drop = FALSE]
        pred_probs <- predict(prop_rf$model, data = pred_df)$predictions
        if (is.matrix(pred_probs) && "1" %in% colnames(pred_probs)) {
          prob_obs <- pred_probs[, "1"]
        } else if (is.matrix(pred_probs)) {
          prob_obs <- pred_probs[, ncol(pred_probs)]
        } else {
          prob_obs <- pred_probs
        }
        prob_obs <- pmax(prob_obs, 0.01)
        lm_data$ipw_weight[event_idx] <- 1.0 / prob_obs

        # Truncate extreme weights
        med_w <- median(lm_data$ipw_weight[event_idx], na.rm = TRUE)
        lm_data$ipw_weight[event_idx] <- pmin(
          lm_data$ipw_weight[event_idx], 10 * med_w
        )
      }

      # Generate pseudo-observations (auto-uses ipw_weight)
      lm_data <- generate_km_pseudoEst(lm_data, tau = TAU)

      # Subject-level aggregation
      subj_po1 <- tapply(lm_data$pseudoEst_km_type1, lm_data$pid, mean, na.rm = TRUE)
      subj_po2 <- tapply(lm_data$pseudoEst_km_type2, lm_data$pid, mean, na.rm = TRUE)
      n_subj <- length(subj_po1)

      theta1_ipw <- mean(subj_po1, na.rm = TRUE)
      theta2_ipw <- mean(subj_po2, na.rm = TRUE)
      se1_ipw <- sqrt(var(subj_po1, na.rm = TRUE) / n_subj)
      se2_ipw <- sqrt(var(subj_po2, na.rm = TRUE) / n_subj)

      data.frame(
        rep       = rep,
        estimator = "IPW-RF-noCF",
        theta1    = theta1_ipw,
        theta2    = theta2_ipw,
        se1       = se1_ipw,
        se2       = se2_ipw,
        cov1      = compute_coverage(theta1_ipw, se1_ipw, THETA_TRUE["type1"]),
        cov2      = compute_coverage(theta2_ipw, se2_ipw, THETA_TRUE["type2"]),
        status    = "success",
        error_msg = NA_character_,
        stringsAsFactors = FALSE, row.names = NULL
      )
    }, error = function(e) {
      data.frame(rep = rep, estimator = "IPW-RF-noCF",
                 theta1 = NA_real_, theta2 = NA_real_,
                 se1 = NA_real_, se2 = NA_real_,
                 cov1 = NA_integer_, cov2 = NA_integer_,
                 status = "error", error_msg = conditionMessage(e),
                 stringsAsFactors = FALSE, row.names = NULL)
    })

    # Combine all estimators for this replicate
    rbind(dr_cf_rf, dr_cf_param, dr_nocf, ipw_rf)

  }, error = function(e) {
    cat(sprintf("  [REP %d] DATA GENERATION FAILED: %s\n", rep, conditionMessage(e)))
    data.frame(
      rep       = rep,
      estimator = "ALL",
      theta1    = NA_real_, theta2 = NA_real_,
      se1       = NA_real_, se2 = NA_real_,
      cov1      = NA_integer_, cov2 = NA_integer_,
      status    = "error",
      error_msg = conditionMessage(e),
      stringsAsFactors = FALSE, row.names = NULL
    )
  })

  results_list[[rep]] <- rep_results

  # Progress report every 10 reps
  if (rep %% 10 == 0 || rep == 1) {
    elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
    rate    <- rep / elapsed
    eta     <- (N_REPS - rep) / rate
    n_ok    <- sum(sapply(results_list[1:rep], function(r)
      sum(r$status == "success")))
    cat(sprintf("[REP %d/%d] elapsed %.1f min | rate %.1f reps/min | ETA %.1f min | %d estimator-successes\n",
                rep, N_REPS, elapsed, rate, eta, n_ok))
  }
}

t_end <- Sys.time()
cat(sprintf("\nSimulation complete. Total time: %.1f min\n\n",
            as.numeric(difftime(t_end, t_start, units = "mins"))))

# ============================================================================
# ASSEMBLE RESULTS
# ============================================================================
results_df <- do.call(rbind, results_list)
rownames(results_df) <- NULL

for (est in ESTIMATOR_NAMES) {
  sub <- results_df[results_df$estimator == est, ]
  n_ok <- sum(sub$status == "success", na.rm = TRUE)
  cat(sprintf("  %-18s: %d/%d successful\n", est, n_ok, N_REPS))
}

# ============================================================================
# COMPUTE SUMMARY STATISTICS
# ============================================================================
compute_block4_metrics <- function(df, theta_true) {
  n <- sum(!is.na(df$theta1))
  if (n < 2) {
    return(data.frame(n = n, bias1 = NA, bias2 = NA, rmse1 = NA, rmse2 = NA,
                      emp_se1 = NA, emp_se2 = NA, mean_se1 = NA, mean_se2 = NA,
                      se_ratio1 = NA, se_ratio2 = NA,
                      coverage1 = NA, coverage2 = NA))
  }

  bias1    <- mean(df$theta1 - theta_true["type1"], na.rm = TRUE)
  bias2    <- mean(df$theta2 - theta_true["type2"], na.rm = TRUE)
  rmse1    <- sqrt(mean((df$theta1 - theta_true["type1"])^2, na.rm = TRUE))
  rmse2    <- sqrt(mean((df$theta2 - theta_true["type2"])^2, na.rm = TRUE))
  emp_se1  <- sd(df$theta1, na.rm = TRUE)
  emp_se2  <- sd(df$theta2, na.rm = TRUE)
  mean_se1 <- mean(df$se1, na.rm = TRUE)
  mean_se2 <- mean(df$se2, na.rm = TRUE)

  data.frame(
    n          = n,
    bias1      = bias1,
    bias2      = bias2,
    rmse1      = rmse1,
    rmse2      = rmse2,
    emp_se1    = emp_se1,
    emp_se2    = emp_se2,
    mean_se1   = mean_se1,
    mean_se2   = mean_se2,
    se_ratio1  = mean_se1 / emp_se1,
    se_ratio2  = mean_se2 / emp_se2,
    coverage1  = mean(df$cov1, na.rm = TRUE),
    coverage2  = mean(df$cov2, na.rm = TRUE)
  )
}

summary_list <- list()
for (est in ESTIMATOR_NAMES) {
  sub <- results_df[results_df$estimator == est & results_df$status == "success", ]
  m <- compute_block4_metrics(sub, THETA_TRUE)
  m$estimator   <- est
  m$miss_pct    <- MISSING_PCT
  m$theta_true1 <- THETA_TRUE["type1"]
  m$theta_true2 <- THETA_TRUE["type2"]
  summary_list[[est]] <- m
}

summary_df <- do.call(rbind, summary_list)
rownames(summary_df) <- NULL

summary_df <- summary_df[, c("estimator", "miss_pct", "n",
                              "theta_true1", "theta_true2",
                              "bias1", "bias2", "rmse1", "rmse2",
                              "emp_se1", "emp_se2", "mean_se1", "mean_se2",
                              "se_ratio1", "se_ratio2",
                              "coverage1", "coverage2")]

# ============================================================================
# PRINT SUMMARY
# ============================================================================
cat("\n============================================================\n")
cat(sprintf("BLOCK 4 SUMMARY: %d%% MAR, n = %d, nonlinear DGM\n",
            MISSING_PCT, N_SUBJECTS))
cat(sprintf("Ground truth: type1 = %.6f, type2 = %.6f\n",
            THETA_TRUE["type1"], THETA_TRUE["type2"]))
cat("============================================================\n\n")

for (i in seq_len(nrow(summary_df))) {
  s <- summary_df[i, ]
  cat(sprintf("%-18s (n=%d)\n", s$estimator, s$n))
  cat(sprintf("  Type 1: bias=%+.5f  RMSE=%.5f  SE ratio=%.3f  coverage=%.3f\n",
              s$bias1, s$rmse1, s$se_ratio1, s$coverage1))
  cat(sprintf("  Type 2: bias=%+.5f  RMSE=%.5f  SE ratio=%.3f  coverage=%.3f\n",
              s$bias2, s$rmse2, s$se_ratio2, s$coverage2))
  cat("\n")
}

# ============================================================================
# SAVE RESULTS
# ============================================================================
results_path <- file.path(RESULTS_DIR, "block4_results.csv")
summary_path <- file.path(RESULTS_DIR, "block4_summary.csv")

write.csv(results_df, results_path, row.names = FALSE)
write.csv(summary_df, summary_path, row.names = FALSE)

cat("Results saved to:\n")
cat("  ", results_path, "\n")
cat("  ", summary_path, "\n")
cat("\n============================================================\n")
cat("Block 4 complete.\n")
cat(sprintf("Elapsed time: %.1f minutes\n",
            as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
cat("============================================================\n")
