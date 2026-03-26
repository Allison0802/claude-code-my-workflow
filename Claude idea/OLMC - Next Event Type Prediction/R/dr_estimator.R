# =============================================================================
# dr_estimator.R
# Doubly robust estimator for mu_k(h) via efficient influence function (EIF)
#
# Estimand:  mu_k(h) = P(T_s^N <= w, J_s = k, T_s^N < T_s^D | H_s = h)
# EIF form:  phi_{mu_k,h}(O) = a_h(H_s) * [
#              M_k(H_s) + int_0^w G_C(u-|H_s)^{-1} {dN_k(u) - Y(u) dLambda_k(u|H_s)}
#            ]
# Estimator: mu_hat_k(h) = mean_{i: H_si in h}[ M_k(H_si) + IF_correction_k(i) ]
#
# Cross-fitting: 5-fold split by subject (not by landmark row)
# Variance: subject-clustered influence function SE
# Last Updated: 2026-03-20
# =============================================================================

library(tidyverse)
library(survival)

# =============================================================================
# NUISANCE MODEL FITTING
# =============================================================================

#' Fit Cox censoring model to estimate G_C(u | H_s)
#'
#' The censoring indicator is 1 when the subject is censored (not event/death).
#' Treats recurrent events and deaths as censoring of the censoring process.
#'
#' @param lm_data   landmark dataset (training fold)
#' @param K         number of event types
#' @param formula_rhs  right-hand side formula string for Cox (default: all features)
#'
#' @return list with $cox_fit (coxph object) and $basehaz (data.frame of baseline hazard)
fit_censoring_model <- function(lm_data, K = 3, formula_rhs = NULL) {

  # Censoring model: outcome is residual censoring time from landmark s.
  # C_obs = min(T_sN, T_sD, C_si, w) = tau_i (what we actually observe first).
  # C_event = 1 iff the subject was censored (not an event, not a death).
  # Death and recurrent events are competing events for the censoring process.
  lm_data$C_obs   <- lm_data$tau_i
  died_in_window  <- is.finite(lm_data$T_sD) & lm_data$T_sD <= lm_data$tau_i
  lm_data$C_event <- as.integer(lm_data$delta_N == 0 & !died_in_window)

  X <- get_nuisance_covariates(lm_data, K = K, include_landmark_time = TRUE)
  X[is.na(X)] <- 0

  # Build Cox formula from column names
  xnames <- colnames(X)
  rhs    <- if (is.null(formula_rhs)) paste(xnames, collapse = " + ") else formula_rhs

  surv_formula <- as.formula(paste("Surv(C_obs, C_event) ~", rhs))
  df_for_cox   <- as.data.frame(X)
  df_for_cox$C_obs   <- lm_data$C_obs
  df_for_cox$C_event <- lm_data$C_event

  cox_fit <- tryCatch(
    coxph(surv_formula, data = df_for_cox, ties = "breslow"),
    error = function(e) {
      # Fallback: intercept-only (KM)
      coxph(Surv(C_obs, C_event) ~ 1, data = df_for_cox, ties = "breslow")
    }
  )

  bh <- basehaz(cox_fit, centered = FALSE)

  list(cox_fit = cox_fit, basehaz = bh, X_names = xnames)
}


#' Evaluate G_C(t | H_si) from a fitted censoring model
#'
#' @param cox_fit_list   output of fit_censoring_model()
#' @param X_new          matrix of covariates for new observations (n_test x p)
#' @param times          numeric vector of times at which to evaluate G_C
#'
#' @return matrix (n_test x length(times)) of G_C values
evaluate_gc <- function(cox_fit_list, X_new, times) {

  cox_fit <- cox_fit_list$cox_fit
  bh      <- cox_fit_list$basehaz

  # Linear predictor for new observations
  coef_vals <- coef(cox_fit)
  coef_vals[is.na(coef_vals)] <- 0
  X_new[is.na(X_new)] <- 0

  # Match columns
  xnames <- names(coef_vals)
  X_new_matched <- matrix(0, nrow = nrow(X_new), ncol = length(xnames))
  colnames(X_new_matched) <- xnames
  common <- intersect(colnames(X_new), xnames)
  X_new_matched[, common] <- X_new[, common]

  lp <- as.numeric(X_new_matched %*% coef_vals)

  # Baseline cumulative hazard at each time
  H0 <- stepfun(bh$time, c(0, bh$hazard))

  n_new <- nrow(X_new_matched)
  n_t   <- length(times)
  gc_mat <- matrix(NA_real_, nrow = n_new, ncol = n_t)

  for (j in seq_along(times)) {
    H0_t <- H0(times[j])
    # G_C(t | H_si) = exp(-H0(t) * exp(lp_i))
    gc_mat[, j] <- exp(-H0_t * exp(lp))
    gc_mat[, j] <- pmax(gc_mat[, j], 0.05)  # truncate for stability
  }

  gc_mat
}


