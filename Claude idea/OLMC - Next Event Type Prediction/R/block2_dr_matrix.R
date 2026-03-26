# =============================================================================
# block2_dr_matrix.R
# Block 2: Double-Robustness Matrix for OLMC
#
# Scientific question: Does the estimator stay consistent under one-correct
# nuisance specification?
#
# DGM:
#   - K = 3, n = 1500
#   - Censoring: 25-30%, history-dependent (informative)
#   - Death: 20-25%, correlated with recurrent event risk (shared frailty
#     sigma^2 = 0.5)
#   - Recurrent hazard: strong dependence on count, last type, gap time
#   - history_on_rec = TRUE, history_on_D = TRUE
#
# Estimators (2x2 DR matrix + 2 single-model):
#   - DR-both-correct : correct OR + correct G_C
#   - DR-G-wrong      : correct OR + misspecified G_C (KM ignoring covariates)
#   - DR-OR-wrong     : misspecified OR (intercept-only logistic) + correct G_C
#   - DR-both-wrong   : misspecified OR + misspecified G_C
#   - OR-only         : outcome regression only (no IPCW correction)
#   - IPCW-only       : IPCW only (no outcome regression)
#
# Kill criterion: No separation between one-correct and both-wrong conditions.
#
# Output: results/block2/block2_cond{CONDITION}_reps{START}-{END}.csv
#
# Usage (SLURM):
#   Rscript block2_dr_matrix.R
#   or via env vars: BLOCK2_REP_START, BLOCK2_N_REPS, BLOCK2_CONDITION
#
# Last Updated: 2026-03-21
# =============================================================================

set.seed(20260321)

suppressPackageStartupMessages({
  library(tidyverse)
  library(survival)
  library(here)
})

# ---- Source project functions ----
script_dir <- tryCatch(here::here(), error = function(e) ".")
source(file.path(script_dir, "R/functions_olmc.R"))
source(file.path(script_dir, "R/dr_estimator.R"))
source(file.path(script_dir, "R/evaluation.R"))

# =============================================================================
# COMMAND-LINE / ENV ARGUMENTS
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
parse_arg <- function(args, flag, default) {
  idx <- which(args == flag)
  if (length(idx) > 0 && idx < length(args)) as.numeric(args[idx + 1]) else default
}
parse_arg_str <- function(args, flag, default) {
  idx <- which(args == flag)
  if (length(idx) > 0 && idx < length(args)) args[idx + 1] else default
}

REP_START <- as.integer(Sys.getenv("BLOCK2_REP_START",
                                    unset = parse_arg(args, "--rep_start", 1)))
N_REPS    <- as.integer(Sys.getenv("BLOCK2_N_REPS",
                                    unset = parse_arg(args, "--n_reps", 200)))
CONDITION <- Sys.getenv("BLOCK2_CONDITION",
                         unset = parse_arg_str(args, "--condition", "all"))

VALID_CONDITIONS <- c("DR-both-correct", "DR-G-wrong", "DR-OR-wrong",
                       "DR-both-wrong", "OR-only", "IPCW-only")

if (CONDITION != "all" && !(CONDITION %in% VALID_CONDITIONS)) {
  stop("Invalid BLOCK2_CONDITION: ", CONDITION,
       "\nValid options: ", paste(VALID_CONDITIONS, collapse = ", "), ", all")
}

cat(sprintf(
  "Block 2 DR Matrix | n=1500 | reps=%d-%d | condition=%s\n",
  REP_START, REP_START + N_REPS - 1, CONDITION
))

# =============================================================================
# DGM PARAMETERS (Block 2: K=3, history-dependent, informative censoring)
# =============================================================================

K           <- 3
N_SIM       <- 1500
W           <- 0.5          # prediction window: 6 months
LANDMARKS   <- seq(0.5, 3.0, by = 0.5)
FRAILTY_VAR <- 0.5          # sigma^2 (shared frailty)
P           <- 4            # covariates: z, x, x2, x3

# Baseline hazards for K=3
LAMBDA0_REC <- c(0.35, 0.30, 0.25)   # type 1, 2, 3 baseline recurrent hazards
LAMBDA0_D   <- 0.08                    # baseline death hazard (~20-25% by 3 yr)

