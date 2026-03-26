# ============================================================================
# METADATA
# ============================================================================
# Script:       block2_dr_matrix.R
# Description:  Block 2 -- Double-robustness 2x2 matrix experiment.
#               Tests DR pseudo-observation estimator under correct/misspecified
#               nuisance model combinations, plus IPW-only and OR-only.
# Project:      Idea 7 - DR Pseudo-Obs
# Author:       Alison
# Last Updated: 2026-03-22
# ============================================================================
#
# Estimators (6 total):
#   both_correct : correct propensity (logistic) + correct outcome (multinomial)
#   prop_wrong   : intercept-only propensity + correct outcome
#   out_wrong    : correct propensity + intercept-only outcome
#   both_wrong   : intercept-only propensity + intercept-only outcome
#   ipw_only     : correct propensity + intercept-only outcome (IPW equivalent)
#   or_only      : trivial propensity (pi=1) + correct outcome (OR equivalent)
#
# Usage:
#   Rscript block2_dr_matrix.R [N_REPS] [ESTIMATOR] [RESULTS_DIR]
#   Rscript block2_dr_matrix.R 200 both_correct results/
#   Rscript block2_dr_matrix.R  # defaults: 200 reps, both_correct, results/
# ============================================================================

set.seed(20260322)

library(here)
library(survival)
library(nnet)

# ============================================================================
# SOURCE SHARED INFRASTRUCTURE
# ============================================================================

source(here::here("R", "source_missing_types.R"))
source(here::here("R", "dr_pseudo_obs.R"))

# ============================================================================
# COMMAND-LINE ARGUMENTS
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)

N_REPS <- if (length(args) >= 1) as.integer(args[1]) else 200L
ESTIMATOR <- if (length(args) >= 2) args[2] else "both_correct"
RESULTS_DIR <- if (length(args) >= 3) args[3] else here::here("results")

valid_estimators <- c("both_correct", "prop_wrong", "out_wrong",
                      "both_wrong", "ipw_only", "or_only")
if (!ESTIMATOR %in% valid_estimators) {
  stop("Invalid ESTIMATOR '", ESTIMATOR, "'. Must be one of: ",
       paste(valid_estimators, collapse = ", "))
}

if (!dir.exists(RESULTS_DIR)) dir.create(RESULTS_DIR, recursive = TRUE)

cat("=== Block 2: DR 2x2 Matrix ===\n")
cat("  N_REPS:      ", N_REPS, "\n")
cat("  ESTIMATOR:   ", ESTIMATOR, "\n")
cat("  RESULTS_DIR: ", RESULTS_DIR, "\n\n")

# ============================================================================
# DGM PARAMETERS
# ============================================================================

N_SUBJECTS   <- 500L
MISSING_PCT  <- 30        # MAR at 30%
CENSOR_MAX   <- 5
FRAILTY_VAR  <- 0.5       # f.alpha
R01          <- 0.5       # baseline rate type 1
R02          <- 0.3       # baseline rate type 2
RHO          <- 0.3       # correlation
BETA_VEC     <- c(0.5, -0.3, 0.3, -0.2, 0.1, -0.1, 0.2, -0.15)
COMPLEX_PAR  <- c(1, 1, 1, 1)   # nonlinear effects on

AA  <- 0.5    # landmark spacing
TAU <- 2.5    # pseudo-obs horizon = 5 * aa

# ============================================================================
# TRIVIAL PROPENSITY (for OR-only: pi = 1 for all subjects)
# ============================================================================

fit_propensity_trivial <- function(data, covariates = NULL) {
  is_event <- data$event == 1
  predict_fn <- function(newdata) rep(1, nrow(newdata))
  list(
    model   = NULL,
    scores  = rep(1, sum(is_event)),
    predict = predict_fn,
    method  = "trivial"
  )
}

# ============================================================================
# MAP ESTIMATOR LABEL TO NUISANCE MODEL SPECIFICATION
# ============================================================================

get_nuisance_spec <- function(estimator) {
  spec <- list(
    propensity_method  = NULL,
    outcome_method     = NULL,
    fit_propensity_fn  = NULL,
    fit_outcome_fn     = NULL
  )

  switch(estimator,
    both_correct = {
      spec$propensity_method <- "logistic"
      spec$outcome_method    <- "multinomial"
    },
    prop_wrong = {
      spec$fit_propensity_fn <- fit_propensity_wrong
      spec$outcome_method    <- "multinomial"
    },
    out_wrong = {
      spec$propensity_method <- "logistic"
      spec$fit_outcome_fn    <- fit_outcome_wrong
    },
    both_wrong = {
      spec$fit_propensity_fn <- fit_propensity_wrong
      spec$fit_outcome_fn    <- fit_outcome_wrong
    },
    ipw_only = {
      # Correct propensity, intercept-only outcome (marginal probs)
      spec$propensity_method <- "logistic"
      spec$fit_outcome_fn    <- fit_outcome_wrong
    },
    or_only = {
      # Trivial propensity (pi=1), correct outcome
      spec$fit_propensity_fn <- fit_propensity_trivial
      spec$outcome_method    <- "multinomial"
    }
  )

  return(spec)
}

