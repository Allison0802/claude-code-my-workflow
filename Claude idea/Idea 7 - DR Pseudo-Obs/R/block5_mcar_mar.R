# ============================================================================
# METADATA
# ============================================================================
# Script:       block5_mcar_mar.R
# Description:  Block 5 -- MCAR vs MAR sensitivity experiment. Compares
#               DR-PO-CF, CCA, IPW-logistic, and IPW-RF under MCAR and MAR
#               missingness at varying rates. Under MCAR all methods should
#               perform similarly; under MAR, IPW and DR should outperform CCA.
# Project:      Idea 7 - DR Pseudo-Obs
# Author:       Alison
# Last Updated: 2026-03-22
# ============================================================================
#
# Estimators (4):
#   DR-PO-CF      : Cross-fitted DR (logistic + multinomial, 5-fold)
#   CCA           : Complete-case analysis
#   IPW-logistic  : Logistic propensity IPW (existing Missing Types method)
#   IPW-RF        : RF propensity IPW (existing Missing Types method)
#
# Usage:
#   Rscript block5_mcar_mar.R [N_REPS] [MISS_PATTERN] [MISS_PCT] [RESULTS_DIR]
#   Rscript block5_mcar_mar.R 500 MAR 30 results/
#   Rscript block5_mcar_mar.R  # defaults: 500 reps, MAR, 30%, results/
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

N_REPS       <- if (length(args) >= 1) as.integer(args[1]) else 500L
MISS_PATTERN <- if (length(args) >= 2) toupper(args[2]) else "MAR"
MISS_PCT     <- if (length(args) >= 3) as.integer(args[3]) else 30L
RESULTS_DIR  <- if (length(args) >= 4) args[4] else here::here("results")

# Validate inputs
stopifnot(MISS_PATTERN %in% c("MCAR", "MAR"))
stopifnot(MISS_PCT %in% c(20, 30, 50))

# Make RESULTS_DIR absolute
if (!startsWith(RESULTS_DIR, "/")) {
  RESULTS_DIR <- here::here(RESULTS_DIR)
}
if (!dir.exists(RESULTS_DIR)) {
  dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
}

cat("============================================================\n")
cat("BLOCK 5: MCAR vs MAR SENSITIVITY\n")
cat("============================================================\n")
cat("N_REPS:       ", N_REPS, "\n")
cat("MISS_PATTERN: ", MISS_PATTERN, "\n")
cat("MISS_PCT:     ", MISS_PCT, "%\n")
cat("RESULTS_DIR:  ", RESULTS_DIR, "\n")
cat("============================================================\n\n")

# ============================================================================
# DGM PARAMETERS
# ============================================================================
N_SUBJECTS   <- 500L
CENSOR_MAX   <- 5
FRAILTY_VAR  <- 0.5       # f.alpha
R01          <- 0.5       # baseline rate type 1
R02          <- 0.3       # baseline rate type 2
RHO          <- 0.3       # correlation
BETA_VEC     <- c(0.5, -0.3, 0.3, -0.2, 0.1, -0.1, 0.2, -0.15)

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
      n          = N_TRUTH_SUBJ,
      f.alpha    = FRAILTY_VAR,
      r01        = R01,
      r02        = R02,
      rho        = RHO,
      beta       = BETA_VEC,
      censor_max = CENSOR_MAX
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
# HELPER: Apply missingness based on pattern
# ============================================================================
apply_missingness <- function(data, pattern, pct) {
  if (pattern == "MCAR") {
    introduce_mcar_missingness(data, pct)
  } else {
    introduce_mar_missingness(data, pct)
  }
}