# Covariate log-HRs (K x P matrix, rows = types)
BETA_REC <- matrix(c(
   0.50, -0.30,  0.20, -0.20,   # type 1: z, x, x2, x3
  -0.30,  0.40, -0.10,  0.30,   # type 2
   0.20, -0.20,  0.40, -0.10    # type 3
), nrow = K, ncol = P, byrow = TRUE)

BETA_D <- c(0.30, -0.20, 0.10, 0.00)

# History-dependent censoring parameters
CENSOR_TYPE  <- "history"
CENSOR_PARAM <- list(base_rate = 0.20,
                      history_coef = c(0.15, -0.10, 0.05, 0.00))

# History effects on recurrent and death hazards
HISTORY_EFFECTS <- list(
  count_effect   =  0.10,
  gap_effect     = -0.05,
  last_type_same =  0.20
)

# =============================================================================
# GROUND TRUTH via MONTE CARLO (history effects make closed-form intractable)
# =============================================================================

cat("Computing ground truth mu_k(h) via Monte Carlo (n=50000, no censoring)...\n")
t0_truth <- proc.time()

set.seed(20260321 + 999)  # separate seed for truth computation

truth_data <- generate_olmc_data(
  n            = 50000,
  K            = K,
  lambda0_rec  = LAMBDA0_REC,
  lambda0_D    = LAMBDA0_D,
  frailty_var  = FRAILTY_VAR,
  beta_rec     = BETA_REC,
  beta_D       = BETA_D,
  censor_type  = "independent",
  censor_param = 1e-6,          # near-zero censoring rate -> effectively no censoring
  max_follow   = 10.0,          # long follow-up to avoid admin censoring in window
  history_effects = HISTORY_EFFECTS,
  history_on_rec  = TRUE,
  history_on_D    = TRUE
)

truth_lm <- build_landmark_dataset(truth_data, landmarks = LANDMARKS, w = W, K = K)

# Compute empirical mu_k(h) from the uncensored large sample
strata <- c("H0", "H1", "H2", "H3")
truth_list <- vector("list", length(strata))

for (h in strata) {
  rows_h <- truth_lm[truth_lm$history_stratum == h, ]
  n_h <- nrow(rows_h)
  if (n_h == 0) {
    truth_list[[which(strata == h)]] <- data.frame(
      history_stratum = h,
      k = 1:K,
      mu_true = NA_real_,
      pi_true = NA_real_,
      q_true  = NA_real_
    )
    next
  }

  mu_k <- numeric(K)
  for (k in 1:K) {
    # mu_k(h) = P(T_sN <= w, J_s = k, T_sN < T_sD | H_s = h)
    # In uncensored data, delta_Nk is 1 iff recurrent event of type k happened
    # first in window, before death and before w
    mu_k[k] <- mean(rows_h[[paste0("delta_N", k)]], na.rm = TRUE)
  }

  q_h  <- sum(mu_k)
  pi_k <- if (q_h > 1e-6) mu_k / q_h else rep(1/K, K)

  truth_list[[which(strata == h)]] <- data.frame(
    history_stratum = h,
    k       = 1:K,
    mu_true = mu_k,
    pi_true = pi_k,
    q_true  = q_h
  )
}

TRUE_MU_DF <- bind_rows(truth_list)

elapsed_truth <- (proc.time() - t0_truth)[["elapsed"]]
cat(sprintf("Ground truth computed in %.1fs (%d landmark rows)\n",
            elapsed_truth, nrow(truth_lm)))
cat("\nTrue mu_k(h) values:\n")
print(as.data.frame(TRUE_MU_DF), digits = 4)
cat("\n")

# Clean up large truth objects
rm(truth_data, truth_lm)
gc()

# Reset master seed after truth computation
set.seed(20260321)

# =============================================================================
# MISSPECIFIED NUISANCE WRAPPERS
# =============================================================================

