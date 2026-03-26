# ============================================================================
# METADATA
# ============================================================================
# Description: Block 1 sanity check for two-stage IF variance estimator.
#              Verifies that (1) DR-oracle is unbiased, (2) IF-based variance
#              matches Monte Carlo variance, and (3) 95% CI coverage is nominal
#              at each sample size. Two estimators:
#                DR-PO-CF-oracle:  true nuisances from large auxiliary dataset
#                DR-PO-CF-correct: correctly specified parametric nuisances
# Last Updated: 2026-03-22
# ============================================================================

set.seed(20260322)

# ============================================================================
# PACKAGES
# ============================================================================
suppressPackageStartupMessages({
  library(here)
  library(survival)
  library(nnet)
  library(tidyverse)
})

# ============================================================================
# SOURCE SHARED INFRASTRUCTURE
# ============================================================================
source(here::here("R", "source_missing_types.R"))
source(here::here("R", "dr_pseudo_obs.R"))

# ============================================================================
# COMMAND-LINE ARGS (for SLURM)
# ============================================================================
args <- commandArgs(trailingOnly = TRUE)

N_REPS      <- as.integer(Sys.getenv("N_REPS",      ifelse(length(args) >= 1, args[1], "200")))
N_SIZE      <- as.integer(Sys.getenv("N_SIZE",       ifelse(length(args) >= 2, args[2], "500")))
RESULTS_DIR <- Sys.getenv("RESULTS_DIR", ifelse(length(args) >= 3, args[3], "results"))

# Validate N_SIZE
stopifnot(N_SIZE %in% c(200, 500, 1000, 2000))

# Make RESULTS_DIR absolute using project root
if (!startsWith(RESULTS_DIR, "/")) {
  RESULTS_DIR <- here::here(RESULTS_DIR)
}
if (!dir.exists(RESULTS_DIR)) {
  dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
}

cat("============================================================\n")
cat("BLOCK 1: IF SANITY CHECK\n")
cat("============================================================\n")
cat("N_REPS:     ", N_REPS, "\n")
cat("N_SIZE:     ", N_SIZE, "\n")
cat("RESULTS_DIR:", RESULTS_DIR, "\n")
cat("============================================================\n\n")

# ============================================================================
# DGM PARAMETERS
# ============================================================================
dgm_params <- list(
  f.alpha   = 0.5,
  r01       = 0.5,
  r02       = 0.3,
  rho       = 0.3,
  beta      = c(0.5, -0.3, 0.3, -0.2, 0.1, -0.1, 0.2, -0.15),
  censor_max = 5,
  complex_params = c(1, 1, 1, 1)
)

MISSING_PCT  <- 20     # MAR at 20%
AA           <- 0.5    # Landmark spacing
TAU          <- 2.5    # Pseudo-observation horizon (5 * aa)
N_FOLDS      <- 5      # Cross-fitting folds

# ============================================================================
# STEP 0: COMPUTE GROUND TRUTH THETA
# ============================================================================
# Generate a very large dataset with NO missingness to estimate true theta_k.
# theta_k = E[PO_k] = marginal type-k pseudo-observation mean.

cat("Computing ground truth theta from large MC sample (n = 50000)...\n")
set.seed(20260322 + 9999)

truth_data <- rate_cox_data_gen_complex(
  n            = 50000,
  f.alpha      = dgm_params$f.alpha,
  r01          = dgm_params$r01,
  r02          = dgm_params$r02,
  rho          = dgm_params$rho,
  beta         = dgm_params$beta,
  complex_params = dgm_params$complex_params,
  censor_max   = dgm_params$censor_max
)

# Transform to landmark format and compute pseudo-observations (no missingness)
truth_lm <- transform_with_covariates_complex(truth_data, aa = AA)
truth_lm <- generate_km_pseudoEst(truth_lm, tau = TAU)

theta_true <- c(
  type1 = mean(truth_lm$pseudoEst_km_type1, na.rm = TRUE),
  type2 = mean(truth_lm$pseudoEst_km_type2, na.rm = TRUE)
)

cat(sprintf("Ground truth theta: type1 = %.6f, type2 = %.6f\n\n",
            theta_true["type1"], theta_true["type2"]))

