# =============================================================================
# block4_cr_comparison.R
# Block 4: First-Event Competing-Risks Methods Fail After Recurrence
#
# Scientific question: Do first-event competing-risks methods fail after
# recurrence? CR models treat event types as competing risks of a single
# "first event" and ignore the recurrent history.
#
# DGM:
#   - K = 3, n = 2000
#   - Strong recurrent dependence: next event type strongly depends on last
#     event type and event count
#   - Death 20-25%, censoring 20-25%, frailty sigma^2 = 0.5
#   - history_on_rec = TRUE, history_on_D = TRUE
#   - Strong history effects: count=0.15, gap=-0.08, last_type_same=0.30
#
# Estimators:
#   1. Proposed-DR  : our DR estimator, correctly specified with history
#   2. Fine-Gray    : subdistribution hazard model applied to ALL landmark
#                     rows (including H1+ strata) -- conceptually wrong for
#                     recurrent data since it treats types as first-event
#                     competing risks
#   3. CS-Cox-noHist: cause-specific Cox for each type k, using only
#                     baseline covariates (z, x, x2, x3) -- ignores history
#   4. Baseline-only: predict from H0 stratum only, apply to all strata
#
# Kill criterion: < 25% of evaluable landmark rows have prior events
#   (H1+H2+H3); or prior history has negligible effect on next type.
#
# Output: results/block4/block4_est{ESTIMATOR}_reps{START}-{END}.csv
#
# Usage (SLURM):
#   Rscript block4_cr_comparison.R
#   or via SLURM array with BLOCK4_REP_START, BLOCK4_N_REPS, BLOCK4_ESTIMATOR
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

# Check if cmprsk is available for Fine-Gray
HAS_CMPRSK <- requireNamespace("cmprsk", quietly = TRUE)
if (HAS_CMPRSK) {
  library(cmprsk)
  cat("cmprsk package available -- using crr() for Fine-Gray.\n")
} else {
  cat("cmprsk not available -- Fine-Gray will use cause-specific Cox fallback.\n")
}

# =============================================================================
# COMMAND-LINE / ENV ARGUMENTS
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
parse_arg <- function(args, flag, default) {
  idx <- which(args == flag)
  if (length(idx) > 0 && idx < length(args)) as.numeric(args[idx + 1]) else default
}

N_SIM     <- as.integer(Sys.getenv("BLOCK4_N", unset = parse_arg(args, "--n", 2000)))
REP_START <- as.integer(Sys.getenv("BLOCK4_REP_START", unset = parse_arg(args, "--rep_start", 1)))
N_REPS    <- as.integer(Sys.getenv("BLOCK4_N_REPS", unset = parse_arg(args, "--n_reps", 200)))
ESTIMATOR <- Sys.getenv("BLOCK4_ESTIMATOR", unset = "all")

cat(sprintf(
  "Block 4 CR Comparison | n=%d | reps=%d-%d | estimator=%s\n",
  N_SIM, REP_START, REP_START + N_REPS - 1, ESTIMATOR
))

# =============================================================================
# DGM PARAMETERS (Block 4: strong history dependence, K=3)
# =============================================================================

K           <- 3
W           <- 0.5          # prediction window: 6 months
LANDMARKS   <- seq(0.5, 3.0, by = 0.5)
FRAILTY_VAR <- 0.5          # sigma^2
P           <- 4            # number of covariates (z, x, x2, x3)

# Baseline hazards (per year)
LAMBDA0_REC <- c(0.35, 0.30, 0.25)  # type 1, 2, 3
LAMBDA0_D   <- 0.08                  # ~20-25% death by 3 years with frailty
CENSOR_RATE <- 0.20                  # ~20-25% censored

# Covariate log-HRs
BETA_REC <- matrix(c(
   0.50, -0.30,  0.20, -0.10,   # type 1
  -0.30,  0.40, -0.10,  0.25,   # type 2
   0.20, -0.20,  0.35, -0.15    # type 3
), nrow = K, ncol = P, byrow = TRUE)