#' Wrapper for misspecified G_C: fits intercept-only Cox (KM) ignoring covariates
#'
#' Returns a censoring model object compatible with evaluate_gc().
#' Forces formula_rhs = "1" so the Cox model ignores all covariates.
fit_censoring_model_wrong <- function(lm_data, K = 3, formula_rhs = NULL) {
  # Ignore the formula_rhs argument; always fit intercept-only
  lm_data$C_obs   <- lm_data$tau_i
  died_in_window   <- is.finite(lm_data$T_sD) & lm_data$T_sD <= lm_data$tau_i
  lm_data$C_event <- as.integer(lm_data$delta_N == 0 & !died_in_window)

  X <- get_nuisance_covariates(lm_data, K = K, include_landmark_time = TRUE)
  X[is.na(X)] <- 0

  df_for_cox         <- as.data.frame(X)
  df_for_cox$C_obs   <- lm_data$C_obs
  df_for_cox$C_event <- lm_data$C_event

  # Intercept-only Cox = Kaplan-Meier (ignores all covariates)
  cox_fit <- coxph(Surv(C_obs, C_event) ~ 1, data = df_for_cox, ties = "breslow")

  bh <- basehaz(cox_fit, centered = FALSE)
  list(cox_fit = cox_fit, basehaz = bh, X_names = colnames(X))
}


#' Wrapper for misspecified OR: fits intercept-only logistic for each type k
#'
#' Returns outcome model list compatible with predict_outcome().
fit_outcome_models_wrong <- function(lm_data, K = 3, method = "logistic") {
  X <- get_nuisance_covariates(lm_data, K = K, include_landmark_time = TRUE)
  X[is.na(X)] <- 0

  models <- vector("list", K)

  for (k in 1:K) {
    y_k <- lm_data[[paste0("delta_N", k)]]
    df_fit    <- as.data.frame(X)
    df_fit$y  <- y_k

    # Intercept-only logistic (ignores all covariates)
    mod <- glm(y ~ 1, data = df_fit, family = binomial())
    models[[k]] <- list(model = mod, method = "logistic", X_names = colnames(X))
  }

  models
}

# =============================================================================
# MODIFIED cross_fit_dr THAT ACCEPTS CUSTOM FIT FUNCTIONS
# =============================================================================

