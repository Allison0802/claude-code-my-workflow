# =============================================================================
# functions_olmc.R
# Core data generation and landmark transformation for OLMC project
#
# Method: Cross-fitted doubly robust estimator for
#   mu_k(h) = P(T_s^N <= w, J_s = k, T_s^N < T_s^D | H_s = h)
# Target venue: Biometrics
# Last Updated: 2026-03-20
# =============================================================================

library(tidyverse)
library(survival)

# =============================================================================
# DATA GENERATION
# =============================================================================

#' Generate OLMC simulation data
#'
#' Simulates K competing recurrent event types plus an absorbing terminal death
#' event, with optional shared log-normal frailty and history-dependent hazards.
#'
#' @param n           Number of subjects
#' @param K           Number of recurrent event types (default 3; use 2 for Block 1)
#' @param lambda0_rec Length-K vector of baseline recurrent event hazards (per year)
#' @param lambda0_D   Scalar baseline death hazard (per year)
#' @param frailty_var Log-normal frailty variance sigma^2 (0 = no frailty)
#' @param beta_rec    K x p matrix of log-HRs for recurrent types (rows = types)
#' @param beta_D      Length-p vector of log-HRs for death
#' @param censor_type "independent" (exponential) or "history" (history-dependent)
#' @param censor_param For "independent": exponential rate; for "history": list with
#'                    base_rate and history_coef vector
#' @param max_follow  Maximum follow-up in years (administrative censoring)
#' @param history_effects List: count_effect, gap_effect, last_type_effect (log-HR)
#'                        Applied only when censor_type = "history" or force_history = TRUE
#' @param history_on_rec Logical: apply history effects to recurrent event hazards
#' @param history_on_D  Logical: apply history effects to death hazard
#'
#' @return data.frame with columns:
#'   pid, event_time, event_type (0=censor, 1..K=recurrent, K+1=death),
#'   obs_end (min(T_D, C_i)), died, z, x, x2, x3 (covariates),
#'   gamma_i (frailty, for oracle use)
generate_olmc_data <- function(
  n,
  K               = 3,
  lambda0_rec     = rep(0.4, K),
  lambda0_D       = 0.08,
  frailty_var     = 0.5,
  beta_rec        = matrix(c(0.5, -0.3, 0.2, -0.2,
                             -0.3, 0.4, -0.1, 0.3,
                             0.2, -0.2, 0.4, -0.1)[1:(K*4)],
                           nrow = K, ncol = 4, byrow = TRUE),
  beta_D          = c(0.3, -0.2, 0.1, 0.0),
  censor_type     = "independent",
  censor_param    = 0.25,
  max_follow      = 3.0,
  history_effects = list(count_effect   =  0.10,
                         gap_effect     = -0.05,
                         last_type_same =  0.20),
  history_on_rec  = FALSE,
  history_on_D    = FALSE
) {

  stopifnot(length(lambda0_rec) == K)
  stopifnot(nrow(beta_rec) == K)
  p <- ncol(beta_rec)
  stopifnot(length(beta_D) == p)

  result_list <- vector("list", n)

  for (pid in 1:n) {

    # ---- Covariates ----
    z  <- rbinom(1, 1, 0.5)
    x  <- runif(1, 0, 1)
    x2 <- rnorm(1, 0, 1)
    x3 <- rnorm(1, 0, 1)
    covs <- c(z, x, x2, x3)[1:p]

    # ---- Frailty ----
    if (frailty_var > 0) {
      gamma_i <- exp(rnorm(1, mean = -frailty_var / 2, sd = sqrt(frailty_var)))
    } else {
      gamma_i <- 1.0
    }

    # ---- Administrative censoring ----
    if (censor_type == "independent") {
      C_admin <- rexp(1, rate = censor_param)
    } else {
      # History-dependent: base rate modified by covariate score
      base_rate <- censor_param$base_rate
      cov_score <- sum(censor_param$history_coef * covs)
      C_admin   <- rexp(1, rate = base_rate * exp(cov_score))
    }
    C_i <- min(C_admin, max_follow)

    # ---- Simulate interleaved event process ----
    event_times <- numeric(0)
    event_types <- integer(0)   # 1..K = recurrent, K+1 = death

    current_time  <- 0.0
    n_events      <- rep(0L, K)   # count by type
    last_evt_time <- rep(NA_real_, K)
    last_evt_type <- 0L
    total_events  <- 0L
    alive         <- TRUE

    while (alive && current_time < C_i) {

      # Compute type-k recurrent hazards at current_time
      h_rec <- numeric(K)
      for (k in 1:K) {
        lp_k <- sum(beta_rec[k, ] * covs)

        if (history_on_rec) {
          lp_k <- lp_k + history_effects$count_effect * total_events
          if (!is.na(last_evt_time[k])) {
            gap_yr <- current_time - last_evt_time[k]
            lp_k   <- lp_k + history_effects$gap_effect * gap_yr * 12  # in months
          }
          if (last_evt_type == k && total_events > 0L)
            lp_k <- lp_k + history_effects$last_type_same
        }

        lp_k <- min(lp_k, 10)  # cap to prevent overflow from count feedback
        h_rec[k] <- max(gamma_i * lambda0_rec[k] * exp(lp_k), 1e-10)
      }

      # Death hazard
      lp_D <- sum(beta_D * covs)
      if (history_on_D)
        lp_D <- lp_D + history_effects$count_effect * 0.5 * total_events
      lp_D <- min(lp_D, 10)  # cap to prevent overflow
      h_D <- max(gamma_i * lambda0_D * exp(lp_D), 1e-10)

      # Total hazard -> time to next event
      h_total     <- sum(h_rec) + h_D
      dt          <- rexp(1, rate = h_total)
      next_time   <- current_time + dt

      if (next_time >= C_i) break  # censored

      # Which event?
      probs   <- c(h_rec, h_D) / h_total
      evt_idx <- sample.int(K + 1L, 1L, prob = probs)

      event_times <- c(event_times, next_time)
      event_types <- c(event_types, evt_idx)

      if (evt_idx == K + 1L) {
        alive <- FALSE  # death: absorbing
      } else {
        # Update history
        k             <- evt_idx
        n_events[k]   <- n_events[k] + 1L
        last_evt_time[k] <- next_time
        last_evt_type <- k
        total_events  <- total_events + 1L
        current_time  <- next_time
      }
    }

    # ---- Build subject event table ----
    obs_end <- if (!alive) max(event_times) else C_i
    died    <- !alive

    n_events_sub <- length(event_times)

    if (n_events_sub == 0) {
      # Only censoring / no events
      sub_df <- data.frame(
        pid        = pid,
        event_time = C_i,
        event_type = 0L,
        obs_end    = C_i,
        died       = FALSE,
        z = z, x = x, x2 = x2, x3 = x3,
        gamma_i    = gamma_i
      )
    } else {
      sub_df <- data.frame(
        pid        = pid,
        event_time = c(event_times, obs_end),
        event_type = c(event_types, if (died) NA_integer_ else 0L),
        obs_end    = obs_end,
        died       = died,
        z = z, x = x, x2 = x2, x3 = x3,
        gamma_i    = gamma_i
      )
      # Drop the duplicated terminal row for death (event already recorded)
      if (died) sub_df <- sub_df[!is.na(sub_df$event_type), ]
      # Re-add clean terminal row
      terminal <- data.frame(
        pid        = pid,
        event_time = obs_end,
        event_type = if (died) K + 1L else 0L,
        obs_end    = obs_end,
        died       = died,
        z = z, x = x, x2 = x2, x3 = x3,
        gamma_i    = gamma_i
      )
      # Keep only recurrent events + terminal
      rec_rows <- sub_df[sub_df$event_type %in% 1:K, ]
      sub_df   <- rbind(rec_rows, terminal)
    }

    result_list[[pid]] <- sub_df
  }

  bind_rows(result_list)
}


