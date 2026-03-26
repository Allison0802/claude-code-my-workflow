# =============================================================================
# evaluation.R
# Evaluation metrics for OLMC simulations
#
# Covers: bias, RMSE, CI coverage, multiclass log loss, calibration error
# Also provides true mu_k(h) computation for Block 1 (simple parametric DGM)
# Last Updated: 2026-03-20
# =============================================================================

library(tidyverse)

# =============================================================================
# TRUE mu_k(h) FOR SIMPLE PARAMETRIC DGM (Block 1 oracle sanity)
# =============================================================================

#' Compute true mu_k(h) under a simple exponential competing-risks DGM
#'
#' Under constant type-k hazard lambda_k(h) and constant death hazard lambda_D(h),
#' with independent exponential censoring at rate r_C (censoring does NOT affect
#' the estimand, only the data), the true value is:
#'
#'   mu_k(h) = integral_0^w lambda_k(h) * exp(-(lambda+(h) + lambda_D(h)) * u) du
#'           = lambda_k(h) / (lambda+(h) + lambda_D(h)) * [1 - exp(-(lambda+(h)+lambda_D(h))*w)]
#'
#' where lambda+(h) = sum_k lambda_k(h).
#'
#' @param lambda_rec_h  length-K vector of type-k hazards conditional on H_s=h
#' @param lambda_D_h    scalar death hazard conditional on H_s=h
#' @param w             prediction window width (years)
#'
#' @return named list: mu (length-K vector), pi (length-K conditional probs), q (scalar)
true_mu_exponential <- function(lambda_rec_h, lambda_D_h, w = 0.5) {
  K        <- length(lambda_rec_h)
  lambda_p <- sum(lambda_rec_h)   # total recurrent hazard
  total_h  <- lambda_p + lambda_D_h

  # mu_k(h) = cause-specific cumulative incidence for type k
  surv_factor <- (1 - exp(-total_h * w)) / total_h
  mu <- lambda_rec_h * surv_factor

  q    <- sum(mu)
  pi_k <- if (q > 1e-6) mu / q else rep(1/K, K)

  list(mu = mu, pi = pi_k, q = q)
}


#' Compute average true mu_k(h) over the stratum distribution
#'
#' In Block 1, subjects in stratum h have covariates drawn from a distribution.
#' The true mu_k(h) averages over this distribution.
#'
#' @param lm_data         landmark dataset with covariates
#' @param stratum         character: "H0", "H1", "H2", "H3"
#' @param K               number of event types
#' @param w               prediction window
#' @param lambda0_rec     length-K vector of baseline recurrent hazards
#' @param lambda0_D       scalar baseline death hazard
#' @param beta_rec        K x p covariate log-HRs (rows = types)
#' @param beta_D          length-p covariate log-HRs for death
#' @param frailty_var     frailty variance (for oracle: use gamma_i if available)
#'
#' @return data.frame: k, mu_true, pi_true, q_true
true_mu_stratum <- function(
  lm_data, stratum, K = 2, w = 0.5,
  lambda0_rec, lambda0_D, beta_rec, beta_D,
  frailty_var = 0, p = 4
) {
  rows_h <- lm_data[lm_data$history_stratum == stratum, ]
  if (nrow(rows_h) == 0) {
    return(data.frame(k = 1:K, mu_true = NA, pi_true = NA, q_true = NA))
  }

  covs <- as.matrix(rows_h[, c("z", "x", "x2", "x3")[1:p], drop = FALSE])
  covs[is.na(covs)] <- 0

  # Use individual frailty if recorded (oracle), else use E[gamma] = exp(sigma^2/2)
  if ("gamma_i" %in% names(rows_h)) {
    gamma_vec <- rows_h$gamma_i
  } else {
    gamma_vec <- rep(exp(frailty_var / 2), nrow(rows_h))
  }

  # Compute per-row true mu
  mu_mat <- matrix(NA_real_, nrow = nrow(rows_h), ncol = K)
  for (i in 1:nrow(rows_h)) {
    gamma_i       <- gamma_vec[i]
    covs_i        <- covs[i, ]
    lambda_rec_i  <- numeric(K)
    for (k in 1:K) {
      lp_k         <- sum(beta_rec[k, ] * covs_i)
      lambda_rec_i[k] <- gamma_i * lambda0_rec[k] * exp(lp_k)
    }
    lp_D        <- sum(beta_D * covs_i)
    lambda_D_i  <- gamma_i * lambda0_D * exp(lp_D)

    res          <- true_mu_exponential(lambda_rec_i, lambda_D_i, w = w)
    mu_mat[i, ] <- res$mu
  }

  # Average over stratum
  mu_true  <- colMeans(mu_mat, na.rm = TRUE)
  q_true   <- sum(mu_true)
  pi_true  <- if (q_true > 1e-6) mu_true / q_true else rep(1/K, K)

  data.frame(
    k        = 1:K,
    mu_true  = mu_true,
    pi_true  = pi_true,
    q_true   = q_true
  )
}