#' Cross-fitted DR estimator with pluggable nuisance fitting functions.
#'
#' Extends cross_fit_dr() by accepting custom fitting functions for censoring
#' and outcome models, enabling misspecification experiments.
#'
#' @param lm_data           full landmark dataset
#' @param K                 number of event types
#' @param w                 prediction window
#' @param V                 number of cross-fitting folds
#' @param outcome_method    "logistic" or "ranger"
#' @param custom_fit_gc     custom censoring model fitter (signature: f(lm_train, K))
#' @param custom_fit_or     custom outcome model fitter (signature: f(lm_train, K, method))
#' @param oracle_gc         oracle G_C function (overrides custom_fit_gc)
#' @param oracle_Mk         oracle M_k function (overrides custom_fit_or)
#' @param oracle_Lk         oracle Lambda_k function
cross_fit_dr_custom <- function(
  lm_data,
  K              = 3,
  w              = 0.5,
  V              = 5,
  outcome_method = "logistic",
  custom_fit_gc  = NULL,
  custom_fit_or  = NULL,
  oracle_gc      = NULL,
  oracle_Mk      = NULL,
  oracle_Lk      = NULL
) {

  # Add w as column for use inside helper functions
  lm_data$w_val <- w

  strata <- levels(lm_data$history_stratum)
  n_rows <- nrow(lm_data)

  # ---- Create subject-level folds ----
  pids       <- unique(lm_data$pid)
  n_subjects <- length(pids)
  fold_assign <- sample(rep(1:V, length.out = n_subjects))
  names(fold_assign) <- as.character(pids)
  lm_data$fold <- fold_assign[as.character(lm_data$pid)]

  # Storage for EIF scores
  score_mat <- matrix(NA_real_, nrow = n_rows, ncol = K)
  colnames(score_mat) <- paste0("score_k", 1:K)

  # ---- Cross-fitting loop ----
  for (v in 1:V) {
    train_idx <- lm_data$fold != v
    test_idx  <- lm_data$fold == v

    lm_train <- lm_data[train_idx, ]
    lm_test  <- lm_data[test_idx, ]

    if (nrow(lm_train) < 20 || nrow(lm_test) < 5) next

    X_test <- get_nuisance_covariates(lm_test, K = K, include_landmark_time = TRUE)
    X_test[is.na(X_test)] <- 0

    # ---- Outcome regression M_k ----
    if (!is.null(oracle_Mk)) {
      M_pred <- oracle_Mk(lm_test)
    } else if (!is.null(custom_fit_or)) {
      om <- custom_fit_or(lm_train, K = K, method = outcome_method)
      M_pred <- predict_outcome(om, X_test, K = K)
    } else {
      om <- fit_outcome_models(lm_train, K = K, method = outcome_method)
      M_pred <- predict_outcome(om, X_test, K = K)
    }

    # ---- Censoring model G_C ----
    if (!is.null(oracle_gc)) {
      gc_model_v <- NULL
    } else if (!is.null(custom_fit_gc)) {
      gc_model_v <- custom_fit_gc(lm_train, K = K)
    } else {
      gc_model_v <- fit_censoring_model(lm_train, K = K)
    }

    # ---- Type-k hazard models Lambda_k ----
    if (!is.null(oracle_Lk)) {
      lk_models <- NULL
    } else {
      lk_models <- fit_type_hazard_models(lm_train, K = K)
    }

    # ---- EIF scores ----
    n_test <- nrow(lm_test)
    IF_mat <- matrix(0.0, nrow = n_test, ncol = K)

    if (!is.null(oracle_gc) || !is.null(oracle_Lk)) {
      IF_mat <- compute_if_oracle(lm_test, oracle_gc, oracle_Lk, K = K, w = w)
    } else {
      IF_mat <- compute_if_corrections(lm_test, gc_model_v, lk_models, K = K, w = w)
    }

    # EIF scores: M_k(H_si) + IF_correction_k(i)
    for (k in 1:K) {
      score_mat[test_idx, k] <- M_pred[, k] + IF_mat[, k]
    }
  }

  # ---- Aggregate by stratum ----
  results <- vector("list", length(strata) * K)
  idx <- 0L

  for (h in strata) {
    h_rows <- lm_data$history_stratum == h & !is.na(lm_data$history_stratum)
    pids_h <- lm_data$pid[h_rows]

    for (k in 1:K) {
      idx <- idx + 1L
      scores_k <- score_mat[h_rows, k]
      if (all(is.na(scores_k))) {
        results[[idx]] <- data.frame(
          history_stratum = h, k = k,
          mu_hat = NA, se = NA, ci_lo = NA, ci_hi = NA,
          n_rows = 0L, n_subjects = 0L
        )
        next
      }

      pid_scores <- tapply(scores_k, pids_h, mean, na.rm = TRUE)
      n_sub      <- length(pid_scores)
      mu_hat     <- mean(pid_scores, na.rm = TRUE)
      se_sub     <- sqrt(var(pid_scores, na.rm = TRUE) / n_sub)

      results[[idx]] <- data.frame(
        history_stratum = h,
        k        = k,
        mu_hat   = mu_hat,
        se       = se_sub,
        ci_lo    = mu_hat - 1.96 * se_sub,
        ci_hi    = mu_hat + 1.96 * se_sub,
        n_rows   = sum(h_rows),
        n_subjects = n_sub
      )
    }
  }

  bind_rows(results)
}


# =============================================================================
# SIMULATION FUNCTION: ONE REPLICATE
# =============================================================================