# =============================================================================
# LANDMARK DATASET BUILDER
# =============================================================================

#' Build post-landmark dataset for OLMC
#'
#' For each (subject, landmark_s) pair where the subject is at risk at s
#' (i.e., obs_end > s), extract the post-landmark outcome quantities needed
#' for the DR estimator.
#'
#' @param event_data  data.frame from generate_olmc_data()
#' @param landmarks   numeric vector of landmark times in years
#'                    (default: quarterly at 0.5, 1.0, ..., 3.0)
#' @param w           prediction window width in years (default 0.5 = 180 days)
#' @param K           number of recurrent event types
#'
#' @return data.frame with one row per (subject, landmark) pair at risk, columns:
#'   pid, landmark_s, n_prior_total, n_prior_type[1..K], gap_since_last_yr,
#'   gap_since_last_type[1..K]_yr, last_event_type, z, x, x2, x3, gamma_i,
#'   T_sN (time to next recurrent event from s, capped at w+eps),
#'   J_s (type of next recurrent event, NA if none),
#'   T_sD (time to death from s, w+1 if no death in [s, s+w]),
#'   C_si (residual censoring from s),
#'   tau_i (min(T_sN, T_sD, C_si, w)),
#'   delta_N (I(T_sN <= w, T_sN < T_sD, T_sN < C_si)),
#'   delta_Nk[1..K] (type-specific indicators),
#'   obs_in_window (whether outcome fully observed: tau_i = T_sN or T_sD),
#'   history_stratum (H0/H1/H2/H3)
build_landmark_dataset <- function(
  event_data,
  landmarks = seq(0.5, 3.0, by = 0.5),
  w         = 0.5,
  K         = 3
) {

  pids <- unique(event_data$pid)
  out_list <- vector("list", length(pids) * length(landmarks))
  idx <- 0L

  for (pid in pids) {
    sub <- event_data[event_data$pid == pid, ]

    # Subject-level info
    obs_end <- sub$obs_end[1]
    died    <- sub$died[1]
    covs    <- sub[1, c("z", "x", "x2", "x3", "gamma_i"), drop = FALSE]

    # Death time (Inf if not observed to die)
    T_D_abs <- if (died) obs_end else Inf

    # All recurrent event times and types (excludes terminal row)
    rec_rows   <- sub[sub$event_type %in% 1:K, ]
    rec_times  <- rec_rows$event_time
    rec_types  <- rec_rows$event_type

    for (s in landmarks) {
      # Subject must be at risk at s (obs_end > s, not yet dead at s)
      if (obs_end <= s) next
      if (T_D_abs <= s) next

      idx <- idx + 1L

      # ---- History up to s ----
      past_rec   <- rec_times[rec_times <= s]
      past_types <- rec_types[rec_times <= s]

      n_prior_total <- length(past_rec)
      n_prior_type  <- tabulate(past_types, nbins = K)

      # Time since last event by type (NA if none)
      gap_by_type <- numeric(K)
      for (k in 1:K) {
        last_k <- max(past_rec[past_types == k], -Inf)
        gap_by_type[k] <- if (is.finite(last_k)) s - last_k else NA_real_
      }

      # Overall gap since last event (any type)
      last_any_time <- if (n_prior_total > 0) max(past_rec) else NA_real_
      gap_since_last_yr <- if (!is.na(last_any_time)) s - last_any_time else NA_real_

      # Type of most recent event
      last_event_type <- if (n_prior_total > 0) past_types[which.max(past_rec)] else 0L

      # ---- Post-landmark outcomes ----
      # Next recurrent event after s (within [s, obs_end])
      future_rec   <- rec_times[rec_times > s]
      future_types <- rec_types[rec_times > s]

      if (length(future_rec) > 0) {
        next_evt_abs  <- min(future_rec)
        next_evt_type <- future_types[which.min(future_rec)]
        T_sN          <- next_evt_abs - s  # relative to s
      } else {
        next_evt_abs  <- Inf
        next_evt_type <- NA_integer_
        T_sN          <- obs_end - s       # at least censored at obs_end - s
      }

      # Time to death from s (relative)
      T_sD <- if (died) T_D_abs - s else Inf

      # Residual censoring from s
      C_si <- obs_end - s  # obs_end = min(T_D_abs, C_i_abs)

      # Stopping time in window
      tau_i <- min(T_sN, T_sD, C_si, w)

      # Event indicator: did a recurrent event occur first, before death/censoring/w?
      delta_N <- as.integer(
        T_sN <= w && T_sN < T_sD && T_sN < C_si
      )
      J_s <- if (delta_N == 1L) next_evt_type else NA_integer_

      # Type-specific indicators
      delta_Nk <- as.integer(delta_N == 1L & seq_len(K) == J_s)
      if (delta_N == 0L) delta_Nk <- rep(0L, K)

      # Build row
      row_df <- data.frame(
        pid            = pid,
        landmark_s     = s,
        n_prior_total  = n_prior_total,
        last_event_type = last_event_type,
        gap_since_last_yr = gap_since_last_yr
      )

      # Prior counts by type
      for (k in 1:K) {
        row_df[[paste0("n_prior_type", k)]] <- n_prior_type[k]
      }

      # Gap since last event by type
      for (k in 1:K) {
        row_df[[paste0("gap_type", k, "_yr")]] <- gap_by_type[k]
      }

      # Covariates
      row_df <- cbind(row_df, covs)

      # Post-landmark outcomes
      row_df$T_sN   <- T_sN
      row_df$J_s    <- J_s
      row_df$T_sD   <- T_sD
      row_df$C_si   <- C_si
      row_df$tau_i  <- tau_i
      row_df$delta_N <- delta_N

      for (k in 1:K) {
        row_df[[paste0("delta_N", k)]] <- delta_Nk[k]
      }

      out_list[[idx]] <- row_df
    }
  }

  lm_data <- bind_rows(out_list[1:idx])

  # ---- History strata ----
  lm_data <- classify_history_stratum(lm_data)

  lm_data
}