#' Fit outcome regression M_k(H_s) = P(T_sN <= w, J_s=k, T_sN < T_sD | H_s)
#'
#' Uses logistic regression (correct-parametric setting) or can be swapped
#' for ranger/xgboost in flexible nuisance version.
#'
#' @param lm_data  training landmark dataset
#' @param K        number of event types
#' @param method   "logistic" (default, parametric) or "ranger"
#'
#' @return list of K fitted models, one per type
fit_outcome_models <- function(lm_data, K = 3, method = "logistic") {

  X    <- get_nuisance_covariates(lm_data, K = K, include_landmark_time = TRUE)
  X[is.na(X)] <- 0

  models <- vector("list", K)

  for (k in 1:K) {
    y_k <- lm_data[[paste0("delta_N", k)]]  # binary outcome for type k

    if (method == "logistic") {
      df_fit  <- as.data.frame(X)
      df_fit$y <- y_k
      xnames   <- colnames(X)
      rhs      <- paste(xnames, collapse = " + ")
      fmla     <- as.formula(paste("y ~", rhs))

      mod <- tryCatch(
        glm(fmla, data = df_fit, family = binomial()),
        error = function(e) {
          glm(y ~ 1, data = df_fit, family = binomial())
        }
      )
      models[[k]] <- list(model = mod, method = "logistic", X_names = xnames)

    } else if (method == "ranger") {
      requireNamespace("ranger", quietly = TRUE)
      df_fit  <- as.data.frame(X)
      df_fit$y <- factor(y_k)
      mod <- ranger::ranger(
        y ~ ., data = df_fit,
        num.trees = 500, probability = TRUE, min.node.size = 10
      )
      models[[k]] <- list(model = mod, method = "ranger", X_names = colnames(X))
    }
  }

  models
}


#' Predict M_k(H_si) for new observations
#'
#' @param outcome_models  list output from fit_outcome_models()
#' @param X_new           matrix of covariates for new observations
#' @param K               number of event types
#'
#' @return matrix (n_new x K) of predicted probabilities
predict_outcome <- function(outcome_models, X_new, K = 3) {

  n_new  <- nrow(X_new)
  M_pred <- matrix(NA_real_, nrow = n_new, ncol = K)

  for (k in 1:K) {
    obj    <- outcome_models[[k]]
    method <- obj$method

    # Align columns
    X_new[is.na(X_new)] <- 0
    xnames <- obj$X_names
    X_aligned <- matrix(0, nrow = n_new, ncol = length(xnames))
    colnames(X_aligned) <- xnames
    common <- intersect(colnames(X_new), xnames)
    X_aligned[, common] <- X_new[, common]

    if (method == "logistic") {
      df_pred <- as.data.frame(X_aligned)
      M_pred[, k] <- predict(obj$model, newdata = df_pred, type = "response")

    } else if (method == "ranger") {
      df_pred <- as.data.frame(X_aligned)
      preds   <- predict(obj$model, data = df_pred)$predictions
      # Column "1" = probability of delta_Nk = 1
      M_pred[, k] <- preds[, "1"]
    }

    # Truncate to [0, 1]
    M_pred[, k] <- pmax(pmin(M_pred[, k], 1 - 1e-6), 1e-6)
  }

  M_pred
}


#' Fit cause-specific Cox model for Lambda_k(u | H_s)
#'
#' Used to compute the predictable compensator term in the EIF.
#'
#' @param lm_data  training landmark dataset
#' @param K        number of event types
#'
#' @return list of K Cox objects with baseline hazard
fit_type_hazard_models <- function(lm_data, K = 3) {

  X <- get_nuisance_covariates(lm_data, K = K, include_landmark_time = TRUE)
  X[is.na(X)] <- 0
  xnames <- colnames(X)
  rhs    <- paste(xnames, collapse = " + ")

  models <- vector("list", K)

  for (k in 1:K) {
    # Status: did type-k event occur as the first event in window?
    y_k  <- lm_data[[paste0("delta_N", k)]]
    t_k  <- pmin(lm_data$T_sN, lm_data$w_val)  # time in window (capped)

    df_fit        <- as.data.frame(X)
    df_fit$t_k    <- t_k
    df_fit$status <- y_k
    fmla          <- as.formula(paste("Surv(t_k, status) ~", rhs))

    cox_k <- tryCatch(
      coxph(fmla, data = df_fit, ties = "breslow"),
      error = function(e) {
        coxph(Surv(t_k, status) ~ 1, data = df_fit, ties = "breslow")
      }
    )

    bh_k <- basehaz(cox_k, centered = FALSE)
    models[[k]] <- list(cox_fit = cox_k, basehaz = bh_k, X_names = xnames)
  }

  models
}