BETA_D <- c(0.30, -0.20, 0.10, 0.00)

# Strong history effects
HISTORY_EFFECTS <- list(
  count_effect   =  0.15,
  gap_effect     = -0.08,
  last_type_same =  0.30
)

# =============================================================================
# GROUND TRUTH VIA LARGE MONTE CARLO
# =============================================================================

#' Compute ground-truth mu_k(h) via large uncensored Monte Carlo sample
#'
#' Generates a large dataset with no censoring, builds landmark data, then
#' computes empirical mu_k(h) = P(T_sN <= w, J_s = k | H_s = h) directly.
#'
#' @param n_mc       number of Monte Carlo subjects (default 50000)
#' @param landmarks  landmark times
#' @param w          prediction window
#' @param K          number of event types
#'
#' @return data.frame with columns: history_stratum, k, mu_true, pi_true, q_true
compute_ground_truth_mc <- function(
  n_mc      = 50000,
  landmarks = LANDMARKS,
  w         = W,
  K_val     = K
) {
  cat("Computing ground truth via Monte Carlo (n=", n_mc, ")...\n")
  t0 <- proc.time()

  # Generate large dataset with NO censoring (censor_rate -> 0)
  mc_data <- generate_olmc_data(
    n            = n_mc,
    K            = K_val,
    lambda0_rec  = LAMBDA0_REC,
    lambda0_D    = LAMBDA0_D,
    frailty_var  = FRAILTY_VAR,
    beta_rec     = BETA_REC,
    beta_D       = BETA_D,
    censor_type  = "independent",
    censor_param = 1e-6,            # essentially no censoring
    max_follow   = 5.0,             # long follow-up to avoid admin censoring
    history_effects = HISTORY_EFFECTS,
    history_on_rec  = TRUE,
    history_on_D    = TRUE
  )

  # Build landmark dataset
  mc_lm <- build_landmark_dataset(mc_data, landmarks = landmarks, w = w, K = K_val)

  # Compute empirical mu_k(h)
  strata <- levels(mc_lm$history_stratum)
  results <- vector("list", length(strata) * K_val)
  idx <- 0L

  for (h in strata) {
    rows_h <- mc_lm[mc_lm$history_stratum == h, ]
    n_h    <- nrow(rows_h)

    for (k in 1:K_val) {
      idx <- idx + 1L
      if (n_h == 0) {
        results[[idx]] <- data.frame(
          history_stratum = h, k = k,
          mu_true = NA, pi_true = NA, q_true = NA, n_mc_rows = 0L
        )
        next
      }

      # mu_k(h) = proportion with delta_Nk = 1 (no censoring means this is exact)
      mu_k <- mean(rows_h[[paste0("delta_N", k)]], na.rm = TRUE)
      results[[idx]] <- data.frame(
        history_stratum = h, k = k,
        mu_true = mu_k, pi_true = NA, q_true = NA, n_mc_rows = n_h
      )
    }
  }

  truth <- bind_rows(results)

  # Compute q and pi from mu
  for (h in strata) {
    h_mask <- truth$history_stratum == h
    q_h    <- sum(truth$mu_true[h_mask], na.rm = TRUE)
    truth$q_true[h_mask]  <- q_h
    truth$pi_true[h_mask] <- if (q_h > 1e-6) truth$mu_true[h_mask] / q_h else 1/K_val
  }

  elapsed <- (proc.time() - t0)[["elapsed"]]
  cat(sprintf("Ground truth computed in %.1fs (%d MC landmark rows)\n",
              elapsed, nrow(mc_lm)))
  cat("Ground truth mu_k(h):\n")
  print(as.data.frame(truth), digits = 4)

  truth
}

# Compute ground truth once
GROUND_TRUTH <- compute_ground_truth_mc()