# =============================================================================
# ORACLE NUISANCE FUNCTIONS FOR BLOCK 1
# =============================================================================

#' Oracle G_C function for Block 1 (independent exponential censoring)
#'
#' @param censor_rate  exponential censoring rate
#' @return function(u, row) -> G_C(u | H_si) = exp(-censor_rate * u)
make_oracle_gc_exponential <- function(censor_rate) {
  function(u, row) exp(-censor_rate * u)
}


#' Oracle Lambda_k function for Block 1 (constant hazard, no history effects)
#'
#' @param lambda0_rec  K-vector of baseline recurrent hazards
#' @param lambda0_D    scalar death hazard
#' @param beta_rec     K x p beta matrix
#' @param beta_D       length-p beta vector
#' @param p            number of covariates
#'
#' @return function(tau, k, row) -> Lambda_k(tau | H_si) = lambda_k(H_si) * tau
make_oracle_Lk_exponential <- function(lambda0_rec, lambda0_D, beta_rec, beta_D, p = 4) {
  function(tau, k, row) {
    covs <- unlist(row[c("z", "x", "x2", "x3")[1:p]])
    covs[is.na(covs)] <- 0
    gamma_i <- if ("gamma_i" %in% names(row)) row$gamma_i else 1.0
    lp_k  <- sum(beta_rec[k, ] * covs)
    lambda_k <- gamma_i * lambda0_rec[k] * exp(lp_k)
    lambda_k * tau
  }
}


#' Oracle M_k function for Block 1 (true outcome regression)
#'
#' @param lambda0_rec  K-vector of baseline recurrent hazards
#' @param lambda0_D    scalar death hazard
#' @param beta_rec     K x p beta matrix
#' @param beta_D       length-p beta vector
#' @param w            prediction window
#' @param p            number of covariates
#'
#' @return function(lm_data) -> matrix (n x K) of true M_k(H_si)
make_oracle_Mk_exponential <- function(lambda0_rec, lambda0_D, beta_rec, beta_D, w = 0.5, p = 4) {
  function(lm_data) {
    K       <- length(lambda0_rec)
    n_rows  <- nrow(lm_data)
    M_mat   <- matrix(NA_real_, nrow = n_rows, ncol = K)
    covs_all <- as.matrix(lm_data[, c("z", "x", "x2", "x3")[1:p], drop = FALSE])
    covs_all[is.na(covs_all)] <- 0

    gamma_vec <- if ("gamma_i" %in% names(lm_data)) lm_data$gamma_i else rep(1.0, n_rows)

    for (i in 1:n_rows) {
      covs_i <- covs_all[i, ]
      gamma_i <- gamma_vec[i]
      lambda_rec_i <- numeric(K)
      for (k in 1:K) {
        lp_k <- sum(beta_rec[k, ] * covs_i)
        lambda_rec_i[k] <- gamma_i * lambda0_rec[k] * exp(lp_k)
      }
      lp_D  <- sum(beta_D * covs_i)
      lambda_D_i <- gamma_i * lambda0_D * exp(lp_D)

      res          <- true_mu_exponential(lambda_rec_i, lambda_D_i, w = w)
      M_mat[i, ]   <- res$mu
    }
    M_mat
  }
}


# =============================================================================
# EVALUATION METRICS
# =============================================================================

#' Evaluate one simulation replicate
#'
#' @param dr_results  data.frame from cross_fit_dr() (or normalize_to_pi())
#'                    must have: history_stratum, k, mu_hat, se, ci_lo, ci_hi
#' @param true_mu_df  data.frame with history_stratum, k, mu_true (true values)
#'
#' @return data.frame: history_stratum, k, bias, rmse, cover_95, ci_width,
#'                     mu_hat, mu_true, se
evaluate_one_rep <- function(dr_results, true_mu_df) {

  merged <- merge(
    dr_results,
    true_mu_df,
    by = c("history_stratum", "k"),
    all.x = TRUE
  )

  merged$bias     <- merged$mu_hat - merged$mu_true
  merged$sq_err   <- merged$bias^2
  merged$cover_95 <- as.integer(
    !is.na(merged$ci_lo) & !is.na(merged$ci_hi) &
    merged$ci_lo <= merged$mu_true &
    merged$ci_hi >= merged$mu_true
  )
  merged$ci_width <- merged$ci_hi - merged$ci_lo

  merged[, c("history_stratum", "k", "mu_hat", "mu_true", "se",
             "bias", "sq_err", "cover_95", "ci_width",
             "n_rows", "n_subjects")]
}


