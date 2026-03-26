# =============================================================================
# block3_naive_bias.R
# Block 3: Naive Method Bias Demonstration for OLMC
#
# Scientific question: Are observed-case and IPCW shortcuts materially biased
# in realistic settings with informative censoring and confounded death?
#
# DGM:
#   - K = 3, n = 1500
#   - Censoring: 30-35%, strongly driven by deteriorating event history
#   - Death: 25-30%, strongly linked to event type 1 risk (confounding)
#   - Frailty sigma^2 = 0.75
#   - history_on_rec = TRUE, history_on_D = TRUE
#   - censor_type = "history" with aggressive parameters
#
# Estimators:
#   1. DR             : correctly specified doubly robust (proposed method)
#   2. OR-only        : outcome regression only (no censoring adjustment)
#   3. IPCW-only      : inverse probability censoring weighting only
#   4. Observed-case  : empirical proportion among delta_N==1 rows only
#   5. Death-as-censor: treat death as censoring, then run DR
#
# Primary metrics:
#   - Absolute bias for mu_k(h) across H0-H3
#   - Type-specific calibration error for pi_k(h)
#   - Bias expressed in clinically meaningful percentages
#
# Expected finding: Observed-case and death-as-censoring show >= 10% absolute
# bias for at least one history stratum; DR materially closer to truth.
#
# Kill criterion: Naive methods nearly unbiased in ALL plausible scenarios
# -> practical motivation weak.
#
# Output: results/block3/block3_est{ESTIMATOR}_reps{START}-{END}.csv
#
# Usage (SLURM):
#   Rscript block3_naive_bias.R
#   or via env vars: BLOCK3_REP_START, BLOCK3_N_REPS, BLOCK3_ESTIMATOR
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

REP_START <- as.integer(Sys.getenv("BLOCK3_REP_START", unset = parse_arg(args, "--rep_start", 1)))
N_REPS    <- as.integer(Sys.getenv("BLOCK3_N_REPS",    unset = parse_arg(args, "--n_reps", 200)))
ESTIMATOR <- Sys.getenv("BLOCK3_ESTIMATOR", unset = "all")

cat(sprintf(
  "Block 3 Naive Bias | reps=%d-%d | estimator=%s\n",
  REP_START, REP_START + N_REPS - 1, ESTIMATOR
))

# =============================================================================
# DGM PARAMETERS (Block 3: realistic K=3, informative censoring + death)
# =============================================================================

K           <- 3
N_SIM       <- 1500
W           <- 0.5          # prediction window: 6 months
LANDMARKS   <- seq(0.5, 3.0, by = 0.5)
FRAILTY_VAR <- 0.75         # sigma^2
P           <- 4            # covariates: z, x, x2, x3

# Baseline hazards (K=3 types + death)
LAMBDA0_REC <- c(0.35, 0.28, 0.20)  # type 1 highest risk
LAMBDA0_D   <- 0.10                  # ~25-30% death by 3yr with frailty

# Covariate log-HRs for recurrent events (K x P)
BETA_REC <- matrix(c(
   0.50, -0.30,  0.20, -0.15,   # type 1
  -0.30,  0.40, -0.10,  0.25,   # type 2
   0.20, -0.20,  0.35, -0.10    # type 3
), nrow = K, ncol = P, byrow = TRUE)

# Death hazard log-HRs: strongly linked to type 1 risk covariates (confounding)
BETA_D <- c(0.45, -0.25, 0.15, -0.10)

# History effects: aggressive, making censoring and death informative
HISTORY_EFFECTS <- list(
  count_effect   =  0.10,   # each prior event increases hazard by ~10%
  gap_effect     = -0.05,   # recent events (short gap) increase hazard
  last_type_same =  0.20    # self-excitation: same-type clustering
)

# Censoring parameters: history-dependent (informative dropout)
CENSOR_PARAM <- list(
  base_rate    = 0.30,
  history_coef = c(0.25, -0.15, 0.10, 0.00)
)

# Number of Monte Carlo subjects for ground truth
N_TRUTH <- 50000

# =============================================================================
# GROUND TRUTH VIA LARGE MONTE CARLO (no censoring)
# =============================================================================

cat("Computing ground truth via large Monte Carlo (n=50000, no censoring)...\n")
t_truth_start <- proc.time()

set.seed(20260321 + 999)  # fixed seed for truth