# ============================================================================
# HELPER: IPW with logistic propensity (uses existing Missing Types function)
# ============================================================================
run_ipw_logistic <- function(data_miss, aa, tau, theta_true) {
  # Fit logistic propensity on raw data
  prop_fit <- fit_propensity_model(data_miss)

  # Transform to landmark format
  lm_data <- transform_with_covariates_complex(data_miss, aa = aa)

  # Assign IPW weights: 1/pi(X) for event rows
  lm_data$ipw_weight <- 1.0
  event_idx <- which(lm_data$event == 1)

  if (length(event_idx) > 0) {
    pred_df <- lm_data[event_idx, , drop = FALSE]
    prob_obs <- predict(prop_fit$model, newdata = pred_df, type = "response")
    prob_obs <- pmax(prob_obs, 0.01)
    lm_data$ipw_weight[event_idx] <- 1.0 / prob_obs

    # Truncate extreme weights (10x median)
    med_w <- median(lm_data$ipw_weight[event_idx], na.rm = TRUE)
    lm_data$ipw_weight[event_idx] <- pmin(
      lm_data$ipw_weight[event_idx], 10 * med_w
    )
  }

  # Generate pseudo-observations (auto-uses ipw_weight column)
  lm_data <- generate_km_pseudoEst(lm_data, tau = tau)

  # Subject-level aggregation
  subj_po1 <- tapply(lm_data$pseudoEst_km_type1, lm_data$pid, mean, na.rm = TRUE)
  subj_po2 <- tapply(lm_data$pseudoEst_km_type2, lm_data$pid, mean, na.rm = TRUE)
  n_subj <- length(subj_po1)

  theta1 <- mean(subj_po1, na.rm = TRUE)
  theta2 <- mean(subj_po2, na.rm = TRUE)
  se1    <- sqrt(var(subj_po1, na.rm = TRUE) / n_subj)
  se2    <- sqrt(var(subj_po2, na.rm = TRUE) / n_subj)

  list(theta1 = theta1, theta2 = theta2, se1 = se1, se2 = se2)
}

# ============================================================================
# HELPER: IPW with RF propensity
# ============================================================================
run_ipw_rf <- function(data_miss, aa, tau, theta_true) {
  prop_rf <- fit_propensity_model_rf(data_miss)

  lm_data <- transform_with_covariates_complex(data_miss, aa = aa)

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

    med_w <- median(lm_data$ipw_weight[event_idx], na.rm = TRUE)
    lm_data$ipw_weight[event_idx] <- pmin(
      lm_data$ipw_weight[event_idx], 10 * med_w
    )
  }

  lm_data <- generate_km_pseudoEst(lm_data, tau = tau)

  subj_po1 <- tapply(lm_data$pseudoEst_km_type1, lm_data$pid, mean, na.rm = TRUE)
  subj_po2 <- tapply(lm_data$pseudoEst_km_type2, lm_data$pid, mean, na.rm = TRUE)
  n_subj <- length(subj_po1)

  theta1 <- mean(subj_po1, na.rm = TRUE)
  theta2 <- mean(subj_po2, na.rm = TRUE)
  se1    <- sqrt(var(subj_po1, na.rm = TRUE) / n_subj)
  se2    <- sqrt(var(subj_po2, na.rm = TRUE) / n_subj)

  list(theta1 = theta1, theta2 = theta2, se1 = se1, se2 = se2)
}

# ============================================================================
# SIMULATION LOOP
# ============================================================================
ESTIMATOR_NAMES <- c("DR-PO-CF", "CCA", "IPW-logistic", "IPW-RF")

results_list <- vector("list", N_REPS)

cat("Starting simulation (", N_REPS, " reps, ", MISS_PATTERN, " ",
    MISS_PCT, "%)...\n", sep = "")
t_start <- Sys.time()