# Clean up large truth dataset
rm(truth_data, truth_lm)
gc(verbose = FALSE)

# ============================================================================
# STEP 1: BUILD ORACLE NUISANCE FUNCTIONS
# ============================================================================
# Oracle approach: fit correct parametric models on a large auxiliary dataset
# (n = 50000) generated from the same DGM with the same MAR mechanism.
# These are NOT truly oracle but approximate the true nuisance functions
# well enough for a sanity check.

cat("Building oracle nuisance models from large auxiliary dataset...\n")
set.seed(20260322 + 8888)

oracle_data <- rate_cox_data_gen_complex(
  n            = 50000,
  f.alpha      = dgm_params$f.alpha,
  r01          = dgm_params$r01,
  r02          = dgm_params$r02,
  rho          = dgm_params$rho,
  beta         = dgm_params$beta,
  complex_params = dgm_params$complex_params,
  censor_max   = dgm_params$censor_max
)

# Save true types then introduce MAR missingness
oracle_data$type_true <- oracle_data$type
oracle_data <- introduce_mar_missingness(oracle_data, MISSING_PCT)

# --- Oracle propensity model ---
# P(R = 1 | X, Z, XX2, x_correlated) fitted on 50k events
oracle_event_data <- oracle_data[oracle_data$event == 1, ]
oracle_event_data$observed <- as.integer(!is.na(oracle_event_data$type))

# Use the same covariates that introduce_mar_missingness() uses
# MAR mechanism: score = -1.5 + 1.5*(x-0.5)^2 + 1.0*(xx2-0.5)^2
#                       + 1.2*z*x + 0.8*x*xx2
# We fit a logistic model with these terms to approximate the true propensity
oracle_prop_fit <- glm(
  observed ~ I((x - 0.5)^2) + I((xx2 - 0.5)^2) + I(z * x) + I(x * xx2),
  data = oracle_event_data, family = binomial(link = "logit")
)

cat(sprintf("Oracle propensity model: AIC = %.1f, mean(pi) = %.3f\n",
            AIC(oracle_prop_fit), mean(predict(oracle_prop_fit, type = "response"))))

# --- Oracle outcome model ---
# P(type = k | X, Z, XX2, x_correlated, R = 1) fitted on 50k observed events
oracle_obs_data <- oracle_event_data[oracle_event_data$observed == 1, ]
oracle_obs_data$type_f <- factor(oracle_obs_data$type_true)

oracle_out_fit <- nnet::multinom(
  type_f ~ x + z + xx2 + x_correlated + I(x * z) + I(x * xx2),
  data = oracle_obs_data, trace = FALSE
)

cat(sprintf("Oracle outcome model: AIC = %.1f\n\n", AIC(oracle_out_fit)))

# Clean up
rm(oracle_event_data, oracle_obs_data)
gc(verbose = FALSE)

# ============================================================================
# ORACLE NUISANCE WRAPPER FUNCTIONS
# ============================================================================
# These are passed to run_dr_po_pipeline() via fit_propensity_fn / fit_outcome_fn.
# They IGNORE the training data and return predictions from the oracle models.

fit_propensity_oracle <- function(data, covariates = NULL) {
  # Predict using pre-trained oracle model (ignores training data)
  predict_fn <- function(newdata) {
    p <- predict(oracle_prop_fit, newdata = newdata, type = "response")
    pmax(p, 0.01)
  }

  # Compute scores for the input data (needed by infrastructure)
  is_event <- data$event == 1
  event_data <- data[is_event, ]
  scores <- predict_fn(event_data)

  list(
    model   = oracle_prop_fit,
    scores  = scores,
    predict = predict_fn,
    method  = "oracle_logistic"
  )
}

fit_outcome_oracle <- function(data, covariates = NULL) {
  predict_fn <- function(newdata) {
    probs <- predict(oracle_out_fit, newdata = newdata, type = "probs")
    if (is.null(dim(probs))) {
      probs <- cbind(1 - probs, probs)
    }
    probs
  }

  list(
    model   = oracle_out_fit,
    predict = predict_fn,
    method  = "oracle_multinomial",
    K       = 2
  )
}