truth_data <- generate_olmc_data(
  n            = N_TRUTH,
  K            = K,
  lambda0_rec  = LAMBDA0_REC,
  lambda0_D    = LAMBDA0_D,
  frailty_var  = FRAILTY_VAR,
  beta_rec     = BETA_REC,
  beta_D       = BETA_D,
  censor_type  = "independent",
  censor_param = 1e-6,        # essentially no censoring
  max_follow   = 10.0,        # very long follow-up
  history_effects = HISTORY_EFFECTS,
  history_on_rec  = TRUE,
  history_on_D    = TRUE
)

truth_lm <- build_landmark_dataset(truth_data, landmarks = LANDMARKS, w = W, K = K)

# Compute true mu_k(h) as empirical proportion in this large uncensored sample
strata <- c("H0", "H1", "H2", "H3")

true_mu_list <- vector("list", length(strata))
for (h_idx in seq_along(strata)) {
  h <- strata[h_idx]
  rows_h <- truth_lm[truth_lm$history_stratum == h, ]
  n_h <- nrow(rows_h)

  if (n_h < 10) {
    true_mu_list[[h_idx]] <- data.frame(
      history_stratum = h,
      k       = 1:K,
      mu_true = rep(NA_real_, K),
      pi_true = rep(NA_real_, K),
      q_true  = NA_real_
    )
    next
  }

  # mu_k(h) = P(T_sN <= w, J_s = k, T_sN < T_sD | H_s = h)
  # In uncensored data, this is just the empirical proportion

  mu_k <- numeric(K)
  for (k in 1:K) {
    mu_k[k] <- mean(rows_h[[paste0("delta_N", k)]], na.rm = TRUE)
  }
  q_h  <- sum(mu_k)
  pi_k <- if (q_h > 1e-6) mu_k / q_h else rep(1/K, K)

  true_mu_list[[h_idx]] <- data.frame(
    history_stratum = h,
    k       = 1:K,
    mu_true = mu_k,
    pi_true = pi_k,
    q_true  = q_h
  )
}

true_mu_df <- bind_rows(true_mu_list)

t_truth_elapsed <- (proc.time() - t_truth_start)[["elapsed"]]
cat(sprintf("Ground truth computed in %.1fs\n", t_truth_elapsed))
cat("\nTrue mu_k(h) values:\n")
print(as.data.frame(true_mu_df), digits = 4)
cat("\n")

# =============================================================================
# HELPER: OBSERVED-CASE NAIVE ESTIMATOR
# =============================================================================

#' Observed-case estimator: empirical type proportions among delta_N==1 rows
#'
#' This naive approach ignores censored and death rows entirely.
#' Computes mu_k(h) as the proportion of observed events that are type k,
#' scaled by the proportion of rows with any event.
#'
#' @param lm_data  landmark dataset
#' @param K        number of event types
#'
#' @return data.frame matching cross_fit_dr() output format
observed_case_estimator <- function(lm_data, K = 3) {

  strata_levels <- levels(lm_data$history_stratum)
  results <- vector("list", length(strata_levels) * K)
  idx <- 0L

  for (h in strata_levels) {
    h_rows <- lm_data[lm_data$history_stratum == h & !is.na(lm_data$history_stratum), ]
    n_total <- nrow(h_rows)

    # Only use rows where an event was observed (delta_N == 1)
    obs_rows <- h_rows[h_rows$delta_N == 1, ]
    n_obs <- nrow(obs_rows)

    # Subjects in stratum
    pids_h <- unique(h_rows$pid)
    n_sub  <- length(pids_h)

    for (k in 1:K) {
      idx <- idx + 1L

      if (n_obs < 5 || n_total < 10) {
        results[[idx]] <- data.frame(
          history_stratum = h, k = k,
          mu_hat = NA, se = NA, ci_lo = NA, ci_hi = NA,
          n_rows = n_total, n_subjects = n_sub
        )
        next
      }

      # Naive mu_k(h): proportion of ALL rows with type-k event
      # This equals P(delta_Nk=1 | observed) * P(observed) naively
      # But observed-case literally just uses delta_Nk among delta_N==1 rows
      # to get pi_k, then scales by observed event rate.
      # Simpler: just use the empirical mean of delta_Nk across ALL rows
      # (treating censored/death as delta_Nk=0).
      # The bias comes from ignoring that censored/death rows may have
      # different underlying event probabilities.
      #
      # Actually, the "observed-case" approach is: restrict to complete cases
      # (delta_N == 1), compute empirical proportion of type k among those.
      # Then scale by the naive event rate (fraction of rows with delta_N==1).
      naive_event_rate <- n_obs / n_total
      naive_pi_k <- mean(obs_rows$J_s == k, na.rm = TRUE)
      mu_hat <- naive_event_rate * naive_pi_k

      # Bootstrap-style SE using subject-level averaging
      pid_scores <- tapply(h_rows[[paste0("delta_N", k)]], h_rows$pid, mean, na.rm = TRUE)
      se_sub <- sqrt(var(pid_scores, na.rm = TRUE) / length(pid_scores))

      results[[idx]] <- data.frame(
        history_stratum = h, k = k,
        mu_hat = mu_hat, se = se_sub,
        ci_lo = mu_hat - 1.96 * se_sub,
        ci_hi = mu_hat + 1.96 * se_sub,
        n_rows = n_total, n_subjects = n_sub
      )
    }
  }

  bind_rows(results)
}