# ============================================================================
# GROUND TRUTH: Monte Carlo theta_k with no missingness
# ============================================================================

cat("Computing ground truth theta_k (large MC, no missingness)...\n")

N_TRUTH_REPS <- 50L
N_TRUTH_SUBJ <- 5000L

truth_theta1 <- numeric(N_TRUTH_REPS)
truth_theta2 <- numeric(N_TRUTH_REPS)

for (tt in seq_len(N_TRUTH_REPS)) {
  tryCatch({
    truth_data <- rate_cox_data_gen_complex(
      n             = N_TRUTH_SUBJ,
      f.alpha       = FRAILTY_VAR,
      r01           = R01,
      r02           = R02,
      rho           = RHO,
      beta          = BETA_VEC,
      complex_params = COMPLEX_PAR,
      censor_max    = CENSOR_MAX
    )

    truth_lm <- transform_with_covariates_complex(truth_data, aa = AA)
    truth_lm <- generate_km_pseudoEst_weighted(truth_lm, tau = TAU, suffix = "dr")

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

cat("Ground truth theta:\n")
cat("  type1:", round(THETA_TRUE["type1"], 5), "\n")
cat("  type2:", round(THETA_TRUE["type2"], 5), "\n\n")

# ============================================================================
# SIMULATION LOOP
# ============================================================================

nuisance_spec <- get_nuisance_spec(ESTIMATOR)

results_list <- vector("list", N_REPS)

cat("Starting simulation: ", ESTIMATOR, " (", N_REPS, " reps)\n", sep = "")
t_start <- Sys.time()

for (rep in seq_len(N_REPS)) {

  rep_result <- tryCatch({

    # (a) Generate data
    data <- rate_cox_data_gen_complex(
      n              = N_SUBJECTS,
      f.alpha        = FRAILTY_VAR,
      r01            = R01,
      r02            = R02,
      rho            = RHO,
      beta           = BETA_VEC,
      complex_params = COMPLEX_PAR,
      censor_max     = CENSOR_MAX
    )

    # (b) Introduce MAR missingness at 30%
    data <- introduce_mar_missingness(data, MISSING_PCT)

    # (c) Run DR pseudo-observation pipeline
    dr_result <- run_dr_po_pipeline(
      data               = data,
      aa                 = AA,
      tau                = TAU,
      n_folds            = 5,
      propensity_method  = nuisance_spec$propensity_method,
      outcome_method     = nuisance_spec$outcome_method,
      fit_propensity_fn  = nuisance_spec$fit_propensity_fn,
      fit_outcome_fn     = nuisance_spec$fit_outcome_fn,
      seed               = 20260322 + rep
    )

    # (d) Record results
    data.frame(
      rep        = rep,
      estimator  = ESTIMATOR,
      theta1     = dr_result$theta["type1"],
      theta2     = dr_result$theta["type2"],
      se_naive1  = dr_result$se_naive["type1"],
      se_naive2  = dr_result$se_naive["type2"],
      se_ts1     = dr_result$se_twostage["type1"],
      se_ts2     = dr_result$se_twostage["type2"],
      n_subjects = dr_result$n_subjects,
      status     = "success",
      error_msg  = NA_character_,
      stringsAsFactors = FALSE
    )

  }, error = function(e) {
    data.frame(
      rep        = rep,
      estimator  = ESTIMATOR,
      theta1     = NA_real_,
      theta2     = NA_real_,
      se_naive1  = NA_real_,
      se_naive2  = NA_real_,
      se_ts1     = NA_real_,
      se_ts2     = NA_real_,
      n_subjects = NA_integer_,
      status     = "error",
      error_msg  = conditionMessage(e),
      stringsAsFactors = FALSE
    )
  })

  results_list[[rep]] <- rep_result

  # Progress report every 10 reps
 if (rep %% 10 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
    n_ok <- sum(sapply(results_list[1:rep], function(r) r$status == "success"))
    cat(sprintf("  Rep %d/%d  |  success: %d  |  elapsed: %.1f min\n",
                rep, N_REPS, n_ok, elapsed))
  }
}

t_end <- Sys.time()
cat("\nSimulation complete. Total time:",
    round(as.numeric(difftime(t_end, t_start, units = "mins")), 1), "min\n\n")

# ============================================================================
# ASSEMBLE RESULTS
# ============================================================================

results_df <- do.call(rbind, results_list)
rownames(results_df) <- NULL

n_success <- sum(results_df$status == "success")
n_error   <- sum(results_df$status == "error")
cat("Successful reps:", n_success, "/", N_REPS, "\n")
if (n_error > 0) {
  cat("Errors:", n_error, "\n")
  err_msgs <- unique(results_df$error_msg[results_df$status == "error"])
  cat("  Unique errors:", paste(err_msgs, collapse = "; "), "\n")
}

# ============================================================================
# COMPUTE SUMMARY STATISTICS
# ============================================================================

ok <- results_df$status == "success"

compute_metrics <- function(theta_hat, se_naive, se_ts, theta_true) {
  n <- sum(!is.na(theta_hat))
  if (n < 2) {
    return(data.frame(
      n = n, bias = NA, abs_bias = NA, rmse = NA, emp_se = NA,
      mean_se_naive = NA, mean_se_ts = NA,
      se_ratio_naive = NA, se_ratio_ts = NA,
      coverage_naive = NA, coverage_ts = NA
    ))
  }

  bias     <- mean(theta_hat - theta_true, na.rm = TRUE)
  abs_bias <- abs(bias)
  emp_se   <- sd(theta_hat, na.rm = TRUE)
  rmse     <- sqrt(mean((theta_hat - theta_true)^2, na.rm = TRUE))

  mean_se_naive <- mean(se_naive, na.rm = TRUE)
  mean_se_ts    <- mean(se_ts, na.rm = TRUE)

  # SE ratio: mean estimated SE / empirical SE (should be near 1)
  se_ratio_naive <- mean_se_naive / emp_se
  se_ratio_ts    <- mean_se_ts / emp_se

  # Coverage: does 95% CI contain theta_true?
  ci_lo_naive <- theta_hat - 1.96 * se_naive
  ci_hi_naive <- theta_hat + 1.96 * se_naive
  coverage_naive <- mean(ci_lo_naive <= theta_true & theta_true <= ci_hi_naive,
                         na.rm = TRUE)

  ci_lo_ts <- theta_hat - 1.96 * se_ts
  ci_hi_ts <- theta_hat + 1.96 * se_ts
  coverage_ts <- mean(ci_lo_ts <= theta_true & theta_true <= ci_hi_ts,
                      na.rm = TRUE)

  data.frame(
    n              = n,
    bias           = bias,
    abs_bias       = abs_bias,
    rmse           = rmse,
    emp_se         = emp_se,
    mean_se_naive  = mean_se_naive,
    mean_se_ts     = mean_se_ts,
    se_ratio_naive = se_ratio_naive,
    se_ratio_ts    = se_ratio_ts,
    coverage_naive = coverage_naive,
    coverage_ts    = coverage_ts
  )
}

metrics_type1 <- compute_metrics(
  theta_hat  = results_df$theta1[ok],
  se_naive   = results_df$se_naive1[ok],
  se_ts      = results_df$se_ts1[ok],
  theta_true = THETA_TRUE["type1"]
)
metrics_type1$type <- 1

metrics_type2 <- compute_metrics(
  theta_hat  = results_df$theta2[ok],
  se_naive   = results_df$se_naive2[ok],
  se_ts      = results_df$se_ts2[ok],
  theta_true = THETA_TRUE["type2"]
)
metrics_type2$type <- 2

summary_df <- rbind(metrics_type1, metrics_type2)
summary_df$estimator  <- ESTIMATOR
summary_df$n_subjects <- N_SUBJECTS
summary_df$missing_pct <- MISSING_PCT
summary_df$theta_true <- c(THETA_TRUE["type1"], THETA_TRUE["type2"])

# Reorder columns
summary_df <- summary_df[, c("estimator", "type", "n_subjects", "missing_pct",
                              "theta_true", "n", "bias", "abs_bias", "rmse",
                              "emp_se", "mean_se_naive", "mean_se_ts",
                              "se_ratio_naive", "se_ratio_ts",
                              "coverage_naive", "coverage_ts")]

# ============================================================================
# PRINT SUMMARY
# ============================================================================

cat("\n=== SUMMARY: ", ESTIMATOR, " ===\n")
cat("Ground truth: type1 =", round(THETA_TRUE["type1"], 4),
    ", type2 =", round(THETA_TRUE["type2"], 4), "\n\n")

for (k in 1:2) {
  m <- summary_df[summary_df$type == k, ]
  cat(sprintf("  Type %d:\n", k))
  cat(sprintf("    Bias:           %+.5f\n",  m$bias))
  cat(sprintf("    RMSE:            %.5f\n",   m$rmse))
  cat(sprintf("    Emp SE:          %.5f\n",   m$emp_se))
  cat(sprintf("    Mean SE (naive): %.5f  (ratio: %.3f)\n",
              m$mean_se_naive, m$se_ratio_naive))
  cat(sprintf("    Mean SE (2stg):  %.5f  (ratio: %.3f)\n",
              m$mean_se_ts, m$se_ratio_ts))
  cat(sprintf("    Coverage naive:  %.1f%%\n", 100 * m$coverage_naive))
  cat(sprintf("    Coverage 2stg:   %.1f%%\n", 100 * m$coverage_ts))
  cat("\n")
}

# ============================================================================
# SAVE RESULTS
# ============================================================================

results_path <- file.path(RESULTS_DIR, paste0("block2_", ESTIMATOR, "_results.csv"))
summary_path <- file.path(RESULTS_DIR, paste0("block2_", ESTIMATOR, "_summary.csv"))

write.csv(results_df, results_path, row.names = FALSE)
write.csv(summary_df, summary_path, row.names = FALSE)

cat("Results saved to:\n")
cat("  ", results_path, "\n")
cat("  ", summary_path, "\n")
cat("\nDone.\n")