# ============================================================================
# SINGLE-REPLICATE FUNCTION
# ============================================================================
run_one_replicate <- function(rep_id, n, dgm_params, missing_pct, aa, tau,
                              n_folds, theta_true) {

  # --- Generate data ---
  data <- rate_cox_data_gen_complex(
    n              = n,
    f.alpha        = dgm_params$f.alpha,
    r01            = dgm_params$r01,
    r02            = dgm_params$r02,
    rho            = dgm_params$rho,
    beta           = dgm_params$beta,
    complex_params = dgm_params$complex_params,
    censor_max     = dgm_params$censor_max
  )

  data$type_true <- data$type

  # --- Introduce MAR missingness ---
  data <- introduce_mar_missingness(data, missing_pct)

  actual_missing <- mean(is.na(data$type[data$event == 1])) * 100

  # ------------------------------------------------------------------
  # ESTIMATOR 1: DR-PO-CF-oracle (true nuisances, no estimation error)
  # ------------------------------------------------------------------
  oracle_result <- tryCatch({
    res <- run_dr_po_pipeline(
      data              = data,
      aa                = aa,
      tau               = tau,
      n_folds           = n_folds,
      seed              = rep_id,
      fit_propensity_fn = fit_propensity_oracle,
      fit_outcome_fn    = fit_outcome_oracle
    )
    list(
      theta       = res$theta,
      se_naive    = res$se_naive,
      se_twostage = res$se_twostage,
      success     = TRUE,
      error       = NA_character_
    )
  }, error = function(e) {
    list(
      theta       = c(type1 = NA_real_, type2 = NA_real_),
      se_naive    = c(type1 = NA_real_, type2 = NA_real_),
      se_twostage = c(type1 = NA_real_, type2 = NA_real_),
      success     = FALSE,
      error       = conditionMessage(e)
    )
  })

  # ------------------------------------------------------------------
  # ESTIMATOR 2: DR-PO-CF-correct (correctly specified parametric)
  # ------------------------------------------------------------------
  correct_result <- tryCatch({
    res <- run_dr_po_pipeline(
      data             = data,
      aa               = aa,
      tau              = tau,
      n_folds          = n_folds,
      propensity_method = "logistic",
      outcome_method    = "multinomial",
      seed             = rep_id
    )
    list(
      theta       = res$theta,
      se_naive    = res$se_naive,
      se_twostage = res$se_twostage,
      success     = TRUE,
      error       = NA_character_
    )
  }, error = function(e) {
    list(
      theta       = c(type1 = NA_real_, type2 = NA_real_),
      se_naive    = c(type1 = NA_real_, type2 = NA_real_),
      se_twostage = c(type1 = NA_real_, type2 = NA_real_),
      success     = FALSE,
      error       = conditionMessage(e)
    )
  })

  # --- Compute coverage ---
  compute_coverage <- function(theta_hat, se, theta_true, alpha = 0.05) {
    z <- qnorm(1 - alpha / 2)
    lo <- theta_hat - z * se
    hi <- theta_hat + z * se
    as.integer(theta_true >= lo & theta_true <= hi)
  }

  data.frame(
    rep_id          = rep_id,
    n               = n,
    actual_missing  = actual_missing,

    # Oracle
    oracle_theta1        = oracle_result$theta["type1"],
    oracle_theta2        = oracle_result$theta["type2"],
    oracle_se_naive1     = oracle_result$se_naive["type1"],
    oracle_se_naive2     = oracle_result$se_naive["type2"],
    oracle_se_twostage1  = oracle_result$se_twostage["type1"],
    oracle_se_twostage2  = oracle_result$se_twostage["type2"],
    oracle_cov_naive1    = compute_coverage(oracle_result$theta["type1"],
                                            oracle_result$se_naive["type1"],
                                            theta_true["type1"]),
    oracle_cov_naive2    = compute_coverage(oracle_result$theta["type2"],
                                            oracle_result$se_naive["type2"],
                                            theta_true["type2"]),
    oracle_cov_twostage1 = compute_coverage(oracle_result$theta["type1"],
                                            oracle_result$se_twostage["type1"],
                                            theta_true["type1"]),
    oracle_cov_twostage2 = compute_coverage(oracle_result$theta["type2"],
                                            oracle_result$se_twostage["type2"],
                                            theta_true["type2"]),
    oracle_success       = oracle_result$success,

    # Correct
    correct_theta1        = correct_result$theta["type1"],
    correct_theta2        = correct_result$theta["type2"],
    correct_se_naive1     = correct_result$se_naive["type1"],
    correct_se_naive2     = correct_result$se_naive["type2"],
    correct_se_twostage1  = correct_result$se_twostage["type1"],
    correct_se_twostage2  = correct_result$se_twostage["type2"],
    correct_cov_naive1    = compute_coverage(correct_result$theta["type1"],
                                             correct_result$se_naive["type1"],
                                             theta_true["type1"]),
    correct_cov_naive2    = compute_coverage(correct_result$theta["type2"],
                                             correct_result$se_naive["type2"],
                                             theta_true["type2"]),
    correct_cov_twostage1 = compute_coverage(correct_result$theta["type1"],
                                             correct_result$se_twostage["type1"],
                                             theta_true["type1"]),
    correct_cov_twostage2 = compute_coverage(correct_result$theta["type2"],
                                             correct_result$se_twostage["type2"],
                                             theta_true["type2"]),
    correct_success       = correct_result$success,

    stringsAsFactors = FALSE,
    row.names        = NULL
  )
}