# =============================================================================
# COMPETITOR ESTIMATORS
# =============================================================================

#' Fine-Gray subdistribution hazard model (first-event competing risks)
#'
#' Applies Fine-Gray (cmprsk::crr) or cause-specific Cox fallback to ALL
#' landmark rows, treating types 1..K as competing risks of a single event.
#' This is conceptually wrong for H1+ strata because the subject already
#' had prior events.
#'
#' @param lm_data  landmark dataset
#' @param K        number of event types
#'
#' @return data.frame matching cross_fit_dr() output format
fit_fine_gray <- function(lm_data, K = 3) {

  strata <- levels(lm_data$history_stratum)

  # Covariates: ONLY baseline (deliberately ignoring history features)
  base_cols <- c("z", "x", "x2", "x3")
  X <- as.matrix(lm_data[, base_cols, drop = FALSE])
  X[is.na(X)] <- 0

  # Failure time and cause (0 = censored/death, 1..K = type)
  ftime  <- lm_data$tau_i
  fstatus <- ifelse(lm_data$delta_N == 1, lm_data$J_s, 0L)
  fstatus[is.na(fstatus)] <- 0L

  # Fit Fine-Gray for each type k
  cif_pred <- matrix(NA_real_, nrow = nrow(lm_data), ncol = K)

  for (k in 1:K) {
    cif_pred[, k] <- tryCatch({
      if (HAS_CMPRSK) {
        # Fine-Gray subdistribution hazard for cause k
        # crr needs: ftime, fstatus, covariates, failcode = k
        fg_fit <- crr(
          ftime   = ftime,
          fstatus = fstatus,
          cov1    = X,
          failcode = k,
          cencode  = 0
        )

        # Predict CIF at time W for each subject
        # crr predict gives CIF at unique failure times
        fg_pred <- predict(fg_fit, cov1 = X)

        # Extract CIF at time closest to W
        pred_times <- as.numeric(fg_pred[1, -1])  # first row = times (minus covariate label)
        # Actually, predict.crr returns a matrix: rows = times, cols include time + subjects
        # Need to handle the output format carefully
        # predict.crr returns: column 1 = time, columns 2:(n+1) = CIF for each subject
        time_col <- fg_pred[, 1]
        idx_w    <- which.min(abs(time_col - W))
        cif_at_w <- as.numeric(fg_pred[idx_w, -1])

        if (length(cif_at_w) == nrow(lm_data)) {
          cif_at_w
        } else {
          # Fallback: use cause-specific Cox approximation
          fit_cs_cox_for_type(lm_data, X, k, K)
        }
      } else {
        # Fallback: cause-specific Cox (not exactly Fine-Gray, but captures
        # the key flaw of ignoring history)
        fit_cs_cox_for_type(lm_data, X, k, K)
      }
    }, error = function(e) {
      warning("Fine-Gray failed for type ", k, ": ", e$message, " -- using CS Cox fallback")
      fit_cs_cox_for_type(lm_data, X, k, K)
    })
  }

  # Assemble results by stratum (same format as cross_fit_dr output)
  assemble_competitor_results(lm_data, cif_pred, strata, K, method_name = "Fine-Gray")
}


