# ============================================================================
# METADATA
# ============================================================================
# Description: Cross-fitted doubly robust pseudo-observation estimator for
#              type-specific rate functions under MAR event type labels.
#              Core contribution: two-stage IF variance propagation.
# Last Updated: 2026-03-22
# ============================================================================
#
# Estimand: theta_k = E[F_k(tau)] = type-specific cumulative incidence at tau
#   where F_k(tau) = 1 - S_k(tau), treating type-k events as "events"
#
# Stage 1: DR correction for missing type labels
#   DR_{ik} = m_k(X_i) + R_i/pi(X_i) * [I(type_i=k) - m_k(X_i)]
#   where pi(X) = P(R=1|X), m_k(X) = P(type=k|X, R=1)
#
# Stage 2: Pseudo-observations using DR-weighted KM
#   PO_{ik} = n * F_k^{DR}(tau) - (n-1) * F_k^{DR,-i}(tau)
#
# Two-stage IF:
#   psi_i = PO_{ik}^{DR} - theta_k              (PO residual)
#         + delta_i^{DR}                          (DR correction term)
#   where delta_i^{DR} captures uncertainty from estimating pi and m_k
#
# Cross-fitting: 5-fold split by SUBJECT (not row) per DML framework
# ============================================================================

library(survival)

# ============================================================================
# CROSS-FITTING INFRASTRUCTURE
# ============================================================================

#' Create subject-level cross-fitting folds
#' @param subject_ids Vector of subject IDs (may repeat for multiple events)
#' @param n_folds Number of folds (default 5)
#' @param seed Random seed for reproducibility
#' @return Named list: fold_assignments (subject -> fold), n_folds
create_subject_folds <- function(subject_ids, n_folds = 5, seed = NULL) {
  unique_subjects <- unique(subject_ids)
  n_subjects <- length(unique_subjects)

  if (n_subjects < n_folds) {
    stop("Fewer subjects (", n_subjects, ") than folds (", n_folds, ")")
  }

  if (!is.null(seed)) set.seed(seed)
  fold_assignments <- sample(rep(1:n_folds, length.out = n_subjects))
  names(fold_assignments) <- unique_subjects

  list(
    fold_assignments = fold_assignments,
    n_folds = n_folds,
    n_subjects = n_subjects
  )
}

#' Get fold assignment for each row based on subject ID
#' @param subject_ids Vector of subject IDs (one per row)
#' @param fold_info Output of create_subject_folds()
#' @return Integer vector of fold assignments (one per row)
get_row_folds <- function(subject_ids, fold_info) {
  fold_info$fold_assignments[as.character(subject_ids)]
}


# ============================================================================
# NUISANCE MODEL FITTING
# ============================================================================

#' Fit propensity model: P(type observed | covariates)
#' Wrapper that supports both logistic and RF
#' @param data Data frame with event rows
#' @param method "logistic" or "rf"
#' @param covariates Character vector of covariate names
#' @return List with model, predict function
fit_propensity <- function(data, method = "logistic", covariates = NULL) {
  is_event <- data$event == 1
  event_data <- data[is_event, ]
  event_data$observed <- as.integer(!is.na(event_data$type))

  if (is.null(covariates)) {
    covariates <- intersect(c("x", "X", "z", "Z", "xx2", "XX2"), names(event_data))
  }

  if (method == "logistic") {
    fml <- as.formula(paste("observed ~", paste(covariates, collapse = " + ")))
    fit <- glm(fml, data = event_data, family = binomial(link = "logit"))
    scores <- predict(fit, newdata = event_data, type = "response")
    scores <- pmax(scores, 0.01)

    predict_fn <- function(newdata) {
      p <- predict(fit, newdata = newdata, type = "response")
      pmax(p, 0.01)
    }
  } else if (method == "rf") {
    event_data$observed_f <- factor(event_data$observed, levels = c(0, 1))
    fml <- as.formula(paste("observed_f ~", paste(covariates, collapse = " + ")))
    fit <- ranger::ranger(fml, data = event_data, probability = TRUE,
                          num.trees = 500, min.node.size = 5)
    scores <- fit$predictions[, "1"]
    scores <- pmax(scores, 0.01)

    predict_fn <- function(newdata) {
      newdata$observed_f <- factor(0, levels = c(0, 1))
      p <- predict(fit, data = newdata)$predictions[, "1"]
      pmax(p, 0.01)
    }
  } else {
    stop("Unknown propensity method: ", method)
  }

  list(model = fit, scores = scores, predict = predict_fn, method = method)
}