# =============================================================================
# HELPER: DEATH-AS-CENSORING MODIFIED LANDMARK DATASET
# =============================================================================

#' Modify landmark dataset to treat death as censoring
#'
#' Sets T_sD = Inf for all rows, then recomputes tau_i and delta_N indicators
#' as if death were just another form of censoring (not a competing risk).
#'
#' @param lm_data  original landmark dataset
#' @param K        number of event types
#' @param w        prediction window
#'
#' @return modified landmark dataset
death_as_censoring_modify <- function(lm_data, K = 3, w = 0.5) {

  lm_mod <- lm_data

  # Treat death as censoring: set T_sD to Inf
  lm_mod$T_sD <- Inf

  # Recompute tau_i = min(T_sN, C_si, w)  [no T_sD since Inf]
  lm_mod$tau_i <- pmin(lm_mod$T_sN, lm_mod$C_si, w)

  # Recompute delta_N: event occurred before censoring and within window
  # Now ignoring death as a competing event
  lm_mod$delta_N <- as.integer(
    lm_mod$T_sN <= w & lm_mod$T_sN <= lm_mod$C_si
  )

  # Recompute J_s
  lm_mod$J_s <- ifelse(lm_mod$delta_N == 1L, lm_data$J_s, NA_integer_)

  # Recompute type-specific indicators
  for (k in 1:K) {
    lm_mod[[paste0("delta_N", k)]] <- as.integer(
      lm_mod$delta_N == 1L & lm_mod$J_s == k
    )
  }

  # Recompute history stratum (unchanged, but ensure factor levels are preserved)
  lm_mod$history_stratum <- lm_data$history_stratum

  lm_mod
}

# =============================================================================
# SIMULATION FUNCTION: ONE REPLICATE
# =============================================================================