# =============================================================================
# EIF COMPUTATION
# =============================================================================

#' Compute IF correction for each observation (one landmark row)
#'
#' IF_correction_k(i) = int_0^{tau_i} G_C(u|H_si)^{-1} {dN_k(u) - Y(u) dLambda_k(u|H_si)}
#'
#' Discretized as:
#'   = delta_Nk_i / G_C(T_sN_i - | H_si)
#'     - sum_{u in grid up to tau_i} G_C(u|H_si)^{-1} * dLambda_k(u|H_si)
#'
#' @param lm_test        test fold landmark dataset
#' @param gc_model       fitted censoring model
#' @param lambda_models  list of K fitted cause-specific hazard models
#' @param K              number of event types
#' @param w              prediction window width
#' @param n_grid         number of integration grid points (default 50)
#'
#' @return matrix (n_test x K) of IF correction values
compute_if_corrections <- function(
  lm_test, gc_model, lambda_models, K = 3, w = 0.5, n_grid = 50
) {

  n_test <- nrow(lm_test)
  IF_mat <- matrix(0.0, nrow = n_test, ncol = K)

  X_test <- get_nuisance_covariates(lm_test, K = K, include_landmark_time = TRUE)
  X_test[is.na(X_test)] <- 0

  # Integration grid (equally spaced in [0, w])
  u_grid   <- seq(0, w, length.out = n_grid + 1)[-1]  # exclude 0
  du       <- w / n_grid

  # Evaluate G_C at grid points for all test observations (n_test x n_grid)
  gc_grid  <- evaluate_gc(gc_model, X_test, u_grid)  # n_test x n_grid

  for (k in 1:K) {
    delta_Nk <- lm_test[[paste0("delta_N", k)]]
    T_sN     <- lm_test$T_sN
    tau_i    <- lm_test$tau_i

    # IPCW term: delta_Nk / G_C(T_sN - | H_si)
    gc_at_TsN <- numeric(n_test)
    for (i in 1:n_test) {
      gc_at_TsN[i] <- evaluate_gc(
        gc_model, X_test[i, , drop = FALSE], max(T_sN[i] - 1e-6, 0)
      )[1, 1]
    }
    ipcw_term <- ifelse(delta_Nk == 1, 1 / pmax(gc_at_TsN, 0.05), 0)

    # Compensator integral: sum_u I(u <= tau_i) * dLambda_k(u|H_si) / G_C(u|H_si)
    # dLambda_k(u|H_si) from Cox model: lambda_k0(u) * exp(beta_k^T H_si) * du
    lambda_obj <- lambda_models[[k]]
    cox_k      <- lambda_obj$cox_fit
    bh_k       <- lambda_obj$basehaz

    # Linear predictor for test set from type-k model
    coef_k <- coef(cox_k)
    coef_k[is.na(coef_k)] <- 0
    xnames_k <- names(coef_k)
    X_aligned <- matrix(0, nrow = n_test, ncol = length(xnames_k))
    colnames(X_aligned) <- xnames_k
    common <- intersect(colnames(X_test), xnames_k)
    X_aligned[, common] <- X_test[, common]
    lp_k <- as.numeric(X_aligned %*% coef_k)

    # Baseline hazard function (step function)
    H0k_fun <- stepfun(bh_k$time, c(0, bh_k$hazard))
    # Increments at grid points
    h0k_grid <- diff(c(0, H0k_fun(u_grid)))  # dLambda_k0 at each grid point

    # For each subject, compute integral up to tau_i
    comp_integral <- numeric(n_test)
    for (i in 1:n_test) {
      in_window <- u_grid <= tau_i[i]
      dL_k      <- h0k_grid[in_window] * exp(lp_k[i])  # dLambda_k(u|H_si)
      gc_vals   <- gc_grid[i, in_window]                 # G_C(u|H_si)
      comp_integral[i] <- sum(dL_k / pmax(gc_vals, 0.05))
    }

    IF_mat[, k] <- ipcw_term - comp_integral
  }

  IF_mat
}


# =============================================================================
# DR ESTIMATOR WITH CROSS-FITTING
# =============================================================================