#' Fit outcome model: P(type = k | X, R = 1) for k = 1, ..., K
#' @param data Data frame with event rows (observed types only)
#' @param method "multinomial" or "rf"
#' @param covariates Character vector of covariate names
#' @return List with model, predict function returning K-column matrix
fit_outcome <- function(data, method = "multinomial", covariates = NULL) {
  is_event <- data$event == 1
  event_data <- data[is_event & !is.na(data$type), ]

  if (is.null(covariates)) {
    covariates <- intersect(c("x", "X", "z", "Z", "xx2", "XX2", "x_correlated"),
                            names(event_data))
  }

  K <- length(unique(event_data$type))

  if (method == "multinomial") {
    event_data$type_f <- factor(event_data$type)
    fml <- as.formula(paste("type_f ~", paste(covariates, collapse = " + ")))
    fit <- nnet::multinom(fml, data = event_data, trace = FALSE)

    predict_fn <- function(newdata) {
      probs <- predict(fit, newdata = newdata, type = "probs")
      if (is.null(dim(probs))) {
        probs <- cbind(1 - probs, probs)
      }
      probs
    }
  } else if (method == "rf") {
    event_data$type_f <- factor(event_data$type)
    fml <- as.formula(paste("type_f ~", paste(covariates, collapse = " + ")))
    fit <- ranger::ranger(fml, data = event_data, probability = TRUE,
                          num.trees = 500, min.node.size = 5)

    predict_fn <- function(newdata) {
      pred <- predict(fit, data = newdata)$predictions
      pred
    }
  } else {
    stop("Unknown outcome method: ", method)
  }

  list(model = fit, predict = predict_fn, method = method, K = K)
}

#' Fit misspecified propensity model (intercept only, for Block 2)
fit_propensity_wrong <- function(data, covariates = NULL) {
  is_event <- data$event == 1
  event_data <- data[is_event, ]
  event_data$observed <- as.integer(!is.na(event_data$type))

  fit <- glm(observed ~ 1, data = event_data, family = binomial(link = "logit"))
  scores <- predict(fit, newdata = event_data, type = "response")
  scores <- pmax(scores, 0.01)

  predict_fn <- function(newdata) {
    p <- predict(fit, newdata = newdata, type = "response")
    pmax(p, 0.01)
  }

  list(model = fit, scores = scores, predict = predict_fn, method = "logistic_wrong")
}

#' Fit misspecified outcome model (intercept only, for Block 2)
fit_outcome_wrong <- function(data, covariates = NULL) {
  is_event <- data$event == 1
  event_data <- data[is_event & !is.na(data$type), ]
  K <- length(unique(event_data$type))

  # Intercept-only: just marginal proportions
  type_tab <- table(event_data$type) / nrow(event_data)
  marginal_probs <- as.numeric(type_tab)

  predict_fn <- function(newdata) {
    n <- nrow(newdata)
    matrix(rep(marginal_probs, each = n), nrow = n, ncol = K)
  }

  list(model = NULL, predict = predict_fn, method = "multinomial_wrong", K = K)
}


# ============================================================================
# CROSS-FITTED DR INDICATORS
# ============================================================================