#' Classify landmark rows into history strata H0-H3
#'
#' H0: No prior events (baseline prediction)
#' H1: Exactly 1 prior event (any type), within 6 months
#' H2: Mixed history, >= 2 prior events of at least 2 different types
#' H3: High-burden, >= 3 total recent events (gap_since_last_yr <= 0.5)
#'
#' Note: strata are mutually exclusive, checked in order H3 -> H2 -> H1 -> H0.
classify_history_stratum <- function(lm_data) {

  n   <- nrow(lm_data)
  str <- rep("H0", n)

  # H1: exactly 1 prior event, gap <= 6 months
  h1 <- lm_data$n_prior_total == 1 &
        !is.na(lm_data$gap_since_last_yr) &
        lm_data$gap_since_last_yr <= 0.5
  str[h1] <- "H1"

  # H2: >= 2 prior events of >= 2 different types
  n_types_present <- function(row) {
    k_cols <- grep("^n_prior_type[0-9]+$", names(lm_data), value = TRUE)
    sum(lm_data[row, k_cols] > 0)
  }
  type_counts <- apply(
    lm_data[, grep("^n_prior_type[0-9]+$", names(lm_data)), drop = FALSE],
    1, function(x) sum(x > 0)
  )
  h2 <- lm_data$n_prior_total >= 2 & type_counts >= 2
  str[h2] <- "H2"

  # H3: >= 3 recent events (gap_since_last_yr <= 0.5 implies at least one recent)
  #     and >= 3 total prior events
  h3 <- lm_data$n_prior_total >= 3 &
        !is.na(lm_data$gap_since_last_yr) &
        lm_data$gap_since_last_yr <= 0.5
  str[h3] <- "H3"

  lm_data$history_stratum <- factor(str, levels = c("H0", "H1", "H2", "H3"))
  lm_data
}