# ============================================================================
# MAIN SIMULATION LOOP
# ============================================================================
cat("Starting simulation loop...\n\n")

all_results <- vector("list", N_REPS)
n_success   <- 0
n_fail      <- 0
t_start     <- Sys.time()

for (rep in 1:N_REPS) {
  # Per-replicate seed: deterministic from master seed + rep_id
  set.seed(20260322 + rep)

  rep_result <- tryCatch({
    run_one_replicate(
      rep_id      = rep,
      n           = N_SIZE,
      dgm_params  = dgm_params,
      missing_pct = MISSING_PCT,
      aa          = AA,
      tau         = TAU,
      n_folds     = N_FOLDS,
      theta_true  = theta_true
    )
  }, error = function(e) {
    cat(sprintf("  [REP %d] FAILED: %s\n", rep, conditionMessage(e)))
    NULL
  })

  if (!is.null(rep_result)) {
    all_results[[rep]] <- rep_result
    n_success <- n_success + 1
  } else {
    n_fail <- n_fail + 1
  }

  # Progress report every 10 reps
 if (rep %% 10 == 0 || rep == 1) {
    elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
    rate    <- rep / elapsed
    eta     <- (N_REPS - rep) / rate
    cat(sprintf("[REP %d/%d] elapsed %.1f min | rate %.1f reps/min | ETA %.1f min | %d ok / %d fail\n",
                rep, N_REPS, elapsed, rate, eta, n_success, n_fail))
  }
}

cat(sprintf("\nSimulation complete: %d/%d successful (%.1f%% failure rate)\n",
            n_success, N_REPS, 100 * n_fail / N_REPS))

# ============================================================================
# COMBINE RESULTS
# ============================================================================
results_df <- bind_rows(Filter(Negate(is.null), all_results))

if (nrow(results_df) == 0) {
  stop("All replicates failed. Check error messages above.")
}

# Save raw results
raw_path <- file.path(RESULTS_DIR, sprintf("block1_n%d_results.csv", N_SIZE))
write.csv(results_df, raw_path, row.names = FALSE)
cat(sprintf("Raw results saved to: %s\n", raw_path))