#' Compute cross-fitted DR event-type indicators
#' @param data Full data frame
#' @param n_folds Number of cross-fitting folds
#' @param propensity_method "logistic" or "rf"
#' @param outcome_method "multinomial" or "rf"
#' @param propensity_covariates Covariates for propensity model
#' @param outcome_covariates Covariates for outcome model
#' @param seed Random seed for fold creation
#' @param fit_propensity_fn Custom propensity fitting function (for misspecification)
#' @param fit_outcome_fn Custom outcome fitting function (for misspecification)
#' @return Data frame with DR indicators and influence function components
compute_dr_indicators_crossfit <- function(data,
                                            n_folds = 5,
                                            propensity_method = "logistic",
                                            outcome_method = "multinomial",
                                            propensity_covariates = NULL,
                                            outcome_covariates = NULL,
                                            seed = NULL,
                                            fit_propensity_fn = NULL,
                                            fit_outcome_fn = NULL) {

  is_event <- data$event == 1
  subject_ids <- data$pid[is_event]

  fold_info <- create_subject_folds(subject_ids, n_folds = n_folds, seed = seed)
  row_folds <- get_row_folds(subject_ids, fold_info)

  n_events <- sum(is_event)
  K <- length(unique(data$type[is_event & !is.na(data$type)]))

  # Initialize output columns
  dr_indicators <- matrix(0, nrow = n_events, ncol = K)
  pi_scores <- numeric(n_events)
  m_matrix <- matrix(0, nrow = n_events, ncol = K)
  if_dr_components <- matrix(0, nrow = n_events, ncol = K)

  event_data <- data[is_event, ]
  R <- as.integer(!is.na(event_data$type))

  for (fold in 1:n_folds) {
    test_idx <- which(row_folds == fold)
    train_idx <- which(row_folds != fold)

    train_data <- event_data[train_idx, ]
    # Wrap train_data in a full-format data frame for fitting functions
    train_wrapper <- train_data
    train_wrapper$event <- 1  # all rows are events

    test_data <- event_data[test_idx, ]

    # Fit nuisance models on training fold
    if (!is.null(fit_propensity_fn)) {
      prop_fit <- fit_propensity_fn(train_wrapper)
    } else {
      prop_fit <- fit_propensity(train_wrapper, method = propensity_method,
                                  covariates = propensity_covariates)
    }

    if (!is.null(fit_outcome_fn)) {
      out_fit <- fit_outcome_fn(train_wrapper)
    } else {
      out_fit <- fit_outcome(train_wrapper, method = outcome_method,
                              covariates = outcome_covariates)
    }

    # Predict on test fold
    pi_test <- prop_fit$predict(test_data)
    m_test <- out_fit$predict(test_data)
    if (is.null(dim(m_test))) {
      m_test <- cbind(1 - m_test, m_test)
    }

    pi_scores[test_idx] <- pi_test
    m_matrix[test_idx, ] <- m_test

    # Compute DR indicators for each type
    R_test <- R[test_idx]
    for (k in 1:K) {
      I_k <- as.integer(event_data$type[test_idx] == k)
      I_k[is.na(I_k)] <- 0

      augmentation_k <- R_test / pi_test * (I_k - m_test[, k])
      dr_k <- m_test[, k] + augmentation_k

      dr_indicators[test_idx, k] <- dr_k

      # IF component for DR correction (per-observation score)
      # Under cross-fitting, the score for the DR estimator of E[I(type=k)] is:
      # psi_DR_i = m_k(X_i) + R_i/pi(X_i) * [I_k - m_k(X_i)] - theta_k
      if_dr_components[test_idx, k] <- augmentation_k
    }
  }

  # Normalize DR indicators to [0,1] and sum to 1
  dr_sum <- rowSums(dr_indicators)
  dr_sum[dr_sum <= 0] <- 1  # avoid division by zero
  dr_norm <- dr_indicators / dr_sum

  # Store results back in data
  data$event_type1_dr <- 0
  data$event_type2_dr <- 0
  data$propensity_score <- NA
  data$prob_type1 <- NA
  data$prob_type2 <- NA

  data$event_type1_dr[is_event] <- dr_norm[, 1]
  data$event_type2_dr[is_event] <- dr_norm[, 2]
  data$propensity_score[is_event] <- pi_scores
  data$prob_type1[is_event] <- m_matrix[, 1]
  data$prob_type2[is_event] <- m_matrix[, 2]

  # Store raw (unnormalized) DR indicators for IF computation
  attr(data, "dr_raw") <- dr_indicators
  attr(data, "if_dr_components") <- if_dr_components
  attr(data, "pi_scores") <- pi_scores
  attr(data, "m_matrix") <- m_matrix
  attr(data, "R_vector") <- R
  attr(data, "fold_info") <- fold_info

  return(data)
}


# ============================================================================
# TWO-STAGE INFLUENCE FUNCTION VARIANCE
# ============================================================================