#' Cross-fitted DR estimator for mu_k(h), k=1..K, h in {H0,H1,H2,H3}
#'
#' Splits subjects into V folds, fits nuisance models on training folds,
#' applies to test fold, aggregates EIF scores, estimates mu_k(h) and SE.
#'
#' @param lm_data       full landmark dataset from build_landmark_dataset()
#' @param K             number of event types
#' @param w             prediction window
#' @param V             number of cross-fitting folds (default 5)
#' @param outcome_method "logistic" or "ranger" for outcome regression M_k
#' @param oracle_gc     if not NULL, function(lm_row) -> G_C value (oracle)
#' @param oracle_Mk     if not NULL, function(lm_data) -> matrix (n x K) of M_k (oracle)
#' @param oracle_Lk     if not NULL, function(lm_row, k) -> Lambda_k cumulative hazard
#'
#' @return data.frame with columns:
#'   history_stratum, k, mu_hat, se, ci_lo, ci_hi, n_stratum
cross_fit_dr <- function(
  lm_data,
  K              = 3,
  w              = 0.5,
  V              = 5,
  outcome_method = "logistic",
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

  # Storage for EIF scores: one score per (landmark row, type)
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
      M_pred <- oracle_Mk(lm_test)  # n_test x K
    } else {
      om <- fit_outcome_models(lm_train, K = K, method = outcome_method)
      M_pred <- predict_outcome(om, X_test, K = K)
    }

    # ---- Censoring model G_C ----
    if (!is.null(oracle_gc)) {
      gc_model_v <- NULL
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
      # Oracle path: compute IF directly using known nuisances
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

      # Subject-clustered SE
      #   For each subject, sum scores across their landmark rows in stratum h
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


#' Oracle IF correction using known nuisance functions
#'
#' For Block 1 verification: uses true G_C and Lambda_k.
#'
#' @param lm_test    test landmark dataset
#' @param oracle_gc  function(times, H_si_row) -> G_C(times | H_si)
#'                   or NULL to use parametric formula
#' @param oracle_Lk  function(tau, k, H_si_row) -> Lambda_k(tau | H_si)
#'                   or NULL
#' @param K          number of event types
#' @param w          prediction window
#'
#' @return matrix (n_test x K) of IF correction values
compute_if_oracle <- function(lm_test, oracle_gc, oracle_Lk, K = 3, w = 0.5,
                               n_grid = 50) {

  n_test  <- nrow(lm_test)
  IF_mat  <- matrix(0.0, nrow = n_test, ncol = K)
  u_grid  <- seq(0, w, length.out = n_grid + 1)[-1]

  for (i in 1:n_test) {
    row_i  <- lm_test[i, ]
    tau_i  <- row_i$tau_i

    gc_vals <- sapply(u_grid, function(u) oracle_gc(u, row_i))
    gc_vals <- pmax(gc_vals, 0.05)

    gc_at_TsN <- oracle_gc(max(row_i$T_sN - 1e-6, 0), row_i)
    gc_at_TsN <- max(gc_at_TsN, 0.05)

    for (k in 1:K) {
      delta_Nk <- row_i[[paste0("delta_N", k)]]

      # IPCW term
      ipcw_term <- if (delta_Nk == 1) 1 / gc_at_TsN else 0

      # Compensator integral
      in_window    <- u_grid <= tau_i
      dL_k         <- diff(c(0, sapply(u_grid, function(u) oracle_Lk(u, k, row_i))))
      dL_k_window  <- dL_k[in_window]
      gc_window    <- gc_vals[in_window]
      comp_integral <- sum(dL_k_window / gc_window)

      IF_mat[i, k] <- ipcw_term - comp_integral
    }
  }

  IF_mat
}


# =============================================================================
# NORMALIZATION TO CONDITIONAL TYPE CLASSIFIER
# =============================================================================

#' Normalize mu_hat_k(h) to pi_k(h) = mu_k(h) / q(h)
#'
#' Reports pi_k(h) only where estimated q(h) = sum_k mu_hat_k(h) >= threshold.
#'
#' @param dr_results  data.frame from cross_fit_dr() with mu_hat by k and stratum
#' @param q_threshold minimum q(h) for reporting pi_k(h) (default 0.10)
#'
#' @return data.frame with additional columns: q_hat, pi_hat, pi_se, reportable
normalize_to_pi <- function(dr_results, q_threshold = 0.10) {

  strata <- unique(dr_results$history_stratum)
  out_list <- vector("list", length(strata))

  for (h in strata) {
    rows_h  <- dr_results[dr_results$history_stratum == h, ]
    K_h     <- nrow(rows_h)
    q_hat   <- sum(rows_h$mu_hat, na.rm = TRUE)
    q_hat   <- max(q_hat, 1e-6)

    # SE for pi_k using delta method: SE(pi_k) = SE(mu_k) / q_hat
    # (approximate; ignores covariance between mu_k estimates)
    rows_h$q_hat      <- q_hat
    rows_h$pi_hat     <- rows_h$mu_hat / q_hat
    rows_h$pi_hat     <- pmax(pmin(rows_h$pi_hat, 1), 0)
    rows_h$pi_se      <- rows_h$se / q_hat
    rows_h$reportable <- (q_hat >= q_threshold)

    out_list[[which(strata == h)]] <- rows_h
  }

  bind_rows(out_list)
}