run_one_rep <- function(rep_id, n, condition = "DR-both-correct") {

  seed_val <- rep_id * 10000 + n
  set.seed(seed_val)

  # ---- 1. Generate data ----
  event_data <- generate_olmc_data(
    n               = n,
    K               = K,
    lambda0_rec     = LAMBDA0_REC,
    lambda0_D       = LAMBDA0_D,
    frailty_var     = FRAILTY_VAR,
    beta_rec        = BETA_REC,
    beta_D          = BETA_D,
    censor_type     = CENSOR_TYPE,
    censor_param    = CENSOR_PARAM,
    max_follow      = 3.0,
    history_effects = HISTORY_EFFECTS,
    history_on_rec  = TRUE,
    history_on_D    = TRUE
  )

  if (is.null(event_data) || nrow(event_data) == 0) {
    warning("Empty event data at rep ", rep_id)
    return(NULL)
  }

  # ---- 2. Build landmark dataset ----
  lm_data <- tryCatch(
    build_landmark_dataset(event_data, landmarks = LANDMARKS, w = W, K = K),
    error = function(e) {
      warning("Landmark build failed rep ", rep_id, ": ", e$message)
      NULL
    }
  )
  if (is.null(lm_data) || nrow(lm_data) < 20) return(NULL)

  # ---- 3. Compute DR estimates under the specified condition ----
  dr_results <- tryCatch({

    if (condition == "DR-both-correct") {
      # Correct OR (logistic with all covariates) + correct G_C (Cox with all covariates)
      cross_fit_dr_custom(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic"
      )

    } else if (condition == "DR-G-wrong") {
      # Correct OR + misspecified G_C (intercept-only Cox / KM)
      cross_fit_dr_custom(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic",
        custom_fit_gc  = fit_censoring_model_wrong
      )

    } else if (condition == "DR-OR-wrong") {
      # Misspecified OR (intercept-only logistic) + correct G_C
      cross_fit_dr_custom(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic",
        custom_fit_or  = fit_outcome_models_wrong
      )

    } else if (condition == "DR-both-wrong") {
      # Misspecified OR + misspecified G_C
      cross_fit_dr_custom(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic",
        custom_fit_gc  = fit_censoring_model_wrong,
        custom_fit_or  = fit_outcome_models_wrong
      )

    } else if (condition == "OR-only") {
      # Outcome regression only: no IPCW correction
      # G_C = 1 (trivial) and Lambda_k = 0 (no compensator) -> IF correction = 0
      cross_fit_dr_custom(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic",
        oracle_gc = function(u, row) 1.0,
        oracle_Lk = function(tau, k, row) 0.0
      )

    } else if (condition == "IPCW-only") {
      # IPCW only: no outcome regression (M_k = 0)
      cross_fit_dr_custom(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic",
        oracle_Mk = function(lm_data) matrix(0, nrow = nrow(lm_data), ncol = K)
      )

    } else {
      stop("Unknown condition: ", condition)
    }

  }, error = function(e) {
    warning("DR estimation failed rep ", rep_id, ", condition=", condition,
            ": ", e$message)
    NULL
  })

  if (is.null(dr_results)) return(NULL)

  # ---- 4. Evaluate against ground truth ----
  eval_df <- evaluate_one_rep(dr_results, TRUE_MU_DF)
  eval_df$rep       <- rep_id
  eval_df$n         <- n
  eval_df$estimator <- condition
  eval_df$seed      <- seed_val

  eval_df
}


# "all" conditions path
run_all_conditions <- function(rep_id, n) {
  results <- lapply(VALID_CONDITIONS, function(cond) {
    cat(sprintf("  rep=%d cond=%s\n", rep_id, cond))
    run_one_rep(rep_id, n, condition = cond)
  })
  bind_rows(results)
}


# =============================================================================
# MAIN SIMULATION LOOP
# =============================================================================

output_dir <- file.path(script_dir, "results", "block2")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat(sprintf("Starting Block 2 simulation | n=%d | reps %d to %d | condition=%s\n",
            N_SIM, REP_START, REP_START + N_REPS - 1, CONDITION))
cat(sprintf("Output directory: %s\n\n", output_dir))

all_results <- vector("list", N_REPS)

for (i in seq_len(N_REPS)) {
  rep_id <- REP_START + i - 1
  cat(sprintf("[%d/%d] rep=%d n=%d ... ", i, N_REPS, rep_id, N_SIM))
  t0 <- proc.time()

  if (CONDITION == "all") {
    res <- run_all_conditions(rep_id, N_SIM)
  } else {
    res <- run_one_rep(rep_id, N_SIM, condition = CONDITION)
  }

  elapsed <- (proc.time() - t0)[["elapsed"]]
  cat(sprintf("done in %.1fs\n", elapsed))

  all_results[[i]] <- res
}

