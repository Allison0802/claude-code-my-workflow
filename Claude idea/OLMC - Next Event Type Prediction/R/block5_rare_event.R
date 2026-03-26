# =============================================================================
# block5_rare_event.R
# Block 5: When is pi_k(h) stable enough to report?
#
# Scientific question: When is pi_k(h) stable enough to report?
#
# DGM:
#   - K = 3, n = 2000
#   - Vary prediction window w to make q(h) = sum_k mu_k(h) ~ {0.05, 0.10, 0.15, 0.20}
#   - w values: c(0.08, 0.17, 0.25, 0.50) years (~1, 2, 3, 6 months)
#   - Censoring 20-25%, death 20%
#   - Frailty sigma^2 = 0.5
#   - history_on_rec = TRUE, history_on_D = FALSE (moderate complexity)
#   - Censor_type = "independent", censor_param = 0.20
#
# Estimators:
#   1. DR mu-then-normalize (main proposed approach)
#   2. DR with truncation at q(h) thresholds: {0.05, 0.10, 0.15}
#   3. Direct conditional: multinomial logistic on observed events only
#
# Primary metrics:
#   - RMSE and CI coverage for pi_k(h) as function of true q(h)
#   - Threshold identification: minimum q(h) where coverage >= 0.90
#
# Expected finding: mu-first estimation stable down to q(h) ~ 0.10;
#   direct conditional estimation degrades earlier (~0.15).
#
# Kill criterion: Instability persists even at q(h) >= 0.15.
#
# Output: results/block5/block5_w{W}_reps{START}-{END}.csv
#
# Usage (SLURM):
#   Rscript block5_rare_event.R
#   or via env vars: BLOCK5_REP_START, BLOCK5_N_REPS, BLOCK5_W
#
# Last Updated: 2026-03-21
# =============================================================================

set.seed(20260321)