#' Cause-specific Cox approximation for one event type
#'
#' Fits a cause-specific Cox model for type k using only baseline covariates.
#' Returns predicted CIF via Breslow estimator.
#'
#' @param lm_data  landmark dataset
#' @param X        covariate matrix (baseline only)
#' @param k        event type
#' @param K        total number of types
#'
#' @return numeric vector of predicted CIF at time W for each row
fit_cs_cox_for_type <- function(lm_data, X, k, K) {

  # Status: type k event = 1, everything else = 0
  status_k <- as.integer(lm_data$delta_N == 1 & lm_data$J_s == k)
  status_k[is.na(status_k)] <- 0L

  df_fit        <- as.data.frame(X)
  df_fit$time   <- pmax(lm_data$tau_i, 1e-6)
  df_fit$status <- status_k

  xnames <- colnames(X)
  rhs    <- paste(xnames, collapse = " + ")
  fmla   <- as.formula(paste("Surv(time, status) ~", rhs))

  cox_k <- tryCatch(
    coxph(fmla, data = df_fit, ties = "breslow"),
    error = function(e) coxph(Surv(time, status) ~ 1, data = df_fit, ties = "breslow")
  )

  # Predict cumulative hazard at W, convert to CIF approximation
  # CIF_k(w) ~ 1 - exp(-Lambda_k(w|X))  (cause-specific, ignoring other types)
  bh_k  <- basehaz(cox_k, centered = FALSE)
  H0_fn <- stepfun(bh_k$time, c(0, bh_k$hazard))
  H0_w  <- H0_fn(W)

  coef_k <- coef(cox_k)
  coef_k[is.na(coef_k)] <- 0

  X_aligned <- matrix(0, nrow = nrow(X), ncol = length(coef_k))
  colnames(X_aligned) <- names(coef_k)
  common <- intersect(colnames(X), names(coef_k))
  X_aligned[, common] <- X[, common]

  lp <- as.numeric(X_aligned %*% coef_k)

  # Approximate CIF: 1 - exp(-H0(w) * exp(lp))
  cif_k <- 1 - exp(-H0_w * exp(lp))
  pmax(pmin(cif_k, 1 - 1e-6), 1e-6)
}


#' Cause-specific Cox model ignoring history (CS-Cox-noHist)
#'
#' Fits cause-specific Cox for each type k using ONLY baseline covariates
#' (z, x, x2, x3) -- deliberately ignoring history features.
#'
#' @param lm_data  landmark dataset
#' @param K        number of event types
#'
#' @return data.frame matching cross_fit_dr() output format
fit_cs_cox_nohist <- function(lm_data, K = 3) {

  strata <- levels(lm_data$history_stratum)

  # Baseline covariates ONLY
  base_cols <- c("z", "x", "x2", "x3")
  X <- as.matrix(lm_data[, base_cols, drop = FALSE])
  X[is.na(X)] <- 0

  cif_pred <- matrix(NA_real_, nrow = nrow(lm_data), ncol = K)

  for (k in 1:K) {
    cif_pred[, k] <- fit_cs_cox_for_type(lm_data, X, k, K)
  }

  assemble_competitor_results(lm_data, cif_pred, strata, K, method_name = "CS-Cox-noHist")
}


#' Baseline-only estimator
#'
#' Uses the proposed DR estimator but only computes mu_k("H0"), then applies
#' those estimates to ALL strata -- pretending everyone is at baseline.
#'
#' @param lm_data  landmark dataset
#' @param K        number of event types
#'
#' @return data.frame matching cross_fit_dr() output format
fit_baseline_only <- function(lm_data, K = 3) {

  strata <- levels(lm_data$history_stratum)

  # Fit DR on H0 rows only
  h0_rows <- lm_data[lm_data$history_stratum == "H0", ]

  if (nrow(h0_rows) < 20) {
    # Not enough H0 rows -- return NA
    results <- expand.grid(history_stratum = strata, k = 1:K)
    results$mu_hat <- NA_real_
    results$se     <- NA_real_
    results$ci_lo  <- NA_real_
    results$ci_hi  <- NA_real_
    results$n_rows <- 0L
    results$n_subjects <- 0L
    return(results)
  }

  # Run DR on H0 data
  dr_h0 <- tryCatch(
    cross_fit_dr(h0_rows, K = K, w = W, V = 5, outcome_method = "logistic"),
    error = function(e) {
      warning("Baseline-only DR failed: ", e$message)
      NULL
    }
  )

  if (is.null(dr_h0)) {
    results <- expand.grid(history_stratum = strata, k = 1:K)
    results$mu_hat <- NA_real_
    results$se     <- NA_real_
    results$ci_lo  <- NA_real_
    results$ci_hi  <- NA_real_
    results$n_rows <- 0L
    results$n_subjects <- 0L
    return(results)
  }

  # Extract H0 estimates
  h0_est <- dr_h0[dr_h0$history_stratum == "H0", ]

  # Apply H0 estimates to ALL strata
  results <- vector("list", length(strata))
  for (i in seq_along(strata)) {
    h <- strata[i]
    h_rows <- lm_data[lm_data$history_stratum == h, ]
    res_h <- h0_est
    res_h$history_stratum <- h
    res_h$n_rows     <- nrow(h_rows)
    res_h$n_subjects <- length(unique(h_rows$pid))
    results[[i]] <- res_h
  }

  bind_rows(results)
}