results_df <- bind_rows(all_results)

# ---- Save results ----
out_file <- file.path(
  output_dir,
  sprintf("block2_cond%s_reps%d-%d.csv",
          gsub("-", "", CONDITION), REP_START, REP_START + N_REPS - 1)
)
write.csv(results_df, file = out_file, row.names = FALSE)
cat(sprintf("\nSaved %d rows to %s\n", nrow(results_df), out_file))

# =============================================================================
# QUICK SUMMARY AND KILL CRITERION CHECK
# =============================================================================

if (nrow(results_df) > 0) {
  cat("\n--- Quick summary (bias, RMSE, coverage by condition) ---\n")
  summary_df <- results_df %>%
    group_by(estimator, history_stratum, k) %>%
    summarise(
      n_reps      = n(),
      bias        = mean(bias, na.rm = TRUE),
      rmse        = sqrt(mean(sq_err, na.rm = TRUE)),
      coverage_95 = mean(cover_95, na.rm = TRUE),
      .groups     = "drop"
    ) %>%
    arrange(estimator, history_stratum, k)

  print(as.data.frame(summary_df), digits = 4)

  # ---- Kill criterion: separation between one-correct and both-wrong ----
  cat("\n--- Kill criterion check: DR double-robustness ---\n")

  # Compute mean absolute bias by condition (averaging over strata and types)
  cond_bias <- summary_df %>%
    group_by(estimator) %>%
    summarise(
      mean_abs_bias = mean(abs(bias), na.rm = TRUE),
      max_abs_bias  = max(abs(bias), na.rm = TRUE),
      mean_coverage = mean(coverage_95, na.rm = TRUE),
      .groups = "drop"
    )

  print(as.data.frame(cond_bias), digits = 4)

  # Extract bias by group
  bias_both_correct <- cond_bias$mean_abs_bias[cond_bias$estimator == "DR-both-correct"]
  bias_g_wrong      <- cond_bias$mean_abs_bias[cond_bias$estimator == "DR-G-wrong"]
  bias_or_wrong     <- cond_bias$mean_abs_bias[cond_bias$estimator == "DR-OR-wrong"]
  bias_both_wrong   <- cond_bias$mean_abs_bias[cond_bias$estimator == "DR-both-wrong"]

  # Check separation: both-wrong should have meaningfully larger bias than
  # one-correct conditions
  if (length(bias_both_wrong) > 0 && length(bias_g_wrong) > 0 && length(bias_or_wrong) > 0) {
    one_correct_max <- max(bias_g_wrong, bias_or_wrong)
    separation      <- bias_both_wrong - one_correct_max

    cat(sprintf("\n  DR-both-correct mean |bias|: %.5f\n", bias_both_correct))
    cat(sprintf("  DR-G-wrong      mean |bias|: %.5f\n", bias_g_wrong))
    cat(sprintf("  DR-OR-wrong     mean |bias|: %.5f\n", bias_or_wrong))
    cat(sprintf("  DR-both-wrong   mean |bias|: %.5f\n", bias_both_wrong))
    cat(sprintf("  Separation (both-wrong - max one-correct): %.5f\n", separation))

    if (separation < 0.005) {
      cat("  WARNING: No meaningful separation between one-correct and both-wrong.\n")
      cat("  Kill criterion triggered. Check DGM or nuisance misspecification severity.\n")
    } else if (one_correct_max > 0.02) {
      cat("  WARNING: One-correct conditions show substantial bias (>0.02).\n")
      cat("  DR property may not hold. Investigate nuisance model fitting.\n")
    } else {
      cat("  PASS: Double-robustness property confirmed.\n")
      cat("  One-correct conditions near-unbiased; both-wrong shows expected bias.\n")
    }
  } else {
    cat("  Insufficient conditions to evaluate kill criterion.\n")
    cat("  Run with BLOCK2_CONDITION=all to get full comparison.\n")
  }
}