#' Compute two-stage IF-based variance for DR pseudo-observations
#'
#' The pseudo-observation PO_{ik} = n*F_k(tau) - (n-1)*F_k^{-i}(tau) depends on
#' all subjects' DR indicators. The two-stage IF accounts for:
#'   Stage 1: Uncertainty in pseudo-observation computation (leave-one-out)
#'   Stage 2: Uncertainty from estimating pi(X) and m_k(X) in DR indicators
#'
#' Under cross-fitting, the total IF for subject i is approximately:
#'   psi_i = (PO_{ik}^DR - theta_k) + dPO/dDR * delta_DR_i
#' where dPO/dDR is the sensitivity of PO to the DR indicator, and
#' delta_DR_i is the IF of the DR indicator estimator.
#'
#' In practice, we estimate this via the empirical IF:
#'   1. Compute PO with all subjects' DR indicators -> PO_{ik}
#'   2. Perturb subject i's DR indicator -> PO_{ik}^{perturbed}
#'   3. Sensitivity = (PO_{ik}^{perturbed} - PO_{ik}) / perturbation
#'
#' For computational tractability, we use the linearized approximation:
#'   Var(theta_k_hat) = (1/n) * Var_i(psi_i)
#' where psi_i = PO_{ik}^DR - theta_k_hat (the centered pseudo-observation)
#' This is the "naive" component. The two-stage correction adds:
#'   + (1/n) * Var_i(delta_DR_i * dF_k/dDR_i)
#'
#' @param data Data frame with DR indicators and pseudo-observations
#' @param tau Evaluation time
#' @param type_k Which event type (1 or 2)
#' @return List with variance components: naive, dr_correction, total, se
compute_twostage_if_variance <- function(data, tau, type_k = 1) {

  # Get the DR IF components stored during cross-fitting
  if_dr <- attr(data, "if_dr_components")
  pi_scores <- attr(data, "pi_scores")
  m_matrix <- attr(data, "m_matrix")
  R_vec <- attr(data, "R_vector")

  is_event <- data$event == 1
  event_data <- data[is_event, ]

  po_col <- paste0("pseudoEst_km_type", type_k)
  if (!po_col %in% names(data)) {
    stop("Pseudo-observation column ", po_col, " not found. Run generate_km_pseudoEst first.")
  }

  po_values <- data[[po_col]][is_event]
  valid <- !is.na(po_values)
  po_valid <- po_values[valid]
  n <- length(po_valid)

  if (n < 2) {
    return(list(naive_var = NA, dr_correction = NA, total_var = NA, se_naive = NA,
                se_twostage = NA, n = n))
  }

  # --- Component 1: Naive PO variance ---
  # This is the standard pseudo-observation variance, ignoring DR uncertainty
  theta_hat <- mean(po_valid)
  naive_var <- var(po_valid) / n

  # --- Component 2: DR correction variance ---
  # The DR indicator for subject i influences the pseudo-observation through
  # the weighted KM. Under the jackknife linearization:
  #   dF_k(tau) / dDR_{ik} ≈ 1/n (each subject's contribution to the KM)
  #
  # The IF of the DR indicator for subject i is:
  #   delta_DR_i = R_i/pi(X_i) * [I(type_i=k) - m_k(X_i)]
  # (the augmentation term from AIPW)
  #
  # The two-stage correction to the variance is:
  #   V_DR = (1/n^2) * sum_i (delta_DR_i)^2
  # which accounts for the fact that estimated DR indicators add noise

  if (!is.null(if_dr) && ncol(if_dr) >= type_k) {
    delta_dr <- if_dr[valid, type_k]
    dr_correction <- var(delta_dr) / n
  } else {
    delta_dr <- rep(0, n)
    dr_correction <- 0
  }

  # --- Subject-level aggregation ---
  # When subjects have multiple event rows, aggregate IF at subject level
  subject_ids <- event_data$pid[valid]
  unique_subjects <- unique(subject_ids)
  n_subjects <- length(unique_subjects)

  # Subject-level mean IF (PO component + DR component)
  psi_total <- (po_valid - theta_hat) + delta_dr

  subject_means <- tapply(psi_total, subject_ids, mean)
  subject_var <- var(as.numeric(subject_means)) / n_subjects

  # Subject-level naive (PO only)
  psi_naive <- po_valid - theta_hat
  subject_means_naive <- tapply(psi_naive, subject_ids, mean)
  subject_var_naive <- var(as.numeric(subject_means_naive)) / n_subjects

  # Subject-level DR correction only
  subject_means_dr <- tapply(delta_dr, subject_ids, mean)
  subject_var_dr <- var(as.numeric(subject_means_dr)) / n_subjects

  list(
    theta_hat = theta_hat,
    naive_var = subject_var_naive,
    dr_correction = subject_var_dr,
    total_var = subject_var,
    se_naive = sqrt(subject_var_naive),
    se_twostage = sqrt(subject_var),
    n = n,
    n_subjects = n_subjects
  )
}