# =============================================================================
# HISTORY FEATURE VECTOR (for nuisance models)
# =============================================================================

#' Extract covariate matrix for nuisance model fitting
#'
#' Returns a matrix suitable for regression, including baseline covariates,
#' history summary features, and landmark time.
#'
#' @param lm_data  landmark dataset from build_landmark_dataset()
#' @param K        number of event types
#' @param include_landmark_time  include landmark_s as a feature
get_nuisance_covariates <- function(lm_data, K = 3, include_landmark_time = TRUE) {
  base_cols <- c("z", "x", "x2", "x3")
  hist_cols <- c(
    "n_prior_total",
    "gap_since_last_yr",
    paste0("n_prior_type", 1:K),
    paste0("gap_type", 1:K, "_yr")
  )

  # Fill NA gap features with 0 (no prior event = gap irrelevant, set to 0)
  for (col in hist_cols) {
    if (col %in% names(lm_data)) {
      lm_data[[col]][is.na(lm_data[[col]])] <- 0
    }
  }

  cols <- c(base_cols, hist_cols)
  if (include_landmark_time) cols <- c(cols, "landmark_s")

  # Keep only columns that exist
  cols <- cols[cols %in% names(lm_data)]

  X <- as.matrix(lm_data[, cols, drop = FALSE])
  X
}