#' Aggregate results over Monte Carlo replicates
#'
#' @param rep_results  list of data.frames from evaluate_one_rep(), one per rep
#'
#' @return data.frame: history_stratum, k, bias_mc, rmse, coverage_95, avg_ci_width,
#'                     avg_se, n_reps, eif_variance_ratio (EIF SE^2 / MC variance)
aggregate_mc_results <- function(rep_results) {

  all_reps <- bind_rows(rep_results, .id = "rep")

  summary_df <- all_reps %>%
    group_by(history_stratum, k) %>%
    summarise(
      n_reps          = n(),
      mu_true         = mean(mu_true, na.rm = TRUE),
      mu_hat_mean     = mean(mu_hat, na.rm = TRUE),
      bias_mc         = mean(bias, na.rm = TRUE),
      rmse            = sqrt(mean(sq_err, na.rm = TRUE)),
      coverage_95     = mean(cover_95, na.rm = TRUE),
      avg_ci_width    = mean(ci_width, na.rm = TRUE),
      avg_se          = mean(se, na.rm = TRUE),
      mc_sd           = sd(mu_hat, na.rm = TRUE),
      # EIF variance ratio: avg SE^2 / MC variance (should be ~1 if EIF correct)
      eif_variance_ratio = mean(se^2, na.rm = TRUE) / var(mu_hat, na.rm = TRUE),
      .groups = "drop"
    )

  summary_df
}


#' Multiclass log loss for conditional type classifier pi_k(h)
#'
#' Evaluates how well the estimated pi_k(h) predicts the observed type J_s.
#' Only evaluated for landmark rows where delta_N = 1 (event observed in window).
#'
#' @param lm_data     landmark dataset with delta_N = 1 rows
#' @param pi_estimates data.frame with history_stratum, k, pi_hat
#' @param K           number of event types
#'
#' @return scalar: mean log loss
compute_log_loss <- function(lm_data, pi_estimates, K = 3) {

  # Only rows with observed event
  obs_rows <- lm_data[lm_data$delta_N == 1, ]
  if (nrow(obs_rows) == 0) return(NA_real_)

  log_losses <- numeric(nrow(obs_rows))

  for (i in 1:nrow(obs_rows)) {
    h       <- as.character(obs_rows$history_stratum[i])
    k_obs   <- obs_rows$J_s[i]
    if (is.na(k_obs)) { log_losses[i] <- NA; next }

    pi_h <- pi_estimates[pi_estimates$history_stratum == h, ]
    pi_k_hat <- pi_h$pi_hat[pi_h$k == k_obs]
    if (length(pi_k_hat) == 0 || is.na(pi_k_hat)) { log_losses[i] <- NA; next }
    pi_k_hat <- pmax(pmin(pi_k_hat, 1 - 1e-6), 1e-6)
    log_losses[i] <- -log(pi_k_hat)
  }

  mean(log_losses, na.rm = TRUE)
}


#' Calibration error for pi_k(h)
#'
#' Compares estimated pi_k(h) against empirical proportion of type-k events
#' within each stratum, for subjects with delta_N = 1.
#'
#' @param lm_data     landmark dataset
#' @param pi_results  data.frame from normalize_to_pi() with pi_hat
#' @param K           number of event types
#'
#' @return data.frame: history_stratum, k, pi_hat, pi_empirical, calibration_error
compute_calibration <- function(lm_data, pi_results, K = 3) {

  strata <- levels(lm_data$history_stratum)
  out_list <- vector("list", length(strata) * K)
  idx <- 0L

  for (h in strata) {
    rows_h <- lm_data[lm_data$history_stratum == h & lm_data$delta_N == 1, ]
    n_h    <- nrow(rows_h)

    for (k in 1:K) {
      idx <- idx + 1L
      pi_row <- pi_results[pi_results$history_stratum == h & pi_results$k == k, ]
      pi_hat <- if (nrow(pi_row) > 0) pi_row$pi_hat[1] else NA

      pi_emp <- if (n_h > 0) mean(rows_h$J_s == k, na.rm = TRUE) else NA

      out_list[[idx]] <- data.frame(
        history_stratum    = h,
        k                  = k,
        pi_hat             = pi_hat,
        pi_empirical       = pi_emp,
        calibration_error  = abs(pi_hat - pi_emp),
        n_events_in_stratum = n_h
      )
    }
  }

  bind_rows(out_list)
}