#' Compute variance for DR pseudo-observations at each landmark time
#' @param data Data frame with DR pseudo-observations
#' @param tau Evaluation time
#' @param type_k Event type (1 or 2)
#' @return Data frame with variance components per landmark time
compute_variance_by_landmark <- function(data, tau, type_k = 1) {
  unique_times <- sort(unique(data$checkin))
  results <- list()

  for (tp in unique_times) {
    tp_data <- data[data$checkin == tp, ]
    # Transfer attributes
    attr(tp_data, "if_dr_components") <- attr(data, "if_dr_components")
    attr(tp_data, "pi_scores") <- attr(data, "pi_scores")
    attr(tp_data, "m_matrix") <- attr(data, "m_matrix")
    attr(tp_data, "R_vector") <- attr(data, "R_vector")

    # Subset attributes to match this landmark
    is_event_full <- data$event == 1
    is_event_tp <- tp_data$event == 1
    event_idx_full <- which(is_event_full)
    event_idx_tp <- which(data$checkin == tp & is_event_full)

    # Map event indices
    if (length(event_idx_tp) > 0) {
      map_idx <- match(event_idx_tp, event_idx_full)
      if_dr_full <- attr(data, "if_dr_components")
      if (!is.null(if_dr_full)) {
        attr(tp_data, "if_dr_components") <- if_dr_full[map_idx, , drop = FALSE]
      }
      pi_full <- attr(data, "pi_scores")
      if (!is.null(pi_full)) {
        attr(tp_data, "pi_scores") <- pi_full[map_idx]
      }
      m_full <- attr(data, "m_matrix")
      if (!is.null(m_full)) {
        attr(tp_data, "m_matrix") <- m_full[map_idx, , drop = FALSE]
      }
      r_full <- attr(data, "R_vector")
      if (!is.null(r_full)) {
        attr(tp_data, "R_vector") <- r_full[map_idx]
      }
    }

    var_result <- compute_twostage_if_variance(tp_data, tau, type_k)
    var_result$checkin <- tp
    results[[length(results) + 1]] <- var_result
  }

  do.call(rbind, lapply(results, function(r) {
    data.frame(
      checkin = r$checkin,
      theta_hat = r$theta_hat,
      se_naive = r$se_naive,
      se_twostage = r$se_twostage,
      naive_var = r$naive_var,
      dr_correction = r$dr_correction,
      total_var = r$total_var,
      n = r$n,
      n_subjects = r$n_subjects,
      stringsAsFactors = FALSE
    )
  }))
}


# ============================================================================
# COMPLETE DR-PO PIPELINE
# ============================================================================