suppressPackageStartupMessages({
  library(tidyverse)
  library(survival)
  library(here)
  library(nnet)
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
  if (length(idx) > 0 && idx < length(args)) args[idx + 1] else default
}

REP_START <- as.integer(Sys.getenv("BLOCK5_REP_START", unset = parse_arg(args, "--rep_start", "1")))
N_REPS    <- as.integer(Sys.getenv("BLOCK5_N_REPS",    unset = parse_arg(args, "--n_reps", "200")))
W_ENV     <- Sys.getenv("BLOCK5_W", unset = parse_arg(args, "--w", "all"))

# Parse which w values to run
ALL_W_VALUES <- c(0.08, 0.17, 0.25, 0.50)
if (W_ENV == "all") {
  W_VALUES <- ALL_W_VALUES
} else {
  W_VALUES <- as.numeric(W_ENV)
  stopifnot(!is.na(W_VALUES), W_VALUES > 0)
}

cat(sprintf(
  "Block 5 Rare Event | n=2000 | w=%s | reps=%d-%d\n",
  paste(W_VALUES, collapse = ","), REP_START, REP_START + N_REPS - 1
))

# =============================================================================
# DGM PARAMETERS (Block 5: K=3, moderate complexity, varying w)
# =============================================================================

K           <- 3
N_SIM       <- 2000
LANDMARKS   <- seq(0.5, 3.0, by = 0.5)
FRAILTY_VAR <- 0.5
P           <- 4

LAMBDA0_REC <- c(0.30, 0.25, 0.20)   # baseline recurrent hazards (per year)
LAMBDA0_D   <- 0.08                    # baseline death hazard (~20% by 3yr)
CENSOR_RATE <- 0.20                    # exponential censoring rate (20-25%)

# Covariate log-HRs
BETA_REC <- matrix(c(
   0.50, -0.30,  0.20, -0.20,   # type 1
  -0.30,  0.40, -0.10,  0.30,   # type 2
   0.20, -0.20,  0.40, -0.10    # type 3
), nrow = K, ncol = P, byrow = TRUE)

BETA_D <- c(0.30, -0.20, 0.10, 0.00)

# History effects (moderate complexity: history_on_rec = TRUE, history_on_D = FALSE)
HISTORY_EFFECTS <- list(
  count_effect   =  0.10,
  gap_effect     = -0.05,
  last_type_same =  0.20
)

# Truncation thresholds for DR-truncated estimator
Q_THRESHOLDS <- c(0.05, 0.10, 0.15)

# Number of bootstrap replicates for direct conditional SE
N_BOOT <- 100

# =============================================================================
# GROUND TRUTH VIA LARGE MONTE CARLO (per w)
# =============================================================================

#' Compute ground truth pi_k(h) for a given w via large Monte Carlo
#'
#' Generates n_mc subjects with no censoring (very long follow-up),
#' builds landmark data, and computes empirical mu_k(h) and pi_k(h).
#'
#' @param w       prediction window
#' @param n_mc    Monte Carlo sample size (default 50000)
#' @param seed    seed for reproducibility
#'
#' @return data.frame: history_stratum, k, mu_true, pi_true, q_true
compute_ground_truth <- function(w, n_mc = 50000, seed = 20260321) {

  set.seed(seed + round(w * 1000))
  cat(sprintf("  Computing ground truth for w=%.2f (n_mc=%d)...\n", w, n_mc))

  # Generate data with no censoring (very large censor_param -> near-zero censoring rate)
  mc_data <- generate_olmc_data(
    n            = n_mc,
    K            = K,
    lambda0_rec  = LAMBDA0_REC,
    lambda0_D    = LAMBDA0_D,
    frailty_var  = FRAILTY_VAR,
    beta_rec     = BETA_REC,
    beta_D       = BETA_D,
    censor_type  = "independent",
    censor_param = 1e-6,             # near-zero censoring
    max_follow   = 10.0,             # long follow-up
    history_on_rec = TRUE,
    history_on_D   = FALSE,
    history_effects = HISTORY_EFFECTS
  )

  # Build landmark dataset with this w
  mc_lm <- build_landmark_dataset(mc_data, landmarks = LANDMARKS, w = w, K = K)

  # Compute empirical mu_k(h) and pi_k(h) by stratum
  strata <- levels(mc_lm$history_stratum)
  truth_list <- vector("list", length(strata))

  for (h in strata) {
    rows_h <- mc_lm[mc_lm$history_stratum == h, ]
    n_h    <- nrow(rows_h)

    if (n_h < 10) {
      truth_list[[which(strata == h)]] <- data.frame(
        history_stratum = h, k = 1:K,
        mu_true = NA_real_, pi_true = NA_real_, q_true = NA_real_,
        n_mc_stratum = n_h
      )
      next
    }

    mu_k <- numeric(K)
    for (k in 1:K) {
      mu_k[k] <- mean(rows_h[[paste0("delta_N", k)]], na.rm = TRUE)
    }
    q_h  <- sum(mu_k)
    pi_k <- if (q_h > 1e-6) mu_k / q_h else rep(1/K, K)

    truth_list[[which(strata == h)]] <- data.frame(
      history_stratum = h,
      k        = 1:K,
      mu_true  = mu_k,
      pi_true  = pi_k,
      q_true   = q_h,
      n_mc_stratum = n_h
    )
  }

  bind_rows(truth_list)
}


# =============================================================================
# DIRECT CONDITIONAL ESTIMATOR
# =============================================================================

#' Direct conditional estimator: multinomial logistic on observed events only
#'
#' Estimates P(J_s = k | event occurred, H_s = h) directly by fitting
#' nnet::multinom on the subset of landmark rows where delta_N == 1.
#'
#' @param lm_data   full landmark dataset
#' @param K         number of event types
#' @param n_boot    number of bootstrap replicates for SE
#'
#' @return data.frame: history_stratum, k, pi_hat, pi_se, pi_ci_lo, pi_ci_hi
fit_direct_conditional <- function(lm_data, K = 3, n_boot = 100) {

  # Subset to rows with observed event
  evt_data <- lm_data[lm_data$delta_N == 1, ]

  if (nrow(evt_data) < 20) {
    strata <- levels(lm_data$history_stratum)
    return(data.frame(
      history_stratum = rep(strata, each = K),
      k        = rep(1:K, length(strata)),
      pi_hat   = NA_real_,
      pi_se    = NA_real_,
      pi_ci_lo = NA_real_,
      pi_ci_hi = NA_real_
    ))
  }

  # Prepare covariates
  X <- get_nuisance_covariates(evt_data, K = K, include_landmark_time = TRUE)
  X[is.na(X)] <- 0
  df_fit <- as.data.frame(X)
  df_fit$J_s <- factor(evt_data$J_s, levels = 1:K)
  df_fit$history_stratum <- evt_data$history_stratum

  # Fit multinomial logistic regression
  xnames <- colnames(X)
  rhs    <- paste(xnames, collapse = " + ")
  fmla   <- as.formula(paste("J_s ~", rhs))

  multinom_fit <- tryCatch(
    nnet::multinom(fmla, data = df_fit, trace = FALSE, maxit = 300),
    error = function(e) {
      # Fallback: intercept-only
      tryCatch(
        nnet::multinom(J_s ~ 1, data = df_fit, trace = FALSE, maxit = 300),
        error = function(e2) NULL
      )
    }
  )

  if (is.null(multinom_fit)) {
    strata <- levels(lm_data$history_stratum)
    return(data.frame(
      history_stratum = rep(strata, each = K),
      k        = rep(1:K, length(strata)),
      pi_hat   = NA_real_,
      pi_se    = NA_real_,
      pi_ci_lo = NA_real_,
      pi_ci_hi = NA_real_
    ))
  }

  # Predict pi_k(h) by stratum: average predicted probabilities within each stratum
  strata <- levels(lm_data$history_stratum)
  point_estimates <- compute_direct_pi_by_stratum(multinom_fit, lm_data, K, xnames)

  # Bootstrap SE
  boot_mat <- matrix(NA_real_, nrow = n_boot, ncol = length(strata) * K)

  for (b in 1:n_boot) {
    # Resample subjects (clustered bootstrap)
    pids_evt   <- unique(evt_data$pid)
    boot_pids  <- sample(pids_evt, length(pids_evt), replace = TRUE)
    boot_idx   <- unlist(lapply(boot_pids, function(p) which(evt_data$pid == p)))
    boot_data  <- evt_data[boot_idx, ]

    X_b   <- get_nuisance_covariates(boot_data, K = K, include_landmark_time = TRUE)
    X_b[is.na(X_b)] <- 0
    df_b  <- as.data.frame(X_b)
    df_b$J_s <- factor(boot_data$J_s, levels = 1:K)
    df_b$history_stratum <- boot_data$history_stratum

    fit_b <- tryCatch(
      nnet::multinom(fmla, data = df_b, trace = FALSE, maxit = 300),
      error = function(e) NULL
    )

    if (is.null(fit_b)) next

    pi_b <- compute_direct_pi_by_stratum(fit_b, lm_data, K, xnames)
    boot_mat[b, ] <- pi_b$pi_hat
  }

  # Compute bootstrap SE
  boot_se <- apply(boot_mat, 2, sd, na.rm = TRUE)
  boot_se[is.nan(boot_se)] <- NA_real_

  point_estimates$pi_se    <- boot_se
  point_estimates$pi_ci_lo <- point_estimates$pi_hat - 1.96 * boot_se
  point_estimates$pi_ci_hi <- point_estimates$pi_hat + 1.96 * boot_se

  point_estimates
}


#' Compute stratum-level pi_k from a fitted multinom model
#'
#' @param fit       fitted nnet::multinom object
#' @param lm_data   full landmark dataset (to get stratum membership)
#' @param K         number of event types
#' @param xnames    covariate names used in the model
#'
#' @return data.frame: history_stratum, k, pi_hat
compute_direct_pi_by_stratum <- function(fit, lm_data, K, xnames) {

  strata <- levels(lm_data$history_stratum)
  out_list <- vector("list", length(strata))

  # Predict on all landmark rows (not just event rows)
  X_all <- get_nuisance_covariates(lm_data, K = K, include_landmark_time = TRUE)
  X_all[is.na(X_all)] <- 0
  df_pred <- as.data.frame(X_all)

  # Align columns to model
  pred_probs <- tryCatch(
    predict(fit, newdata = df_pred, type = "probs"),
    error = function(e) NULL
  )

  if (is.null(pred_probs)) {
    return(data.frame(
      history_stratum = rep(strata, each = K),
      k      = rep(1:K, length(strata)),
      pi_hat = NA_real_
    ))
  }

  # Ensure pred_probs is a matrix (K=2 case returns vector for binary)
  if (is.null(dim(pred_probs))) {
    pred_probs <- cbind(1 - pred_probs, pred_probs)
  }
  # Ensure K columns
  if (ncol(pred_probs) < K) {
    # Pad missing columns with 0
    missing_cols <- K - ncol(pred_probs)
    pred_probs <- cbind(pred_probs, matrix(0, nrow = nrow(pred_probs), ncol = missing_cols))
  }

  for (h_idx in seq_along(strata)) {
    h      <- strata[h_idx]
    h_rows <- lm_data$history_stratum == h & !is.na(lm_data$history_stratum)

    if (sum(h_rows) == 0) {
      out_list[[h_idx]] <- data.frame(
        history_stratum = h, k = 1:K, pi_hat = NA_real_
      )
      next
    }

    # Average predicted probabilities within stratum
    pi_k <- colMeans(pred_probs[h_rows, 1:K, drop = FALSE], na.rm = TRUE)
    # Renormalize to sum to 1
    pi_k <- pi_k / sum(pi_k)

    out_list[[h_idx]] <- data.frame(
      history_stratum = h, k = 1:K, pi_hat = pi_k
    )
  }

  bind_rows(out_list)
}


# =============================================================================
# EVALUATION HELPERS FOR pi_k(h)
# =============================================================================

#' Evaluate pi_k(h) estimates against ground truth
#'
#' @param pi_results  data.frame with history_stratum, k, pi_hat, pi_se (or pi_ci_lo/hi)
#' @param truth_df    data.frame with history_stratum, k, pi_true, q_true
#' @param estimator   character label for the estimator
#' @param w           prediction window
#' @param rep_id      replicate ID
#'
#' @return data.frame with evaluation metrics for pi_k(h)
evaluate_pi_rep <- function(pi_results, truth_df, estimator, w, rep_id) {

  merged <- merge(
    pi_results,
    truth_df[, c("history_stratum", "k", "pi_true", "q_true")],
    by = c("history_stratum", "k"),
    all.x = TRUE
  )

  # Compute CI bounds if not already present
  if (!"pi_ci_lo" %in% names(merged) && "pi_se" %in% names(merged)) {
    merged$pi_ci_lo <- merged$pi_hat - 1.96 * merged$pi_se
    merged$pi_ci_hi <- merged$pi_hat + 1.96 * merged$pi_se
  }

  merged$bias     <- merged$pi_hat - merged$pi_true
  merged$sq_err   <- merged$bias^2
  merged$cover_95 <- as.integer(
    !is.na(merged$pi_ci_lo) & !is.na(merged$pi_ci_hi) &
    !is.na(merged$pi_true) &
    merged$pi_ci_lo <= merged$pi_true &
    merged$pi_ci_hi >= merged$pi_true
  )
  merged$ci_width <- merged$pi_ci_hi - merged$pi_ci_lo

  merged$estimator <- estimator
  merged$w         <- w
  merged$rep       <- rep_id

  # Select output columns (handle both naming conventions)
  out_cols <- c("history_stratum", "k", "estimator", "w", "rep",
                "pi_hat", "pi_true", "q_true",
                "bias", "sq_err", "cover_95", "ci_width")
  # Add pi_se if present
  if ("pi_se" %in% names(merged)) out_cols <- c(out_cols, "pi_se")

  merged[, out_cols[out_cols %in% names(merged)]]
}


# =============================================================================
# SIMULATION FUNCTION: ONE REPLICATE, ONE w
# =============================================================================

run_one_rep <- function(rep_id, w, truth_df) {

  seed_val <- rep_id * 1000 + round(w * 10000)
  set.seed(seed_val)

  # ---- 1. Generate data ----
  event_data <- generate_olmc_data(
    n            = N_SIM,
    K            = K,
    lambda0_rec  = LAMBDA0_REC,
    lambda0_D    = LAMBDA0_D,
    frailty_var  = FRAILTY_VAR,
    beta_rec     = BETA_REC,
    beta_D       = BETA_D,
    censor_type  = "independent",
    censor_param = CENSOR_RATE,
    max_follow   = 3.0,
    history_on_rec = TRUE,
    history_on_D   = FALSE,
    history_effects = HISTORY_EFFECTS
  )

  if (is.null(event_data) || nrow(event_data) == 0) {
    warning("Empty event data at rep ", rep_id, ", w=", w)
    return(NULL)
  }

  # ---- 2. Build landmark dataset ----
  lm_data <- tryCatch(
    build_landmark_dataset(event_data, landmarks = LANDMARKS, w = w, K = K),
    error = function(e) {
      warning("Landmark build failed rep ", rep_id, ": ", e$message)
      NULL
    }
  )
  if (is.null(lm_data) || nrow(lm_data) < 20) return(NULL)

  # ---- 3. DR mu-then-normalize (all estimator variants) ----
  dr_results <- tryCatch(
    cross_fit_dr(lm_data, K = K, w = w, V = 5, outcome_method = "logistic"),
    error = function(e) {
      warning("DR estimation failed rep ", rep_id, ", w=", w, ": ", e$message)
      NULL
    }
  )

  all_eval <- list()

  if (!is.null(dr_results)) {

    # --- Estimator 1: DR-normalize (no truncation threshold) ---
    pi_norm <- normalize_to_pi(dr_results, q_threshold = 0.0)
    pi_df   <- pi_norm[, c("history_stratum", "k", "pi_hat", "pi_se", "q_hat")]
    pi_df$pi_ci_lo <- pi_df$pi_hat - 1.96 * pi_df$pi_se
    pi_df$pi_ci_hi <- pi_df$pi_hat + 1.96 * pi_df$pi_se

    eval_norm <- evaluate_pi_rep(pi_df, truth_df, "DR-normalize", w, rep_id)
    eval_norm$seed <- seed_val
    all_eval[["DR-normalize"]] <- eval_norm

    # --- Estimator 2: DR-truncated at various q(h) thresholds ---
    for (qt in Q_THRESHOLDS) {
      est_name <- sprintf("DR-truncated-%.2f", qt)
      pi_trunc <- normalize_to_pi(dr_results, q_threshold = qt)

      # Only keep reportable rows
      pi_trunc_report <- pi_trunc[pi_trunc$reportable == TRUE, ]

      if (nrow(pi_trunc_report) > 0) {
        pi_trunc_df <- pi_trunc_report[, c("history_stratum", "k", "pi_hat", "pi_se", "q_hat")]
        pi_trunc_df$pi_ci_lo <- pi_trunc_df$pi_hat - 1.96 * pi_trunc_df$pi_se
        pi_trunc_df$pi_ci_hi <- pi_trunc_df$pi_hat + 1.96 * pi_trunc_df$pi_se

        eval_trunc <- evaluate_pi_rep(pi_trunc_df, truth_df, est_name, w, rep_id)
        eval_trunc$seed <- seed_val
        all_eval[[est_name]] <- eval_trunc
      }
    }
  }

  # ---- 4. Direct conditional estimator ----
  direct_results <- tryCatch(
    fit_direct_conditional(lm_data, K = K, n_boot = N_BOOT),
    error = function(e) {
      warning("Direct conditional failed rep ", rep_id, ", w=", w, ": ", e$message)
      NULL
    }
  )

  if (!is.null(direct_results) && any(!is.na(direct_results$pi_hat))) {
    eval_direct <- evaluate_pi_rep(direct_results, truth_df, "direct-conditional", w, rep_id)
    eval_direct$seed <- seed_val
    all_eval[["direct-conditional"]] <- eval_direct
  }

  if (length(all_eval) == 0) return(NULL)
  bind_rows(all_eval)
}


# =============================================================================
# MAIN SIMULATION LOOP
# =============================================================================

output_dir <- file.path(script_dir, "results", "block5")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat(sprintf("Starting Block 5 simulation | n=%d | reps %d to %d\n",
            N_SIM, REP_START, REP_START + N_REPS - 1))
cat(sprintf("Output directory: %s\n\n", output_dir))

for (w_val in W_VALUES) {

  cat(sprintf("=== w = %.2f ===\n", w_val))

  # ---- Compute ground truth for this w ----
  truth_df <- tryCatch(
    compute_ground_truth(w = w_val, n_mc = 50000, seed = 20260321),
    error = function(e) {
      cat(sprintf("  Ground truth computation failed for w=%.2f: %s\n", w_val, e$message))
      NULL
    }
  )

  if (is.null(truth_df)) {
    cat(sprintf("  Skipping w=%.2f due to ground truth failure.\n", w_val))
    next
  }

  cat("  Ground truth q(h) by stratum:\n")
  q_summary <- truth_df %>%
    group_by(history_stratum) %>%
    summarise(q_true = first(q_true), n_mc = first(n_mc_stratum), .groups = "drop")
  print(as.data.frame(q_summary), row.names = FALSE)
  cat("\n")

  # ---- Run replicates ----
  all_results <- vector("list", N_REPS)

  for (i in seq_len(N_REPS)) {
    rep_id <- REP_START + i - 1
    cat(sprintf("  [%d/%d] rep=%d w=%.2f ... ", i, N_REPS, rep_id, w_val))
    t0 <- proc.time()

    res <- tryCatch(
      run_one_rep(rep_id, w_val, truth_df),
      error = function(e) {
        warning("Rep ", rep_id, " w=", w_val, " failed: ", e$message)
        NULL
      }
    )

    elapsed <- (proc.time() - t0)[["elapsed"]]
    cat(sprintf("done in %.1fs\n", elapsed))

    all_results[[i]] <- res
  }

  results_df <- bind_rows(all_results)

  if (nrow(results_df) == 0) {
    cat(sprintf("  No results for w=%.2f. Skipping.\n\n", w_val))
    next
  }

  # ---- Save results ----
  out_file <- file.path(
    output_dir,
    sprintf("block5_w%.2f_reps%d-%d.csv",
            w_val, REP_START, REP_START + N_REPS - 1)
  )
  write.csv(results_df, file = out_file, row.names = FALSE)
  cat(sprintf("  Saved %d rows to %s\n", nrow(results_df), out_file))

  # ---- Quick summary ----
  cat(sprintf("\n  --- Summary for w=%.2f ---\n", w_val))
  summary_df <- results_df %>%
    group_by(estimator, history_stratum, k) %>%
    summarise(
      n_reps      = n(),
      q_true      = mean(q_true, na.rm = TRUE),
      pi_true     = mean(pi_true, na.rm = TRUE),
      bias        = mean(bias, na.rm = TRUE),
      rmse        = sqrt(mean(sq_err, na.rm = TRUE)),
      coverage_95 = mean(cover_95, na.rm = TRUE),
      .groups     = "drop"
    ) %>%
    arrange(estimator, history_stratum, k)

  print(as.data.frame(summary_df), digits = 4)
  cat("\n")
}


# =============================================================================
# CROSS-w SUMMARY AND KILL CRITERION CHECK
# =============================================================================

# Load all block5 results for this run
all_files <- list.files(output_dir, pattern = "^block5_w.*\\.csv$", full.names = TRUE)
if (length(all_files) > 0) {

  combined <- bind_rows(lapply(all_files, read.csv))

  if (nrow(combined) > 0) {

    cat("\n========================================\n")
    cat("BLOCK 5: CROSS-w STABILITY ANALYSIS\n")
    cat("========================================\n\n")

    # Coverage by estimator and q_true band
    combined$q_band <- cut(combined$q_true,
                           breaks = c(0, 0.05, 0.10, 0.15, 0.20, 1.0),
                           labels = c("(0,0.05]", "(0.05,0.10]", "(0.10,0.15]",
                                      "(0.15,0.20]", "(0.20,1]"),
                           include.lowest = TRUE)

    stability_summary <- combined %>%
      filter(!is.na(q_band)) %>%
      group_by(estimator, q_band) %>%
      summarise(
        n_obs       = n(),
        mean_bias   = mean(bias, na.rm = TRUE),
        rmse        = sqrt(mean(sq_err, na.rm = TRUE)),
        coverage_95 = mean(cover_95, na.rm = TRUE),
        .groups     = "drop"
      ) %>%
      arrange(estimator, q_band)

    cat("Coverage by estimator and q(h) band:\n")
    print(as.data.frame(stability_summary), digits = 4)

    # ---- Threshold identification ----
    cat("\n--- Threshold identification (min q(h) for coverage >= 0.90) ---\n")
    threshold_check <- stability_summary %>%
      filter(coverage_95 >= 0.90, n_obs >= 10) %>%
      group_by(estimator) %>%
      summarise(
        min_q_band_stable = first(q_band),
        coverage_at_min   = first(coverage_95),
        .groups = "drop"
      )

    if (nrow(threshold_check) > 0) {
      print(as.data.frame(threshold_check))
    } else {
      cat("  No estimator achieved coverage >= 0.90 in any q band.\n")
    }

    # ---- Kill criterion check ----
    cat("\n--- Kill criterion check ---\n")
    cat("  Checking: Does instability persist at q(h) >= 0.15?\n")

    kill_check <- combined %>%
      filter(q_true >= 0.15, !is.na(cover_95)) %>%
      group_by(estimator) %>%
      summarise(
        n_obs       = n(),
        coverage_95 = mean(cover_95, na.rm = TRUE),
        rmse        = sqrt(mean(sq_err, na.rm = TRUE)),
        .groups     = "drop"
      )

    if (nrow(kill_check) > 0) {
      print(as.data.frame(kill_check), digits = 4)

      # Flag if ANY estimator has coverage < 0.90 at q >= 0.15
      bad_ests <- kill_check %>% filter(coverage_95 < 0.90, n_obs >= 50)
      if (nrow(bad_ests) > 0) {
        cat("\n  KILL CRITERION TRIGGERED: The following estimators have coverage < 0.90\n")
        cat("  at q(h) >= 0.15, suggesting fundamental instability:\n")
        for (r in 1:nrow(bad_ests)) {
          cat(sprintf("    %s: coverage=%.3f, RMSE=%.4f (n=%d)\n",
                      bad_ests$estimator[r], bad_ests$coverage_95[r],
                      bad_ests$rmse[r], bad_ests$n_obs[r]))
        }
      } else {
        cat("  PASS: All estimators with sufficient data achieve coverage >= 0.90 at q(h) >= 0.15.\n")
      }
    } else {
      cat("  No observations with q(h) >= 0.15 available for kill criterion check.\n")
    }
  }
}

cat("\nBlock 5 complete.\n")
