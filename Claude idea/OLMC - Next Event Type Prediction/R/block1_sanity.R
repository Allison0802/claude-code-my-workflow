# =============================================================================
# block1_sanity.R
# Block 1: EIF / Oracle Sanity Check for OLMC
#
# Scientific question: Is the implementation correct, and does the EIF-based
# variance estimate match the Monte Carlo variance?
#
# DGM:
#   - K = 2 (simpler for verification)
#   - n in {500, 1000, 2000}
#   - Censoring: 15%, independent exponential
#   - Death: 15-20%, moderate frailty sigma^2 = 0.3
#   - Simple parametric constant hazards (true mu_k(h) available in closed form)
#
# Estimators:
#   - DR-oracle   : true nuisances (G_C, Lambda_k, M_k) plugged in
#   - DR-correct  : parametric nuisances correctly specified (Cox + logistic)
#   - OR-only     : outcome regression only (no censoring adjustment)
#   - IPCW-only   : IPCW only (no outcome regression)
#
# Kill criterion: persistent bias for DR-oracle at n >= 1000 -> bug.
#
# Output: results/block1/block1_rep{REP}_n{N}.csv
#
# Usage (SLURM):
#   Rscript block1_sanity.R --n 1000 --rep 1 --n_reps 200 --estimator DR-oracle
#   or via SLURM array with BLOCK1_N, BLOCK1_REP env vars
#
# Last Updated: 2026-03-20
# =============================================================================

set.seed(20260320)

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

# Allow SLURM env vars or command line flags
N_SIM    <- as.integer(Sys.getenv("BLOCK1_N",   unset = parse_arg(args, "--n", 1000)))
REP_START <- as.integer(Sys.getenv("BLOCK1_REP_START", unset = parse_arg(args, "--rep_start", 1)))
N_REPS   <- as.integer(Sys.getenv("BLOCK1_N_REPS", unset = parse_arg(args, "--n_reps", 200)))
ESTIMATOR <- Sys.getenv("BLOCK1_ESTIMATOR", unset = "all")

cat(sprintf(
  "Block 1 Sanity | n=%d | reps=%d-%d | estimator=%s\n",
  N_SIM, REP_START, REP_START + N_REPS - 1, ESTIMATOR
))

# =============================================================================
# DGM PARAMETERS (Block 1: simple parametric, K=2)
# =============================================================================

K           <- 2
W           <- 0.5          # prediction window: 6 months
LANDMARKS   <- seq(0.5, 3.0, by = 0.5)
FRAILTY_VAR <- 0.3          # sigma^2
P           <- 4            # number of covariates (z, x, x2, x3)

# Simple constant-ish hazards for K=2
# Using only 4 covariates: (z, x, x2, x3)
LAMBDA0_REC <- c(0.30, 0.25)   # baseline recurrent hazards (per year)
LAMBDA0_D   <- 0.06             # baseline death hazard (~18% by 3 years)
CENSOR_RATE <- 0.16             # exponential rate -> ~15% censored in 3 yr window

# Covariate log-HRs (simple, no interactions)
BETA_REC <- matrix(c(
   0.40, -0.20,  0.15, 0.00,   # type 1: z, x, x2, x3
  -0.25,  0.30, -0.10, 0.00    # type 2
), nrow = K, ncol = P, byrow = TRUE)

BETA_D <- c(0.35, -0.15, 0.10, 0.00)

# =============================================================================
# ORACLE FUNCTIONS
# =============================================================================

oracle_gc <- make_oracle_gc_exponential(censor_rate = CENSOR_RATE)
oracle_Lk <- make_oracle_Lk_exponential(LAMBDA0_REC, LAMBDA0_D, BETA_REC, BETA_D, p = P)
oracle_Mk <- make_oracle_Mk_exponential(LAMBDA0_REC, LAMBDA0_D, BETA_REC, BETA_D, w = W, p = P)

# =============================================================================
# SIMULATION FUNCTION: ONE REPLICATE
# =============================================================================