#' Assemble competitor results into standard output format
#'
#' Takes predicted CIF matrix and computes stratum-level mu_hat and SE.
#'
#' @param lm_data    landmark dataset
#' @param cif_pred   n x K matrix of predicted CIF values (mu_k estimates)
#' @param strata     character vector of stratum levels
#' @param K          number of event types
#' @param method_name character label for the method
#'
#' @return data.frame with: history_stratum, k, mu_hat, se, ci_lo, ci_hi, n_rows, n_subjects
assemble_competitor_results <- function(lm_data, cif_pred, strata, K, method_name = "") {

  results <- vector("list", length(strata) * K)
  idx <- 0L

  for (h in strata) {
    h_mask <- lm_data$history_stratum == h & !is.na(lm_data$history_stratum)
    pids_h <- lm_data$pid[h_mask]
    n_h    <- sum(h_mask)

    for (k in 1:K) {
      idx <- idx + 1L

      if (n_h == 0) {
        results[[idx]] <- data.frame(
          history_stratum = h, k = k,
          mu_hat = NA, se = NA, ci_lo = NA, ci_hi = NA,
          n_rows = 0L, n_subjects = 0L
        )
        next
      }

      # Stratum-level mean of predicted CIF
      pred_k <- cif_pred[h_mask, k]

      # Subject-clustered mean and SE
      pid_means <- tapply(pred_k, pids_h, mean, na.rm = TRUE)
      n_sub     <- length(pid_means)
      mu_hat    <- mean(pid_means, na.rm = TRUE)
      se_sub    <- sqrt(var(pid_means, na.rm = TRUE) / n_sub)

      results[[idx]] <- data.frame(
        history_stratum = h,
        k        = k,
        mu_hat   = mu_hat,
        se       = se_sub,
        ci_lo    = mu_hat - 1.96 * se_sub,
        ci_hi    = mu_hat + 1.96 * se_sub,
        n_rows   = n_h,
        n_subjects = n_sub
      )
    }
  }

  bind_rows(results)
}


# =============================================================================
# SIMULATION FUNCTION: ONE REPLICATE
# =============================================================================