for (rep in seq_len(N_REPS)) {

  set.seed(20260322 + rep)

  rep_results <- tryCatch({

    # --- (a) Generate data ---
    raw_data <- rate_cox_data_gen_complex(
      n          = N_SUBJECTS,
      f.alpha    = FRAILTY_VAR,
      r01        = R01,
      r02        = R02,
      rho        = RHO,
      beta       = BETA_VEC,
      censor_max = CENSOR_MAX
    )

    raw_data$type_true <- raw_data$type

    # --- (b) Introduce missingness ---
    data_miss <- apply_missingness(raw_data, MISS_PATTERN, MISS_PCT)

    # ==================================================================
    # ESTIMATOR 1: DR-PO-CF (cross-fitted, logistic + multinomial)
    # ==================================================================
    dr_cf <- tryCatch({
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
        estimator = "DR-PO-CF",
        pattern   = MISS_PATTERN,
        miss_pct  = MISS_PCT,
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
      data.frame(rep = rep, estimator = "DR-PO-CF",
                 pattern = MISS_PATTERN, miss_pct = MISS_PCT,
                 theta1 = NA_real_, theta2 = NA_real_,
                 se1 = NA_real_, se2 = NA_real_,
                 cov1 = NA_integer_, cov2 = NA_integer_,
                 status = "error", error_msg = conditionMessage(e),
                 stringsAsFactors = FALSE, row.names = NULL)
    })

    # ==================================================================
    # ESTIMATOR 2: CCA (complete-case analysis)
    # ==================================================================
    cca <- tryCatch({
      data_cc <- data_miss
      missing_events <- which(data_cc$event == 1 & is.na(data_cc$type))
      if (length(missing_events) > 0) {
        data_cc <- data_cc[-missing_events, ]
      }

      lm_cc <- transform_with_covariates_complex(data_cc, aa = AA)
      lm_cc <- generate_km_pseudoEst(lm_cc, tau = TAU)

      subj_po1 <- tapply(lm_cc$pseudoEst_km_type1, lm_cc$pid, mean, na.rm = TRUE)
      subj_po2 <- tapply(lm_cc$pseudoEst_km_type2, lm_cc$pid, mean, na.rm = TRUE)
      n_subj <- length(subj_po1)

      theta1_cc <- mean(subj_po1, na.rm = TRUE)
      theta2_cc <- mean(subj_po2, na.rm = TRUE)
      se1_cc <- sqrt(var(subj_po1, na.rm = TRUE) / n_subj)
      se2_cc <- sqrt(var(subj_po2, na.rm = TRUE) / n_subj)

      data.frame(
        rep       = rep,
        estimator = "CCA",
        pattern   = MISS_PATTERN,
        miss_pct  = MISS_PCT,
        theta1    = theta1_cc,
        theta2    = theta2_cc,
        se1       = se1_cc,
        se2       = se2_cc,
        cov1      = compute_coverage(theta1_cc, se1_cc, THETA_TRUE["type1"]),
        cov2      = compute_coverage(theta2_cc, se2_cc, THETA_TRUE["type2"]),
        status    = "success",
        error_msg = NA_character_,
        stringsAsFactors = FALSE, row.names = NULL
      )
    }, error = function(e) {
      data.frame(rep = rep, estimator = "CCA",
                 pattern = MISS_PATTERN, miss_pct = MISS_PCT,
                 theta1 = NA_real_, theta2 = NA_real_,
                 se1 = NA_real_, se2 = NA_real_,
                 cov1 = NA_integer_, cov2 = NA_integer_,
                 status = "error", error_msg = conditionMessage(e),
                 stringsAsFactors = FALSE, row.names = NULL)
    })

    # ==================================================================
    # ESTIMATOR 3: IPW-logistic
    # ==================================================================
    ipw_log <- tryCatch({
      res <- run_ipw_logistic(data_miss, AA, TAU, THETA_TRUE)
      data.frame(
        rep       = rep,
        estimator = "IPW-logistic",
        pattern   = MISS_PATTERN,
        miss_pct  = MISS_PCT,
        theta1    = res$theta1,
        theta2    = res$theta2,
        se1       = res$se1,
        se2       = res$se2,
        cov1      = compute_coverage(res$theta1, res$se1, THETA_TRUE["type1"]),
        cov2      = compute_coverage(res$theta2, res$se2, THETA_TRUE["type2"]),
        status    = "success",
        error_msg = NA_character_,
        stringsAsFactors = FALSE, row.names = NULL
      )
    }, error = function(e) {
      data.frame(rep = rep, estimator = "IPW-logistic",
                 pattern = MISS_PATTERN, miss_pct = MISS_PCT,
                 theta1 = NA_real_, theta2 = NA_real_,
                 se1 = NA_real_, se2 = NA_real_,
                 cov1 = NA_integer_, cov2 = NA_integer_,
                 status = "error", error_msg = conditionMessage(e),
                 stringsAsFactors = FALSE, row.names = NULL)
    })

    # ==================================================================
    # ESTIMATOR 4: IPW-RF
    # ==================================================================
    ipw_rf <- tryCatch({
      res <- run_ipw_rf(data_miss, AA, TAU, THETA_TRUE)
      data.frame(
        rep       = rep,
        estimator = "IPW-RF",
        pattern   = MISS_PATTERN,
        miss_pct  = MISS_PCT,
        theta1    = res$theta1,
        theta2    = res$theta2,
        se1       = res$se1,
        se2       = res$se2,
        cov1      = compute_coverage(res$theta1, res$se1, THETA_TRUE["type1"]),
        cov2      = compute_coverage(res$theta2, res$se2, THETA_TRUE["type2"]),
        status    = "success",
        error_msg = NA_character_,
        stringsAsFactors = FALSE, row.names = NULL
      )
    }, error = function(e) {
      data.frame(rep = rep, estimator = "IPW-RF",
                 pattern = MISS_PATTERN, miss_pct = MISS_PCT,
                 theta1 = NA_real_, theta2 = NA_real_,
                 se1 = NA_real_, se2 = NA_real_,
                 cov1 = NA_integer_, cov2 = NA_integer_,
                 status = "error", error_msg = conditionMessage(e),
                 stringsAsFactors = FALSE, row.names = NULL)
    })

    # Combine all estimators for this replicate
    rbind(dr_cf, cca, ipw_log, ipw_rf)

  }, error = function(e) {
    cat(sprintf("  [REP %d] DATA GENERATION FAILED: %s\n", rep, conditionMessage(e)))
    data.frame(
      rep       = rep,
      estimator = "ALL",
      pattern   = MISS_PATTERN,
      miss_pct  = MISS_PCT,
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
  cat(sprintf("  %-15s: %d/%d successful\n", est, n_ok, N_REPS))
}

# ============================================================================
# COMPUTE SUMMARY STATISTICS
# ============================================================================
compute_block5_metrics <- function(df, theta_true) {
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
  m <- compute_block5_metrics(sub, THETA_TRUE)
  m$estimator   <- est
  m$pattern     <- MISS_PATTERN
  m$miss_pct    <- MISS_PCT
  m$theta_true1 <- THETA_TRUE["type1"]
  m$theta_true2 <- THETA_TRUE["type2"]
  summary_list[[est]] <- m
}

summary_df <- do.call(rbind, summary_list)
rownames(summary_df) <- NULL

summary_df <- summary_df[, c("estimator", "pattern", "miss_pct", "n",
                              "theta_true1", "theta_true2",
                              "bias1", "bias2", "rmse1", "rmse2",
                              "emp_se1", "emp_se2", "mean_se1", "mean_se2",
                              "se_ratio1", "se_ratio2",
                              "coverage1", "coverage2")]

# ============================================================================
# PRINT SUMMARY
# ============================================================================
cat("\n============================================================\n")
cat(sprintf("BLOCK 5 SUMMARY: %s %d%%, n = %d\n",
            MISS_PATTERN, MISS_PCT, N_SUBJECTS))
cat(sprintf("Ground truth: type1 = %.6f, type2 = %.6f\n",
            THETA_TRUE["type1"], THETA_TRUE["type2"]))
cat("============================================================\n\n")

for (i in seq_len(nrow(summary_df))) {
  s <- summary_df[i, ]
  cat(sprintf("%-15s (n=%d)\n", s$estimator, s$n))
  cat(sprintf("  Type 1: bias=%+.5f  RMSE=%.5f  SE ratio=%.3f  coverage=%.3f\n",
              s$bias1, s$rmse1, s$se_ratio1, s$coverage1))
  cat(sprintf("  Type 2: bias=%+.5f  RMSE=%.5f  SE ratio=%.3f  coverage=%.3f\n",
              s$bias2, s$rmse2, s$se_ratio2, s$coverage2))
  cat("\n")
}

# ============================================================================
# SAVE RESULTS
# ============================================================================
results_path <- file.path(RESULTS_DIR,
                          sprintf("block5_%s_%dpct_results.csv",
                                  MISS_PATTERN, MISS_PCT))
summary_path <- file.path(RESULTS_DIR,
                          sprintf("block5_%s_%dpct_summary.csv",
                                  MISS_PATTERN, MISS_PCT))

write.csv(results_df, results_path, row.names = FALSE)
write.csv(summary_df, summary_path, row.names = FALSE)

cat("Results saved to:\n")
cat("  ", results_path, "\n")
cat("  ", summary_path, "\n")
cat("\n============================================================\n")
cat("Block 5 complete.\n")
cat(sprintf("Elapsed time: %.1f minutes\n",
            as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
cat("============================================================\n")