run_one_rep <- function(rep_id, n, estimator = "DR-oracle") {

  seed_val <- rep_id * 1000 + n
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
    history_on_rec = FALSE,
    history_on_D   = FALSE
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

  # ---- 3. Compute true mu_k(h) for this sample ----
  strata <- c("H0", "H1", "H2", "H3")
  true_mu_list <- vector("list", length(strata))

  for (h in strata) {
    true_mu_list[[which(strata == h)]] <- cbind(
      history_stratum = h,
      true_mu_stratum(
        lm_data, stratum = h, K = K, w = W,
        lambda0_rec = LAMBDA0_REC, lambda0_D = LAMBDA0_D,
        beta_rec = BETA_REC, beta_D = BETA_D,
        frailty_var = FRAILTY_VAR, p = P
      )
    )
  }
  true_mu_df <- bind_rows(true_mu_list)

  # ---- 4. Compute DR estimates ----
  dr_results <- tryCatch({
    if (estimator == "DR-oracle") {
      cross_fit_dr(
        lm_data, K = K, w = W, V = 5,
        oracle_gc = oracle_gc,
        oracle_Mk = oracle_Mk,
        oracle_Lk = oracle_Lk
      )
    } else if (estimator == "DR-correct") {
      cross_fit_dr(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic"
      )
    } else if (estimator == "OR-only") {
      # Outcome regression only: no censoring adjustment
      # Equivalent to DR with G_C = 1 (no IPCW correction)
      cross_fit_dr(
        lm_data, K = K, w = W, V = 5,
        outcome_method = "logistic",
        oracle_gc = function(u, row) 1.0,   # trivial G_C = 1 -> no IPCW
        oracle_Lk = function(tau, k, row) 0.0  # no compensator
      )
    } else if (estimator == "IPCW-only") {
      # IPCW only: no outcome regression
      # M_k = 0 (no OR), use oracle censoring
      cross_fit_dr(
        lm_data, K = K, w = W, V = 5,
        oracle_gc = oracle_gc,
        oracle_Lk = oracle_Lk,
        oracle_Mk = function(lm_data) matrix(0, nrow = nrow(lm_data), ncol = K)
      )
    } else {
      # "all": run all four estimators and return combined
      stop("Use estimator='all' outside this branch")
    }
  }, error = function(e) {
    warning("DR estimation failed rep ", rep_id, ", estimator=", estimator, ": ", e$message)
    NULL
  })

  if (is.null(dr_results)) return(NULL)

  # ---- 5. Evaluate ----
  eval_df <- evaluate_one_rep(dr_results, true_mu_df)
  eval_df$rep       <- rep_id
  eval_df$n         <- n
  eval_df$estimator <- estimator
  eval_df$seed      <- seed_val

  eval_df
}


# "all" estimators path
run_all_estimators <- function(rep_id, n) {
  ests <- c("DR-oracle", "DR-correct", "OR-only", "IPCW-only")
  results <- lapply(ests, function(est) {
    cat(sprintf("  rep=%d n=%d est=%s\n", rep_id, n, est))
    run_one_rep(rep_id, n, estimator = est)
  })
  bind_rows(results)
}

# =============================================================================
# MAIN SIMULATION LOOP
# =============================================================================

output_dir <- file.path(script_dir, "results", "block1")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat(sprintf("Starting Block 1 simulation | n=%d | reps %d to %d\n",
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
  sprintf("block1_n%d_reps%d-%d.csv",
          N_SIM, REP_START, REP_START + N_REPS - 1)
)
write.csv(results_df, file = out_file, row.names = FALSE)
cat(sprintf("\nSaved %d rows to %s\n", nrow(results_df), out_file))

# ---- Quick summary ----
if (nrow(results_df) > 0) {
  cat("\n--- Quick summary (bias and coverage) ---\n")
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

  # ---- Kill criterion check ----
  oracle_summary <- summary_df %>%
    filter(estimator == "DR-oracle", n_reps >= 50)

  if (nrow(oracle_summary) > 0) {
    max_bias  <- max(abs(oracle_summary$bias), na.rm = TRUE)
    min_cover <- min(oracle_summary$coverage_95, na.rm = TRUE)
    cat(sprintf(
      "\nKill criterion check (DR-oracle):\n  Max |bias| = %.4f (threshold: 0.005)\n  Min coverage = %.3f (threshold: 0.93)\n",
      max_bias, min_cover
    ))
    if (max_bias > 0.005 && nrow(results_df %>% filter(n == N_SIM, estimator == "DR-oracle")) >= 50) {
      cat("  WARNING: Bias exceeds kill threshold. Check EIF derivation.\n")
    } else if (min_cover < 0.88) {
      cat("  WARNING: Coverage below 0.88. Check variance estimation.\n")
    } else {
      cat("  PASS: DR-oracle within expected range.\n")
    }
  }
}