# ============================================================================
# COMPUTE SUMMARY STATISTICS
# ============================================================================
summarize_estimator <- function(df, prefix, theta_true) {
  # Extract columns by prefix
  theta1  <- df[[paste0(prefix, "_theta1")]]
  theta2  <- df[[paste0(prefix, "_theta2")]]
  se_n1   <- df[[paste0(prefix, "_se_naive1")]]
  se_n2   <- df[[paste0(prefix, "_se_naive2")]]
  se_ts1  <- df[[paste0(prefix, "_se_twostage1")]]
  se_ts2  <- df[[paste0(prefix, "_se_twostage2")]]
  cov_n1  <- df[[paste0(prefix, "_cov_naive1")]]
  cov_n2  <- df[[paste0(prefix, "_cov_naive2")]]
  cov_ts1 <- df[[paste0(prefix, "_cov_twostage1")]]
  cov_ts2 <- df[[paste0(prefix, "_cov_twostage2")]]

  # Remove NAs
  valid <- !is.na(theta1) & !is.na(theta2)
  n_valid <- sum(valid)

  if (n_valid < 2) {
    return(data.frame(estimator = prefix, n_valid = n_valid,
                      note = "Insufficient valid replicates", stringsAsFactors = FALSE))
  }

  theta1 <- theta1[valid]; theta2 <- theta2[valid]
  se_n1  <- se_n1[valid];  se_n2  <- se_n2[valid]
  se_ts1 <- se_ts1[valid]; se_ts2 <- se_ts2[valid]
  cov_n1 <- cov_n1[valid]; cov_n2 <- cov_n2[valid]
  cov_ts1 <- cov_ts1[valid]; cov_ts2 <- cov_ts2[valid]

  data.frame(
    estimator        = prefix,
    n_valid          = n_valid,

    # Type 1
    theta_true_1     = theta_true["type1"],
    mean_theta1      = mean(theta1),
    bias_1           = mean(theta1) - theta_true["type1"],
    rel_bias_1       = (mean(theta1) - theta_true["type1"]) / theta_true["type1"] * 100,
    mc_var_1         = var(theta1),
    mc_se_1          = sd(theta1),
    mean_se_naive_1  = mean(se_n1),
    mean_se_ts_1     = mean(se_ts1),
    mean_var_naive_1 = mean(se_n1^2),
    mean_var_ts_1    = mean(se_ts1^2),
    var_ratio_naive_1  = mean(se_n1^2) / var(theta1),
    var_ratio_ts_1     = mean(se_ts1^2) / var(theta1),
    coverage_naive_1   = mean(cov_n1, na.rm = TRUE),
    coverage_ts_1      = mean(cov_ts1, na.rm = TRUE),

    # Type 2
    theta_true_2     = theta_true["type2"],
    mean_theta2      = mean(theta2),
    bias_2           = mean(theta2) - theta_true["type2"],
    rel_bias_2       = (mean(theta2) - theta_true["type2"]) / theta_true["type2"] * 100,
    mc_var_2         = var(theta2),
    mc_se_2          = sd(theta2),
    mean_se_naive_2  = mean(se_n2),
    mean_se_ts_2     = mean(se_ts2),
    mean_var_naive_2 = mean(se_n2^2),
    mean_var_ts_2    = mean(se_ts2^2),
    var_ratio_naive_2  = mean(se_n2^2) / var(theta2),
    var_ratio_ts_2     = mean(se_ts2^2) / var(theta2),
    coverage_naive_2   = mean(cov_n2, na.rm = TRUE),
    coverage_ts_2      = mean(cov_ts2, na.rm = TRUE),

    stringsAsFactors = FALSE,
    row.names        = NULL
  )
}

summary_oracle  <- summarize_estimator(results_df, "oracle",  theta_true)
summary_correct <- summarize_estimator(results_df, "correct", theta_true)
summary_df      <- bind_rows(summary_oracle, summary_correct)

# Save summary
summary_path <- file.path(RESULTS_DIR, sprintf("block1_n%d_summary.csv", N_SIZE))
write.csv(summary_df, summary_path, row.names = FALSE)
cat(sprintf("Summary saved to: %s\n", summary_path))

# ============================================================================
# PRINT SUMMARY TABLE
# ============================================================================
cat("\n")
cat("============================================================\n")
cat(sprintf("BLOCK 1 SUMMARY: n = %d, %d replicates\n", N_SIZE, nrow(results_df)))
cat(sprintf("Ground truth: theta1 = %.6f, theta2 = %.6f\n",
            theta_true["type1"], theta_true["type2"]))
cat("============================================================\n\n")