run_one_rep <- function(rep_id, n, estimator = "DR") {

  seed_val <- rep_id * 1000 + n
  set.seed(seed_val)

  # ---- 1. Generate data (informative censoring + death) ----
  event_data <- generate_olmc_data(
    n               = n,
    K               = K,
    lambda0_rec     = LAMBDA0_REC,
    lambda0_D       = LAMBDA0_D,
    frailty_var     = FRAILTY_VAR,
    beta_rec        = BETA_REC,
    beta_D          = BETA_D,
    censor_type     = "history",
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

  # ---- 3. Compute estimates based on estimator type ----
  dr_results <- tryCatch({
    if (estimator == "DR") {
      # Correctly specified DR (proposed method)
      cross_fit_dr(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic"
      )

    } else if (estimator == "OR-only") {
      # Outcome regression only: G_C = 1, Lambda_k = 0
      cross_fit_dr(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic",
        oracle_gc = function(u, row) 1.0,
        oracle_Lk = function(tau, k, row) 0.0
      )

    } else if (estimator == "IPCW-only") {
      # IPCW only: M_k = 0 (no outcome regression)
      cross_fit_dr(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic",
        oracle_Mk = function(lm_data) matrix(0, nrow = nrow(lm_data), ncol = K)
      )

    } else if (estimator == "Observed-case") {
      # Naive: empirical proportions among observed events only
      observed_case_estimator(lm_data, K = K)

    } else if (estimator == "Death-as-censor") {
      # Treat death as censoring, then run DR on modified data
      lm_mod <- death_as_censoring_modify(lm_data, K = K, w = W)
      cross_fit_dr(
        lm_mod, K = K, w = W, V = 5,
        outcome_method = "logistic"
      )

    } else {
      stop("Unknown estimator: ", estimator)
    }
  }, error = function(e) {
    warning("Estimation failed rep ", rep_id, ", estimator=", estimator, ": ", e$message)
    NULL
  })

  if (is.null(dr_results)) return(NULL)

  # ---- 4. Evaluate against ground truth ----
  eval_df <- evaluate_one_rep(dr_results, true_mu_df)
  eval_df$rep       <- rep_id
  eval_df$n         <- n
  eval_df$estimator <- estimator
  eval_df$seed      <- seed_val

  # ---- 5. Add calibration metrics (pi_k) ----
  pi_results <- tryCatch(
    normalize_to_pi(dr_results),
    error = function(e) NULL
  )

  if (!is.null(pi_results)) {
    calib_df <- tryCatch(
      compute_calibration(lm_data, pi_results, K = K),
      error = function(e) NULL
    )
    if (!is.null(calib_df)) {
      calib_merged <- merge(
        eval_df,
        calib_df[, c("history_stratum", "k", "pi_hat", "pi_empirical", "calibration_error")],
        by = c("history_stratum", "k"),
        all.x = TRUE
      )
      # Also merge true pi
      calib_merged <- merge(
        calib_merged,
        true_mu_df[, c("history_stratum", "k", "pi_true")],
        by = c("history_stratum", "k"),
        all.x = TRUE
      )
      calib_merged$pi_bias <- calib_merged$pi_hat - calib_merged$pi_true
      return(calib_merged)
    }
  }

  eval_df
}


# "all" estimators path
run_all_estimators <- function(rep_id, n) {
  ests <- c("DR", "OR-only", "IPCW-only", "Observed-case", "Death-as-censor")
  results <- lapply(ests, function(est) {
    cat(sprintf("  rep=%d est=%s\n", rep_id, est))
    run_one_rep(rep_id, n, estimator = est)
  })
  bind_rows(results)
}

# =============================================================================
# MAIN SIMULATION LOOP
# =============================================================================

output_dir <- file.path(script_dir, "results", "block3")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat(sprintf("Starting Block 3 simulation | n=%d | reps %d to %d\n",
            N_SIM, REP_START, REP_START + N_REPS - 1))
cat(sprintf("Output directory: %s\n\n", output_dir))

all_results <- vector("list", N_REPS)

for (i in seq_len(N_REPS)) {
  rep_id <- REP_START + i - 1
  cat(sprintf("[%d/%d] rep=%d ... ", i, N_REPS, rep_id))
  t0 <- proc.time()

  if (ESTIMATOR == "all") {
    res <- run_all_estimators(rep_id, N_SIM)
  } else {
    res <- run_one_rep(rep_id, N_SIM, estimator = ESTIMATOR)
  }

  elapsed <- (proc.time() - t0)[["elapsed"]]
  cat(sprintf("done in %.1fs\n", elapsed))

  all_results[[i]] <- res
}

results_df <- bind_rows(all_results)

# ---- Save results ----
out_file <- file.path(
  output_dir,
  sprintf("block3_est%s_reps%d-%d.csv",
          ESTIMATOR, REP_START, REP_START + N_REPS - 1)
)
write.csv(results_df, file = out_file, row.names = FALSE)
cat(sprintf("\nSaved %d rows to %s\n", nrow(results_df), out_file))

# =============================================================================
# SUMMARY AND KILL CRITERION CHECK
# =============================================================================

if (nrow(results_df) > 0) {

  cat("\n=== Block 3 Summary: Bias by Estimator and Stratum ===\n\n")

  # ---- Absolute bias summary ----
  bias_summary <- results_df %>%
    group_by(estimator, history_stratum, k) %>%
    summarise(
      n_reps     = n(),
      mu_true    = mean(mu_true, na.rm = TRUE),
      mu_hat_avg = mean(mu_hat, na.rm = TRUE),
      bias       = mean(bias, na.rm = TRUE),
      abs_bias   = abs(mean(bias, na.rm = TRUE)),
      rmse       = sqrt(mean(sq_err, na.rm = TRUE)),
      cover_95   = mean(cover_95, na.rm = TRUE),
      .groups    = "drop"
    ) %>%
    arrange(estimator, history_stratum, k)

  print(as.data.frame(bias_summary), digits = 4)

  # ---- Bias as percentage of truth ----
  cat("\n=== Bias as Percentage of True mu_k(h) ===\n\n")

  pct_bias <- bias_summary %>%
    mutate(
      pct_bias = ifelse(abs(mu_true) > 1e-6,
                        100 * abs_bias / abs(mu_true),
                        NA_real_)
    ) %>%
    select(estimator, history_stratum, k, mu_true, bias, pct_bias)

  print(as.data.frame(pct_bias), digits = 4)

  # ---- Calibration summary (if pi columns exist) ----
  if ("pi_bias" %in% names(results_df)) {
    cat("\n=== Type-Specific Calibration Error (pi_k) ===\n\n")

    calib_summary <- results_df %>%
      filter(!is.na(pi_hat)) %>%
      group_by(estimator, history_stratum, k) %>%
      summarise(
        pi_true_avg    = mean(pi_true, na.rm = TRUE),
        pi_hat_avg     = mean(pi_hat, na.rm = TRUE),
        pi_bias_avg    = mean(pi_bias, na.rm = TRUE),
        abs_pi_bias    = abs(mean(pi_bias, na.rm = TRUE)),
        calib_err_avg  = mean(calibration_error, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      arrange(estimator, history_stratum, k)

    print(as.data.frame(calib_summary), digits = 4)
  }

  # ---- Kill criterion check ----
  cat("\n=== Kill Criterion Check ===\n")
  cat("Threshold: naive methods should show >= 10% absolute bias in at least one stratum.\n\n")

  naive_methods <- c("Observed-case", "Death-as-censor")
  dr_method     <- "DR"

  for (method in c(naive_methods, dr_method)) {
    method_rows <- bias_summary %>%
      filter(estimator == method, n_reps >= 20)

    if (nrow(method_rows) > 0) {
      max_abs_bias <- max(method_rows$abs_bias, na.rm = TRUE)
      max_pct_bias <- max(
        ifelse(abs(method_rows$mu_true) > 1e-6,
               100 * method_rows$abs_bias / abs(method_rows$mu_true),
               0),
        na.rm = TRUE
      )
      worst_row <- method_rows[which.max(method_rows$abs_bias), ]

      cat(sprintf(
        "  %s:\n    Max |bias| = %.4f (%.1f%% of truth) at H=%s, k=%d\n    Max RMSE = %.4f\n",
        method,
        max_abs_bias, max_pct_bias,
        worst_row$history_stratum, worst_row$k,
        max(method_rows$rmse, na.rm = TRUE)
      ))
    } else {
      cat(sprintf("  %s: insufficient data for summary\n", method))
    }
  }

  # Check if ANY naive method has >= 10% bias somewhere
  naive_summary <- bias_summary %>%
    filter(estimator %in% naive_methods, n_reps >= 20) %>%
    mutate(pct_bias = ifelse(abs(mu_true) > 1e-6,
                             100 * abs_bias / abs(mu_true), 0))

  if (nrow(naive_summary) > 0) {
    max_naive_pct <- max(naive_summary$pct_bias, na.rm = TRUE)
    max_naive_abs <- max(naive_summary$abs_bias, na.rm = TRUE)

    cat(sprintf(
      "\n  Overall max naive |bias|: %.4f (%.1f%% of truth)\n",
      max_naive_abs, max_naive_pct
    ))

    if (max_naive_abs < 0.10 && max_naive_pct < 10) {
      cat("  KILL CRITERION TRIGGERED: Naive methods show < 10% bias everywhere.\n")
      cat("  Practical motivation for DR correction may be weak.\n")
    } else {
      cat("  PASS: Naive methods show material bias. DR correction justified.\n")
    }

    # Compare DR vs naive
    dr_summary <- bias_summary %>%
      filter(estimator == dr_method, n_reps >= 20)

    if (nrow(dr_summary) > 0) {
      max_dr_abs <- max(dr_summary$abs_bias, na.rm = TRUE)
      cat(sprintf(
        "\n  DR max |bias|: %.4f vs Naive max |bias|: %.4f\n",
        max_dr_abs, max_naive_abs
      ))
      cat(sprintf(
        "  Bias reduction ratio: %.1fx\n",
        max_naive_abs / max(max_dr_abs, 1e-6)
      ))
    }
  }
}