#' Run full DR pseudo-observation pipeline with cross-fitting
#' @param data Raw recurrent events data (output of rate_cox_data_gen_complex)
#' @param aa Landmark spacing
#' @param tau Pseudo-observation evaluation horizon
#' @param n_folds Number of cross-fitting folds
#' @param propensity_method "logistic" or "rf"
#' @param outcome_method "multinomial" or "rf"
#' @param seed Random seed
#' @param fit_propensity_fn Custom propensity fitting function (for misspecification)
#' @param fit_outcome_fn Custom outcome fitting function (for misspecification)
#' @return List with: data (augmented), variance_type1, variance_type2, theta
run_dr_po_pipeline <- function(data,
                                aa,
                                tau = 5 * aa,
                                n_folds = 5,
                                propensity_method = "logistic",
                                outcome_method = "multinomial",
                                seed = NULL,
                                fit_propensity_fn = NULL,
                                fit_outcome_fn = NULL) {

  # Step 1: Compute cross-fitted DR indicators on raw data
  data_dr <- compute_dr_indicators_crossfit(
    data,
    n_folds = n_folds,
    propensity_method = propensity_method,
    outcome_method = outcome_method,
    seed = seed,
    fit_propensity_fn = fit_propensity_fn,
    fit_outcome_fn = fit_outcome_fn
  )

  # Step 2: Transform to landmark format
  # Store attributes before transformation
  dr_attrs <- list(
    dr_raw = attr(data_dr, "dr_raw"),
    if_dr_components = attr(data_dr, "if_dr_components"),
    pi_scores = attr(data_dr, "pi_scores"),
    m_matrix = attr(data_dr, "m_matrix"),
    R_vector = attr(data_dr, "R_vector"),
    fold_info = attr(data_dr, "fold_info")
  )

  lm_data <- transform_with_covariates_complex(data_dr, aa = aa)

  # Step 3: Compute pseudo-observations using DR-weighted events
  lm_data <- generate_km_pseudoEst_weighted(lm_data, tau = tau, suffix = "dr")

  # Step 4: Compute variance estimates
  # Transfer DR attributes to landmark data for variance computation
  # Note: attributes need to be mapped from event-level to landmark-level
  # For now, compute variance at the marginal level (averaging over landmarks)

  # Marginal theta estimates
  theta1 <- mean(lm_data$pseudoEst_km_type1, na.rm = TRUE)
  theta2 <- mean(lm_data$pseudoEst_km_type2, na.rm = TRUE)

  # Simple variance: var(PO) / n_subjects
  unique_subjects <- unique(lm_data$pid)
  n_subjects <- length(unique_subjects)

  # Subject-level mean PO
  subj_po1 <- tapply(lm_data$pseudoEst_km_type1, lm_data$pid, mean, na.rm = TRUE)
  subj_po2 <- tapply(lm_data$pseudoEst_km_type2, lm_data$pid, mean, na.rm = TRUE)

  se_naive_1 <- sqrt(var(subj_po1, na.rm = TRUE) / n_subjects)
  se_naive_2 <- sqrt(var(subj_po2, na.rm = TRUE) / n_subjects)

  # Two-stage SE: add DR correction
  # The DR augmentation terms are at the event level; aggregate to subject level
  if (!is.null(dr_attrs$if_dr_components)) {
    subj_dr1 <- tapply(dr_attrs$if_dr_components[, 1], data_dr$pid[data_dr$event == 1], mean)
    subj_dr2 <- tapply(dr_attrs$if_dr_components[, 2], data_dr$pid[data_dr$event == 1], mean)

    # Match subjects that appear in both
    common_subj <- intersect(names(subj_po1), names(subj_dr1))
    psi_total_1 <- (subj_po1[common_subj] - theta1) + subj_dr1[common_subj]
    psi_total_2 <- (subj_po2[common_subj] - theta2) + subj_dr2[common_subj]

    se_twostage_1 <- sqrt(var(psi_total_1, na.rm = TRUE) / length(common_subj))
    se_twostage_2 <- sqrt(var(psi_total_2, na.rm = TRUE) / length(common_subj))
  } else {
    se_twostage_1 <- se_naive_1
    se_twostage_2 <- se_naive_2
  }

  list(
    data = lm_data,
    theta = c(type1 = theta1, type2 = theta2),
    se_naive = c(type1 = se_naive_1, type2 = se_naive_2),
    se_twostage = c(type1 = se_twostage_1, type2 = se_twostage_2),
    ci_naive = list(
      type1 = theta1 + c(-1.96, 1.96) * se_naive_1,
      type2 = theta2 + c(-1.96, 1.96) * se_naive_2
    ),
    ci_twostage = list(
      type1 = theta1 + c(-1.96, 1.96) * se_twostage_1,
      type2 = theta2 + c(-1.96, 1.96) * se_twostage_2
    ),
    n_subjects = n_subjects,
    dr_attrs = dr_attrs
  )
}