for (i in 1:nrow(summary_df)) {
  s <- summary_df[i, ]
  if ("note" %in% names(s) && !is.na(s$note)) {
    cat(sprintf("Estimator: %s -- %s\n\n", s$estimator, s$note))
    next
  }
  cat(sprintf("Estimator: %s (%d valid reps)\n", s$estimator, s$n_valid))
  cat("------------------------------------------------------------\n")
  cat(sprintf("  TYPE 1:\n"))
  cat(sprintf("    Mean theta_hat:     %.6f\n", s$mean_theta1))
  cat(sprintf("    Bias:               %.6f  (%.2f%%)\n", s$bias_1, s$rel_bias_1))
  cat(sprintf("    MC SE:              %.6f\n", s$mc_se_1))
  cat(sprintf("    Mean SE (naive):    %.6f\n", s$mean_se_naive_1))
  cat(sprintf("    Mean SE (twostage): %.6f\n", s$mean_se_ts_1))
  cat(sprintf("    Var ratio (naive):  %.4f  (target: 1.0)\n", s$var_ratio_naive_1))
  cat(sprintf("    Var ratio (2stage): %.4f  (target: 1.0)\n", s$var_ratio_ts_1))
  cat(sprintf("    Coverage (naive):   %.3f  (target: 0.950)\n", s$coverage_naive_1))
  cat(sprintf("    Coverage (2stage):  %.3f  (target: 0.950)\n", s$coverage_ts_1))
  cat(sprintf("  TYPE 2:\n"))
  cat(sprintf("    Mean theta_hat:     %.6f\n", s$mean_theta2))
  cat(sprintf("    Bias:               %.6f  (%.2f%%)\n", s$bias_2, s$rel_bias_2))
  cat(sprintf("    MC SE:              %.6f\n", s$mc_se_2))
  cat(sprintf("    Mean SE (naive):    %.6f\n", s$mean_se_naive_2))
  cat(sprintf("    Mean SE (twostage): %.6f\n", s$mean_se_ts_2))
  cat(sprintf("    Var ratio (naive):  %.4f  (target: 1.0)\n", s$var_ratio_naive_2))
  cat(sprintf("    Var ratio (2stage): %.4f  (target: 1.0)\n", s$var_ratio_ts_2))
  cat(sprintf("    Coverage (naive):   %.3f  (target: 0.950)\n", s$coverage_naive_2))
  cat(sprintf("    Coverage (2stage):  %.3f  (target: 0.950)\n", s$coverage_ts_2))
  cat("\n")
}

# ============================================================================
# DIAGNOSTIC CHECKS
# ============================================================================
cat("============================================================\n")
cat("DIAGNOSTIC FLAGS\n")
cat("============================================================\n")

for (i in 1:nrow(summary_df)) {
  s <- summary_df[i, ]
  if ("note" %in% names(s) && !is.na(s$note)) next

  flags <- character(0)

  # Bias check: |relative bias| should be < 5%
  if (abs(s$rel_bias_1) > 5)  flags <- c(flags, sprintf("Type1 bias %.2f%%", s$rel_bias_1))
  if (abs(s$rel_bias_2) > 5)  flags <- c(flags, sprintf("Type2 bias %.2f%%", s$rel_bias_2))

  # Variance ratio check: should be in [0.8, 1.2]
  for (vr_name in c("var_ratio_naive_1", "var_ratio_ts_1",
                     "var_ratio_naive_2", "var_ratio_ts_2")) {
    vr <- s[[vr_name]]
    if (!is.na(vr) && (vr < 0.8 || vr > 1.2)) {
      flags <- c(flags, sprintf("%s = %.3f", vr_name, vr))
    }
  }

  # Coverage check: should be in [0.90, 0.98]
  for (cv_name in c("coverage_naive_1", "coverage_ts_1",
                     "coverage_naive_2", "coverage_ts_2")) {
    cv <- s[[cv_name]]
    if (!is.na(cv) && (cv < 0.90 || cv > 0.98)) {
      flags <- c(flags, sprintf("%s = %.3f", cv_name, cv))
    }
  }

  if (length(flags) == 0) {
    cat(sprintf("  %s: ALL CHECKS PASSED\n", s$estimator))
  } else {
    cat(sprintf("  %s: FLAGS (%d):\n", s$estimator, length(flags)))
    for (f in flags) cat(sprintf("    - %s\n", f))
  }
}

cat("\n============================================================\n")
cat("Block 1 complete.\n")
cat(sprintf("Elapsed time: %.1f minutes\n",
            as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
cat("============================================================\n")