run_one_rep <- function(rep_id, n, estimator = "Proposed-DR") {

  seed_val <- rep_id * 1000 + n + 4000  # offset to avoid seed collision with block1
  set.seed(seed_val)

  # ---- 1. Generate data ----
  event_data <- generate_olmc_data(
    n            = n,
    K            = K,
    lambda0_rec  = LAMBDA0_REC,
    lambda0_D    = LAMBDA0_D,
    frailty_var  = FRAILTY_VAR,
    beta_rec     = BETA_REC,
    beta_D       = BETA_D,
    censor_type  = "independent",
    censor_param = CENSOR_RATE,
    max_follow   = 3.0,
    history_effects = HISTORY_EFFECTS,
    history_on_rec  = TRUE,
    history_on_D    = TRUE
  )

  if (is.null(event_data) || nrow(event_data) == 0) {
    warning("Empty event data at rep ", rep_id, ", n=", n)
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

  # ---- 3. Stratum distribution (for kill criterion) ----
  stratum_counts <- table(lm_data$history_stratum)
  n_total_rows   <- nrow(lm_data)
  n_h1plus       <- sum(stratum_counts[c("H1", "H2", "H3")], na.rm = TRUE)
  frac_h1plus    <- n_h1plus / n_total_rows

  # ---- 4. Fit estimator ----
  dr_results <- tryCatch({
    if (estimator == "Proposed-DR") {
      cross_fit_dr(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic"
      )
    } else if (estimator == "Fine-Gray") {
      fit_fine_gray(lm_data, K = K)
    } else if (estimator == "CS-Cox-noHist") {
      fit_cs_cox_nohist(lm_data, K = K)
    } else if (estimator == "Baseline-only") {
      fit_baseline_only(lm_data, K = K)
    } else {
      stop("Unknown estimator: ", estimator)
    }
  }, error = function(e) {
    warning("Estimation failed rep ", rep_id, ", estimator=", estimator, ": ", e$message)
    NULL
  })

  if (is.null(dr_results)) return(NULL)

  # ---- 5. Evaluate against ground truth ----
  eval_df <- evaluate_one_rep(dr_results, GROUND_TRUTH)
  eval_df$rep            <- rep_id
  eval_df$n              <- n
  eval_df$estimator      <- estimator
  eval_df$seed           <- seed_val
  eval_df$frac_h1plus    <- frac_h1plus
  eval_df$n_total_rows   <- n_total_rows

  # Add stratum counts
  for (h in c("H0", "H1", "H2", "H3")) {
    eval_df[[paste0("n_rows_", h)]] <- as.integer(stratum_counts[h])
  }

  eval_df
}


# "all" estimators path
run_all_estimators <- function(rep_id, n) {
  ests <- c("Proposed-DR", "Fine-Gray", "CS-Cox-noHist", "Baseline-only")
  results <- lapply(ests, function(est) {
    cat(sprintf("  rep=%d n=%d est=%s\n", rep_id, n, est))
    run_one_rep(rep_id, n, estimator = est)
  })
  bind_rows(results)
}

# =============================================================================
# MAIN SIMULATION LOOP
# =============================================================================

output_dir <- file.path(script_dir, "results", "block4")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat(sprintf("Starting Block 4 simulation | n=%d | reps %d to %d\n",
            N_SIM, REP_START, REP_START + N_REPS - 1))
cat(sprintf("Output directory: %s\n\n", output_dir))

all_results <- vector("list", N_REPS)

for (i in seq_len(N_REPS)) {
  rep_id <- REP_START + i - 1
  cat(sprintf("[%d/%d] rep=%d n=%d ... ", i, N_REPS, rep_id, N_SIM))
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
  sprintf("block4_est%s_reps%d-%d.csv",
          gsub("[^A-Za-z0-9_-]", "", ESTIMATOR),
          REP_START, REP_START + N_REPS - 1)
)
write.csv(results_df, file = out_file, row.names = FALSE)
cat(sprintf("\nSaved %d rows to %s\n", nrow(results_df), out_file))

# =============================================================================
# SUMMARY AND KILL CRITERION CHECKS
# =============================================================================

if (nrow(results_df) > 0) {

  # ---- Kill criterion 1: fraction of H1+ rows ----
  frac_h1plus_avg <- mean(results_df$frac_h1plus, na.rm = TRUE)
  cat(sprintf(
    "\n--- Kill criterion 1: fraction of H1+ rows = %.3f (threshold: >= 0.25) ---\n",
    frac_h1plus_avg
  ))
  if (frac_h1plus_avg < 0.25) {
    cat("  FAIL: < 25%% of landmark rows have prior events.\n")
    cat("  History dependence cannot be evaluated. Simulation design needs revision.\n")
  } else {
    cat(sprintf("  PASS: %.1f%% of landmark rows have prior events.\n",
                frac_h1plus_avg * 100))
  }

  # ---- Kill criterion 2: history effect on next type ----
  # Check if proposed DR shows different mu_k across strata
  proposed_res <- results_df %>% filter(estimator == "Proposed-DR")
  if (nrow(proposed_res) > 0) {
    strata_mu <- proposed_res %>%
      group_by(history_stratum, k) %>%
      summarise(mu_hat_mean = mean(mu_hat, na.rm = TRUE), .groups = "drop") %>%
      pivot_wider(names_from = history_stratum, values_from = mu_hat_mean)

    cat("\n--- Kill criterion 2: history effect on mu_k (Proposed-DR) ---\n")
    print(as.data.frame(strata_mu), digits = 4)

    # Check if mu_k varies across strata
    h0_vals <- proposed_res %>%
      filter(history_stratum == "H0") %>%
      group_by(k) %>% summarise(mu_h0 = mean(mu_hat, na.rm = TRUE), .groups = "drop")
    h1plus_vals <- proposed_res %>%
      filter(history_stratum != "H0") %>%
      group_by(k) %>% summarise(mu_other = mean(mu_hat, na.rm = TRUE), .groups = "drop")
    merged_check <- merge(h0_vals, h1plus_vals, by = "k")
    max_diff <- max(abs(merged_check$mu_h0 - merged_check$mu_other), na.rm = TRUE)
    cat(sprintf("  Max |mu_k(H0) - mu_k(H1+)| = %.4f\n", max_diff))
    if (max_diff < 0.005) {
      cat("  WARNING: History has negligible effect on next type distribution.\n")
    } else {
      cat("  PASS: History meaningfully affects next type probabilities.\n")
    }
  }

  # ---- Main comparison: bias and coverage by estimator and stratum ----
  cat("\n--- Bias and coverage by estimator and stratum ---\n")
  summary_df <- results_df %>%
    group_by(estimator, history_stratum, k) %>%
    summarise(
      n_reps      = n(),
      mu_true     = mean(mu_true, na.rm = TRUE),
      bias        = mean(bias, na.rm = TRUE),
      rmse        = sqrt(mean(sq_err, na.rm = TRUE)),
      coverage_95 = mean(cover_95, na.rm = TRUE),
      .groups     = "drop"
    ) %>%
    arrange(estimator, history_stratum, k)

  print(as.data.frame(summary_df), digits = 4)

  # ---- Focus: H1+ strata comparison (key finding) ----
  cat("\n--- KEY COMPARISON: H1+ strata only ---\n")
  h1plus_summary <- results_df %>%
    filter(history_stratum %in% c("H1", "H2", "H3")) %>%
    group_by(estimator) %>%
    summarise(
      n_evals     = n(),
      mean_bias   = mean(bias, na.rm = TRUE),
      mean_absbias = mean(abs(bias), na.rm = TRUE),
      rmse        = sqrt(mean(sq_err, na.rm = TRUE)),
      coverage_95 = mean(cover_95, na.rm = TRUE),
      .groups     = "drop"
    ) %>%
    arrange(mean_absbias)

  print(as.data.frame(h1plus_summary), digits = 4)

  cat("\nExpected finding: CR models are miscalibrated for H1+ strata;\n")
  cat("Proposed-DR remains calibrated because it accounts for history.\n")

  # ---- Calibration by stratum for each estimator ----
  cat("\n--- Calibration: mean |bias| by estimator and stratum ---\n")
  calib_summary <- results_df %>%
    group_by(estimator, history_stratum) %>%
    summarise(
      mean_absbias = mean(abs(bias), na.rm = TRUE),
      coverage_95  = mean(cover_95, na.rm = TRUE),
      .groups      = "drop"
    ) %>%
    arrange(history_stratum, estimator)

  print(as.data.frame(calib_summary), digits = 4)
}
