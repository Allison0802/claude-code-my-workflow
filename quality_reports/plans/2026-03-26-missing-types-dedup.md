# Missing Types Structural Deduplication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce ~14,000 lines across 9 simulation scripts to ~2,500 by extracting shared infrastructure into two new files, leaving each of the 7 single-method scripts as a ~20-line thin wrapper.

**Architecture:** Create `simulation_engine.R` (lib setup, package loading, memory monitoring, config parsing, chunked parallel engine, results summary) and `simulation_runner.R` (imputation dispatch + shared RF/MERF/Cox pipeline). The 7 single-method scripts (CCA, IPW, IPW-RF, RPM, RPM-RF, DR, DR-RF) are reduced to thin wrappers that source those two files and run. The 2 GRF scripts keep their own `run_comprehensive_simulation()` but source `simulation_engine.R` to eliminate their duplicated setup.

**Tech Stack:** R 4.4, SLURM/Longleaf HPC, packages: ranger, randomForest, SAEforest, LongituRF, survival, grf, nnet, tidyverse

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| CREATE | `Missing Types/simulation_engine.R` | Lib paths, pkg loading, memory monitoring, `configure_simulation()`, `run_chunked_simulations()`, `save_and_summarize_results()` |
| CREATE | `Missing Types/simulation_runner.R` | `compute_event_history_features()`, `apply_imputation_phase_a()`, `apply_imputation_phase_b()`, `apply_pseudo_observations()`, `run_comprehensive_simulation()` (RF/MERF/Cox pipeline) |
| REWRITE | `missing_types_method_comparison_cca.R` | 20-line thin wrapper (source engine + runner, set method, run) |
| REWRITE | `missing_types_method_comparison_ipw.R` | Same thin wrapper pattern |
| REWRITE | `missing_types_method_comparison_ipw_rf.R` | Same thin wrapper pattern |
| REWRITE | `missing_types_method_comparison_rpm.R` | Same thin wrapper pattern |
| REWRITE | `missing_types_method_comparison_rpm_rf.R` | Same thin wrapper pattern |
| REWRITE | `missing_types_method_comparison_dr.R` | Same thin wrapper pattern |
| REWRITE | `missing_types_method_comparison_dr_rf.R` | Same thin wrapper pattern |
| UPDATE | `missing_types_method_comparison_grf_type_cov_all_methods.R` | Source `simulation_engine.R`; remove duplicated setup/config/engine blocks |
| UPDATE | `missing_types_method_comparison_grf_stratified_all_methods.R` | Same GRF update pattern |

**Invariant:** SLURM submit scripts (`submit_missing_types_*.sh`) and `run_missing_types_all_methods.sh` do NOT change — they invoke the same script filenames.

---

## Task 1: Create simulation_engine.R

**Files:**
- Create: `Missing Types/simulation_engine.R`

- [ ] **Step 1: Write simulation_engine.R**

```r
# ============================================================================
# METADATA
# ============================================================================
# Description: Shared infrastructure for Missing Types simulation studies.
#              Provides Longleaf library setup, package loading, memory
#              monitoring, configuration parsing, chunked parallel processing,
#              and results summary printing. Source this file before
#              functions.R and simulation_runner.R.
# Last Updated: 2026-03-26
# ============================================================================

# ============================================================================
# LONGLEAF LIBRARY SETUP  (runs on source)
# ============================================================================

r_version_major_minor <- paste(R.version$major,
  strsplit(R.version$minor, "\\.")[[1]][1], sep = ".")
r_version_full <- paste(R.version$major, R.version$minor, sep = ".")

cat("Detected R version:", R.version.string, "\n")
cat("R version (major.minor):", r_version_major_minor, "\n")

user_lib_paths   <- paste0("/nas/longleaf/home/yumeiy/R/x86_64-pc-linux-gnu-library/",
                           r_version_major_minor)
system_lib_paths <- c(
  paste0("/nas/longleaf/rhel9/apps/r/", r_version_full, "/lib64/R/library"),
  paste0("/nas/longleaf/rhel8/apps/r/", r_version_full, "/lib64/R/library")
)

lib_paths <- .libPaths()
for (path in system_lib_paths) {
  if (dir.exists(path) && !path %in% lib_paths) {
    lib_paths <- c(lib_paths, path)
    cat("✓ Found system library path:", path, "\n")
  }
}
for (path in rev(user_lib_paths)) {
  if (dir.exists(path)) {
    lib_paths <- c(path, lib_paths[!lib_paths %in% path])
    cat("✓ Found user library path:", path, "\n")
  }
}
.libPaths(unique(lib_paths))
cat("Using library paths:\n")
for (i in seq_along(.libPaths())) cat(sprintf("  [%d] %s\n", i, .libPaths()[i]))
cat("\n")

# ============================================================================
# PACKAGE LOADING  (runs on source)
# ============================================================================

library(Hmisc)
library(partykit)
library(parallel)
library(cmprsk)
library(survival)
library(tidyverse)
library(LongituRF)
library(SAEforest)
library(randomForest)
library(nnet)

tryCatch({
  library(ranger)
  cat("✓ ranger loaded\n")
}, error = function(e) {
  stop("ranger is required: ", e$message)
})

tryCatch({
  library(grf)
  cat("✓ grf loaded\n")
}, error = function(e) {
  stop("grf is required: ", e$message)
})

# ============================================================================
# MEMORY MONITORING
# ============================================================================

monitor_memory <- function(label = "") {
  mem_used  <- gc()[2, 2]
  mem_limit <- as.numeric(Sys.getenv("SLURM_MEM_PER_NODE", "0")) / 1024
  if (mem_limit > 0) {
    cat(sprintf("[MEMORY %s] Using %.2f GB / %.2f GB (%.1f%%)\n",
                label, mem_used/1024, mem_limit,
                (mem_used/1024) / mem_limit * 100))
  } else {
    cat(sprintf("[MEMORY %s] Using %.2f GB\n", label, mem_used/1024))
  }
  return(mem_used)
}

aggressive_gc <- function() gc(full = TRUE)

# ============================================================================
# SIMULATION CONFIGURATION
# ============================================================================

#' Parse env-vars, build scenario list, validate requested scenario.
#' @param imputation_methods character vector of method names for this script
#' @return list: scenario, n_sims, chunk_size, save_interval,
#'               n_trees_grf, temp_dir, is_test_run
configure_simulation <- function(imputation_methods) {
  is_test_run <- Sys.getenv("TEST_RUN") == "true"

  n_sims_env <- Sys.getenv("N_SIMS", "")
  if (n_sims_env != "") {
    n_sims <- as.numeric(n_sims_env)
    if (is.na(n_sims) || n_sims < 1) {
      warning("Invalid N_SIMS, using default")
      n_sims <- if (is_test_run) 2 else 500
    }
  } else {
    n_sims <- if (is_test_run) 2 else 500
  }

  scenario_name <- Sys.getenv("SCENARIO_NAME")
  if (scenario_name == "") stop("SCENARIO_NAME environment variable not set")

  chunk_size    <- as.numeric(Sys.getenv("CHUNK_SIZE",    "10"))
  save_interval <- as.numeric(Sys.getenv("SAVE_INTERVAL", "50"))
  n_trees_grf   <- as.integer(Sys.getenv("N_TREES_GRF",
                                         ifelse(is_test_run, "100", "500")))

  cat("=====================================================\n")
  cat("SIMULATION CONFIGURATION\n")
  cat("=====================================================\n")
  cat("Scenario:", scenario_name, "\n")
  cat("Total simulations:", n_sims, "\n")
  cat("Chunk size:", chunk_size, "\n")
  cat("Save interval:", save_interval, "\n")
  cat("GRF trees:", n_trees_grf, "\n")
  cat("=====================================================\n\n")

  monitor_memory("STARTUP")

  base_missing_scenario <- list(
    name          = "missing_base",
    n             = if (is_test_run) 100 else 500,
    f.alpha       = 0,
    r01           = 0.20,
    r02           = 0.15,
    rho           = 0.3,
    beta          = c(1.5, 1.0, 1.2, 1.5, 0, 0, 0.5, 0.3),
    complex_params = c(1, 1, 1, 1),
    censor_max    = 4
  )

  scenarios <- list()
  for (m_pattern in c("MCAR", "MAR")) {
    for (m_pct in c(10, 20, 30, 50)) {
      for (i_method in imputation_methods) {
        s_name <- paste0("missing_", m_pattern, "_", m_pct, "pct_", i_method)
        scenarios[[s_name]] <- modifyList(base_missing_scenario, list(
          name             = s_name,
          missing_pattern  = m_pattern,
          missing_pct      = m_pct,
          imputation_method = i_method
        ))
      }
    }
  }

  scenario <- NULL
  for (s in scenarios) {
    if (s$name == scenario_name) { scenario <- s; break }
  }
  if (is.null(scenario)) stop("Scenario '", scenario_name, "' not found")

  if (!dir.exists("results_missing_types"))
    dir.create("results_missing_types", showWarnings = FALSE, recursive = TRUE)

  temp_dir <- file.path("results_missing_types", paste0("temp_", scenario$name))
  if (!dir.exists(temp_dir)) dir.create(temp_dir, recursive = TRUE)

  list(scenario = scenario, n_sims = n_sims, chunk_size = chunk_size,
       save_interval = save_interval, n_trees_grf = n_trees_grf,
       temp_dir = temp_dir, is_test_run = is_test_run)
}

# ============================================================================
# CHUNKED PARALLEL PROCESSING ENGINE
# ============================================================================

#' Run simulations in memory-efficient chunks using PSOCK parallel workers.
#' @param scenario   Scenario list (from configure_simulation)
#' @param n_sims     Total replicates
#' @param chunk_size Replicates per parallel batch
#' @param save_interval Save intermediate results every N replicates
#' @param extra_exports Additional object names to clusterExport (e.g. "n_trees_grf")
run_chunked_simulations <- function(scenario, n_sims, chunk_size,
                                    save_interval, extra_exports = c()) {
  slurm_cpus <- as.numeric(Sys.getenv("SLURM_CPUS_PER_TASK"))
  n_cores <- if (!is.na(slurm_cpus) && slurm_cpus > 0) {
    min(slurm_cpus, chunk_size)
  } else {
    min(detectCores() - 1, chunk_size)
  }

  cat(sprintf("\n=== CHUNKED PROCESSING SETUP ===\n"))
  cat(sprintf("Total simulations: %d\n", n_sims))
  cat(sprintf("Chunk size: %d\n", chunk_size))
  cat(sprintf("Cores per chunk: %d\n", n_cores))
  cat(sprintf("Number of chunks: %d\n", ceiling(n_sims / chunk_size)))
  cat("=====================================\n\n")

  monitor_memory("PRE-SIMULATION")

  all_results <- list()
  sim_seeds   <- 1:n_sims
  n_chunks    <- ceiling(n_sims / chunk_size)
  temp_dir    <- file.path("results_missing_types", paste0("temp_", scenario$name))

  for (chunk_idx in 1:n_chunks) {
    chunk_start <- (chunk_idx - 1) * chunk_size + 1
    chunk_end   <- min(chunk_idx * chunk_size, n_sims)
    chunk_seeds <- sim_seeds[chunk_start:chunk_end]

    cat(sprintf("\n╔═══════════════════════════════════════╗\n"))
    cat(sprintf("║ CHUNK %d/%d: Simulations %d-%d\n",
                chunk_idx, n_chunks, chunk_start, chunk_end))
    cat(sprintf("╚═══════════════════════════════════════╝\n\n"))
    monitor_memory(sprintf("CHUNK %d START", chunk_idx))

    chunk_results <- tryCatch({
      if (n_cores > 1 && length(chunk_seeds) > 1) {
        cl <- makeCluster(min(n_cores, length(chunk_seeds)), type = "PSOCK", outfile = "")
        main_lib_paths <- .libPaths()
        exports <- c("run_comprehensive_simulation", "scenario",
                     "main_lib_paths", extra_exports)
        clusterExport(cl, exports, envir = parent.frame())
        clusterEvalQ(cl, {
          if (!exists("cluster_packages_loaded", envir = .GlobalEnv)) {
            .libPaths(main_lib_paths)
            suppressMessages(suppressPackageStartupMessages({
              library(Hmisc); library(partykit); library(ranger)
              library(randomForest); library(cmprsk); library(survival)
              library(tidyverse); library(LongituRF); library(SAEforest)
              library(grf); library(nnet)
            }))
            source("functions.R")
            assign("cluster_packages_loaded", TRUE, envir = .GlobalEnv)
          }
        })
        cat(sprintf("  ✓ Cluster setup (%d workers)\n", min(n_cores, length(chunk_seeds))))
        results <- parLapply(cl, chunk_seeds, function(seed) {
          tryCatch({
            result <- run_comprehensive_simulation(scenario, seed = seed)
            gc(); return(result)
          }, error = function(e) {
            gc()
            return(list(success = FALSE,
                        error = paste("Worker error:", conditionMessage(e))))
          })
        })
        stopCluster(cl); rm(cl); aggressive_gc()
        results
      } else {
        cat("  Running chunk sequentially...\n")
        lapply(chunk_seeds, function(seed) {
          result <- tryCatch(
            run_comprehensive_simulation(scenario, seed = seed),
            error = function(e) list(success = FALSE, error = conditionMessage(e))
          )
          gc(); result
        })
      }
    }, error = function(e) {
      cat("  ERROR in chunk:", conditionMessage(e), "\n")
      lapply(chunk_seeds, function(seed)
        list(success = FALSE, error = paste("Chunk error:", conditionMessage(e))))
    })

    for (i in seq_along(chunk_seeds))
      all_results[[chunk_seeds[i]]] <- chunk_results[[i]]

    monitor_memory(sprintf("CHUNK %d END", chunk_idx))

    if (chunk_end %% save_interval == 0 || chunk_idx == n_chunks) {
      temp_file <- file.path(temp_dir, sprintf("results_up_to_%d.rds", chunk_end))
      saveRDS(all_results, temp_file)
      cat(sprintf("  ✓ Saved intermediate results (up to sim %d)\n", chunk_end))
    }

    rm(chunk_results); aggressive_gc()
    n_successful <- sum(sapply(all_results, function(x) x$success))
    cat(sprintf("\n  Progress: %d/%d simulations (%d successful)\n",
                length(all_results), n_sims, n_successful))
  }

  monitor_memory("POST-SIMULATION")
  return(all_results)
}

# ============================================================================
# RESULTS SAVING AND SUMMARY
# ============================================================================

#' Save final RDS, clean temp dir, print summary statistics.
save_and_summarize_results <- function(scenario_results, scenario, temp_dir) {
  successful_sims <- sum(sapply(scenario_results, function(x) x$success))
  cat(sprintf("\n╔══════════════════════════════════════════════════════════╗\n"))
  cat(sprintf("║  COMPLETED: %d/%d successful simulations\n",
              successful_sims, length(scenario_results)))
  cat(sprintf("╚══════════════════════════════════════════════════════════╝\n\n"))

  scenario_file <- file.path("results_missing_types",
    paste0("scenario_", scenario$name, "_comprehensive_results.rds"))
  saveRDS(scenario_results, scenario_file)
  cat(sprintf("✓ Saved final results to: %s\n", scenario_file))

  if (dir.exists(temp_dir)) { unlink(temp_dir, recursive = TRUE); cat("✓ Cleaned up temp files\n") }

  invisible(monitor_memory("FINAL"))
  cat("\n=== COMPREHENSIVE RESULTS SUMMARY ===\n")
  cat("Scenario:", scenario$name, "\n\n")

  successful_results <- Filter(Negate(is.null), lapply(scenario_results, function(x) {
    if (is.list(x) && isTRUE(x$success)) {
      res <- x; res$success <- NULL; res$error <- NULL; res$time_specific_results <- NULL
      as.data.frame(res, stringsAsFactors = FALSE)
    } else NULL
  }))
  cat(sprintf("Found %d successful result sets.\n", length(successful_results)))

  if (length(successful_results) == 0) {
    cat("No valid results for this scenario\n")
    return(invisible(NULL))
  }

  scenario_data <- do.call(rbind, successful_results)
  num_cols      <- sapply(scenario_data, is.numeric)
  means <- colMeans(scenario_data[, num_cols, drop = FALSE], na.rm = TRUE)
  sds   <- apply(scenario_data[, num_cols, drop = FALSE], 2, sd, na.rm = TRUE)

  cat("\nAA:", round(means["aa"], 3), "± ", round(sds["aa"], 3), "\n")
  cat("Tau:", round(means["tau"], 3), "± ", round(sds["tau"], 3), "\n")
  cat("\nEvent Rates:\n")
  cat("  Type 1:", round(means["event_rate1"], 4), "±", round(sds["event_rate1"], 4), "\n")
  cat("  Type 2:", round(means["event_rate2"], 4), "±", round(sds["event_rate2"], 4), "\n")

  if ("missing_pattern" %in% names(scenario_data)) {
    cat("\nMissingness:\n")
    if (length(unique(scenario_data$missing_pattern)) == 1)
      cat("  Pattern:", unique(scenario_data$missing_pattern)[1], "\n")
    if ("actual_missing_pct" %in% names(scenario_data))
      cat("  Actual %:", round(means["actual_missing_pct"], 2),
          "±", round(sds["actual_missing_pct"], 2), "\n")
    if ("imputation_method" %in% names(scenario_data) &&
        length(unique(scenario_data$imputation_method)) == 1)
      cat("  Method:", unique(scenario_data$imputation_method)[1], "\n")
  }

  cat("\n=== METHOD COMPARISON ===\n")
  print_ci <- function(label, m_name) {
    cc_val   <- if (m_name %in% names(means)) round(means[m_name], 3) else NA
    true_val <- if (paste0(m_name, "_true") %in% names(means))
      round(means[paste0(m_name, "_true")], 3) else NA
    cat(sprintf("  %-40s CC: %.3f  True: %.3f\n", label, cc_val, true_val))
  }
  cat("\nSTRATIFIED:\n")
  print_ci("RF Stratified Type 1",        "c_rf_strat_type1")
  print_ci("RF Stratified Type 2",        "c_rf_strat_type2")
  print_ci("MERFranger Stratified Type 1","c_merfranger_strat_type1")
  print_ci("MERFranger Stratified Type 2","c_merfranger_strat_type2")
  cat("\nTYPE-AS-COVARIATE:\n")
  print_ci("MERFranger Cov Type 1",       "c_merfranger_cov_type1")
  print_ci("MERFranger Cov Type 2",       "c_merfranger_cov_type2")
  print_ci("RF + Time Type 1",            "c_rf_time_type1")
  print_ci("RF + Time Type 2",            "c_rf_time_type2")
  cat("\nCOX PH + HISTORY:\n")
  print_ci("Cox PH Type 1",               "c_cox_hist_type1_landmark")
  print_ci("Cox PH Type 2",               "c_cox_hist_type2_landmark")

  aggressive_gc()
  cat("\n╔══════════════════════════════════════════════════════════╗\n")
  cat("║           SIMULATION COMPLETED SUCCESSFULLY              ║\n")
  cat("╚══════════════════════════════════════════════════════════╝\n")
}
```

- [ ] **Step 2: Verify simulation_engine.R sources cleanly (local)**

```bash
cd "Missing Types"
Rscript -e 'source("simulation_engine.R"); cat("OK\n")'
```

Expected: prints lib paths, package load messages, then `OK`. No errors.

- [ ] **Step 3: Commit**

```bash
cd "Missing Types"
git add simulation_engine.R
git commit -m "feat: add simulation_engine.R with shared setup, config, and parallel engine"
```

---

## Task 2: Create simulation_runner.R

**Files:**
- Create: `Missing Types/simulation_runner.R`

- [ ] **Step 1: Write simulation_runner.R — imputation helpers**

This file is sourced AFTER `simulation_engine.R` and `functions.R`. It defines the imputation dispatch functions and the shared `run_comprehensive_simulation()`.

```r
# ============================================================================
# METADATA
# ============================================================================
# Description: Shared simulation pipeline for RF/MERF/Cox methods with
#              imputation dispatch. Source after simulation_engine.R and
#              functions.R. Provides run_comprehensive_simulation() used by
#              all 7 single-method wrapper scripts.
# Last Updated: 2026-03-26
# ============================================================================

# ============================================================================
# IMPUTATION HELPERS
# ============================================================================

#' Compute event-history features on interval data (needed by RPM and DR).
#' Adds n_prior_type1, n_prior_type2, prev_event_type, time_since_last_type1/2.
compute_event_history_features <- function(data) {
  data <- data %>%
    arrange(pid, e.time) %>%
    group_by(pid) %>%
    mutate(
      n_prior_type1   = cumsum(lag(event == 1 & type == 1, default = FALSE)),
      n_prior_type2   = cumsum(lag(event == 1 & type == 2, default = FALSE)),
      prev_event_type = lag(ifelse(event == 1, type, NA_real_))
    ) %>%
    ungroup() %>%
    arrange(pid, e.time) %>%
    group_by(pid) %>%
    mutate(last_type1_time = NA_real_, last_type2_time = NA_real_) %>%
    ungroup()

  for (subj in unique(data$pid)) {
    idx <- which(data$pid == subj)
    last_t1 <- NA_real_; last_t2 <- NA_real_
    for (i in idx) {
      data$last_type1_time[i] <- last_t1
      data$last_type2_time[i] <- last_t2
      if (data$event[i] == 1 && !is.na(data$type[i])) {
        if (data$type[i] == 1) last_t1 <- data$e.time[i]
        if (data$type[i] == 2) last_t2 <- data$e.time[i]
      }
    }
  }

  data$time_since_last_type1 <- ifelse(is.na(data$last_type1_time), 0,
                                       data$e.time - data$last_type1_time)
  data$time_since_last_type2 <- ifelse(is.na(data$last_type2_time), 0,
                                       data$e.time - data$last_type2_time)
  data$n_prior_type1[is.na(data$n_prior_type1)] <- 0
  data$n_prior_type2[is.na(data$n_prior_type2)] <- 0
  data$prev_event_type[is.na(data$prev_event_type)] <- 0
  data$last_type1_time <- NULL
  data$last_type2_time <- NULL
  data
}

#' Phase A imputation: applied to interval data BEFORE landmark transformation.
#' Handles: complete_case (no-op), rpm, rpm_rf, dr, dr_rf.
#' Returns modified data plus diagnostics list.
apply_imputation_phase_a <- function(data, method, pattern, pct) {
  diag <- list(entropy = NA, mismatch_rate = NA, mean_prob_correct = NA,
               dr_propensity_mean = NA, rpm_aic = NA, rpm_convergence = NA)

  if (method == "complete_case" || pattern == "none" || pct == 0) {
    return(list(data = data, diag = diag))
  }

  if (method %in% c("rpm", "rpm_rf")) {
    cat(sprintf("\n=== Applying %s Imputation ===\n",
                ifelse(method == "rpm", "Rate Proportion Model", "RF-based RPM")))
    tryCatch({
      data    <- compute_event_history_features(data)
      rpm_fit <- if (method == "rpm") fit_rate_proportion_model(data)
                 else                 fit_rate_proportion_model_rf(data)
      data    <- if (method == "rpm") impute_event_types(data, rpm_fit)
                 else                 impute_event_types_rf(data, rpm_fit)
      if (method == "rpm") {
        diag$rpm_aic        <- rpm_fit$aic
        diag$rpm_convergence <- rpm_fit$convergence
      }
      is_miss <- data$event == 1 & !is.na(data$imputation_entropy)
      if (sum(is_miss) > 0) {
        diag$entropy <- mean(data$imputation_entropy[is_miss], na.rm = TRUE)
        if ("type_true" %in% names(data)) {
          has_truth <- is_miss & !is.na(data$type_true)
          if (sum(has_truth) > 0) {
            tv <- data$type_true[has_truth]; ti <- data$type_imputed[has_truth]
            p1 <- data$prob_type1[has_truth]; p2 <- data$prob_type2[has_truth]
            diag$mismatch_rate     <- mean(tv != ti, na.rm = TRUE)
            diag$mean_prob_correct <- mean(ifelse(tv == 1, p1, p2), na.rm = TRUE)
          }
        }
      }
      cat(sprintf("%s: entropy=%.3f, mismatch=%.1f%%\n",
                  toupper(method),
                  ifelse(is.na(diag$entropy), 0, diag$entropy),
                  100 * ifelse(is.na(diag$mismatch_rate), 0, diag$mismatch_rate)))
    }, error = function(e) {
      cat(method, "imputation failed:", e$message, "\n")
    })
  }

  if (method %in% c("dr", "dr_rf")) {
    cat(sprintf("\n=== Applying DR %s (AIPW) Imputation ===\n",
                ifelse(method == "dr", "(logistic)", "(RF)")))
    tryCatch({
      propensity_fit <- if (method == "dr") fit_propensity_model(data)
                        else                fit_propensity_model_rf(data)
      diag$dr_propensity_mean <- propensity_fit$mean_score
      data        <- compute_event_history_features(data)
      outcome_fit <- if (method == "dr") fit_rate_proportion_model(data)
                     else                fit_rate_proportion_model_rf(data)
      data        <- if (method == "dr") compute_dr_indicators(data, propensity_fit, outcome_fit)
                     else                compute_dr_indicators_rf(data, propensity_fit, outcome_fit)
      is_event <- data$event == 1
      if (sum(is_event) > 0) {
        diag$entropy <- mean(data$imputation_entropy[is_event], na.rm = TRUE)
        is_miss  <- is_event & is.na(data$type)
        if ("type_true" %in% names(data)) {
          has_truth <- is_miss & !is.na(data$type_true)
          if (sum(has_truth) > 0) {
            tv <- data$type_true[has_truth]; ti <- data$type_imputed[has_truth]
            p1 <- data$prob_type1[has_truth]; p2 <- data$prob_type2[has_truth]
            diag$mismatch_rate     <- mean(tv != ti, na.rm = TRUE)
            diag$mean_prob_correct <- mean(ifelse(tv == 1, p1, p2), na.rm = TRUE)
          }
        }
      }
      cat(sprintf("%s: propensity=%.3f, entropy=%.3f, mismatch=%.1f%%\n",
                  toupper(method),
                  ifelse(is.na(diag$dr_propensity_mean), 0, diag$dr_propensity_mean),
                  ifelse(is.na(diag$entropy), 0, diag$entropy),
                  100 * ifelse(is.na(diag$mismatch_rate), 0, diag$mismatch_rate)))
    }, error = function(e) {
      cat(method, "imputation failed:", e$message, "\n")
    })
  }

  list(data = data, diag = diag)
}

#' Phase B imputation: applied to transformed landmark data AFTER transformation.
#' Handles: ipw/ipw_rf weight computation, rpm/dr indicator propagation.
#' Returns modified transformed_data.
apply_imputation_phase_b <- function(transformed_data, data, method, pattern, pct) {
  if (pattern == "none" || pct == 0) return(transformed_data)

  # ---- IPW / IPW-RF: compute weights on landmark events ----
  if (method %in% c("ipw", "ipw_rf")) {
    cat(sprintf("\n=== Applying %s Weights (post-transform) ===\n",
                ifelse(method == "ipw", "IPW logistic", "IPW-RF")))
    transformed_data$observed   <- !(transformed_data$event == 1 & is.na(transformed_data$type))
    transformed_data$ipw_weight <- 1.0

    if (any(!transformed_data$observed[transformed_data$event == 1])) {
      event_rows_td <- transformed_data[transformed_data$event == 1, ]
      ipw_features  <- intersect(c("X", "Z"), names(event_rows_td))

      if (nrow(event_rows_td) >= 10 && length(ipw_features) > 0) {
        observed_vals <- event_rows_td$observed
        if (length(unique(observed_vals)) > 1) {
          tryCatch({
            event_indices <- which(transformed_data$event == 1)
            if (method == "ipw") {
              train_df <- event_rows_td[, ipw_features, drop = FALSE]
              train_df$observed <- observed_vals
              obs_model <- glm(as.formula(paste("observed ~",
                               paste(ipw_features, collapse = " + "))),
                               data = train_df, family = binomial(link = "logit"))
              pred_df       <- transformed_data[event_indices, ipw_features, drop = FALSE]
              prob_observed <- pmax(predict(obs_model, newdata = pred_df,
                                           type = "response"), 0.01)
            } else {
              train_df <- event_rows_td[, ipw_features, drop = FALSE]
              for (cn in names(train_df))
                if (is.numeric(train_df[[cn]])) train_df[[cn]][is.na(train_df[[cn]])] <- 0
              train_df$observed <- factor(observed_vals, levels = c(FALSE, TRUE))
              obs_model <- ranger::ranger(observed ~ ., data = train_df,
                                         probability = TRUE,
                                         num.trees = 500,
                                         mtry = length(ipw_features))
              pred_df <- transformed_data[event_indices, ipw_features, drop = FALSE]
              for (cn in names(pred_df))
                if (is.numeric(pred_df[[cn]])) pred_df[[cn]][is.na(pred_df[[cn]])] <- 0
              pred_probs <- predict(obs_model, data = pred_df)$predictions
              prob_col   <- if (is.matrix(pred_probs) && "TRUE" %in% colnames(pred_probs))
                              "TRUE" else ncol(pred_probs)
              prob_observed <- pmax(if (is.matrix(pred_probs))
                                      pred_probs[, prob_col] else pred_probs, 0.01)
            }

            transformed_data$ipw_weight[event_indices] <- 1.0 / prob_observed
            median_w <- median(transformed_data$ipw_weight[event_indices], na.rm = TRUE)
            transformed_data$ipw_weight[event_indices] <- pmin(
              transformed_data$ipw_weight[event_indices], 10 * median_w)
            cat(sprintf("%s: median_weight=%.3f\n", toupper(method), median_w))

          }, error = function(e) {
            cat(method, "weight computation failed:", e$message, "\n")
            transformed_data$ipw_weight[transformed_data$event == 1] <- 1.0
          })
        }
      }
    }
  }

  # ---- RPM / RPM-RF: propagate fractional indicators to landmark rows ----
  if (method %in% c("rpm", "rpm_rf") &&
      all(c("event_type1_rpm", "event_type2_rpm") %in% names(data))) {
    cat("\nPropagating RPM fractional indicators to landmark format...\n")
    transformed_data$event_type1_rpm <- 0
    transformed_data$event_type2_rpm <- 0

    # Pre-sort for efficient lookup
    event_data <- data[data$event == 1, c("pid", "e.time", "event_type1_rpm", "event_type2_rpm")]
    event_data <- event_data[order(event_data$pid, event_data$e.time), ]

    for (i in 1:nrow(transformed_data)) {
      subj_id      <- transformed_data$id[i]
      current_time <- transformed_data$checkin[i]
      subj_events  <- event_data[event_data$pid == subj_id & event_data$e.time > current_time, ]
      if (nrow(subj_events) > 0) {
        transformed_data$event_type1_rpm[i] <- subj_events$event_type1_rpm[1]
        transformed_data$event_type2_rpm[i] <- subj_events$event_type2_rpm[1]
      }
    }
    cat(sprintf("✓ Propagated RPM indicators to %d landmarks\n", nrow(transformed_data)))
  }

  # ---- DR / DR-RF: propagate DR indicators to landmark rows ----
  if (method %in% c("dr", "dr_rf") &&
      all(c("event_type1_dr", "event_type2_dr") %in% names(data))) {
    cat("\nPropagating DR indicators to landmark format...\n")
    transformed_data$event_type1_dr <- 0
    transformed_data$event_type2_dr <- 0

    event_data <- data[data$event == 1, c("pid", "e.time", "event_type1_dr", "event_type2_dr")]
    event_data <- event_data[order(event_data$pid, event_data$e.time), ]

    for (i in 1:nrow(transformed_data)) {
      subj_id      <- transformed_data$id[i]
      current_time <- transformed_data$checkin[i]
      subj_events  <- event_data[event_data$pid == subj_id & event_data$e.time > current_time, ]
      if (nrow(subj_events) > 0) {
        transformed_data$event_type1_dr[i] <- subj_events$event_type1_dr[1]
        transformed_data$event_type2_dr[i] <- subj_events$event_type2_dr[1]
      }
    }
    cat(sprintf("✓ Propagated DR indicators to %d landmarks\n", nrow(transformed_data)))
  }

  transformed_data
}

#' Generate pseudo-observations with method-appropriate estimator.
apply_pseudo_observations <- function(transformed_data, tau, method, pattern, pct) {
  if (method %in% c("rpm", "rpm_rf") && pattern != "none" && pct > 0 &&
      "event_type1_rpm" %in% names(transformed_data)) {
    cat("\nGenerating RPM-weighted KM pseudo-observations...\n")
    transformed_data <- generate_km_pseudoEst_weighted(transformed_data, tau, "rpm")
  } else if (method %in% c("dr", "dr_rf") && pattern != "none" && pct > 0 &&
             "event_type1_dr" %in% names(transformed_data)) {
    cat("\nGenerating DR-weighted KM pseudo-observations...\n")
    transformed_data <- generate_km_pseudoEst_weighted(transformed_data, tau, "dr")
  } else {
    transformed_data <- generate_km_pseudoEst(transformed_data, tau)
  }
  transformed_data <- generate_rmst_pseudoEst_stratified(transformed_data, tau)
  transformed_data
}
```

- [ ] **Step 2: Write simulation_runner.R — run_comprehensive_simulation()**

Append after the helpers above. The body is copied verbatim from `missing_types_method_comparison_cca.R` lines 224–1267 (the current `run_comprehensive_simulation` in that file), with three targeted modifications:

**Modification A** — Replace the CCA-specific imputation block (old lines 258-324) with dispatch calls:

```r
    # Step 2b: Apply missingness
    if (missing_pattern != "none" && missing_pct > 0) {
      if (missing_pattern == "MCAR") {
        data <- introduce_mcar_missingness(data, missing_pct)
      } else if (missing_pattern == "MAR") {
        data <- introduce_mar_missingness(data, missing_pct)
      }
    }
    data_original <- data
    data$observed_type <- !(data$event == 1 & is.na(data$type))
    event_rows       <- which(data$event == 1)
    actual_missing_pct <- if (length(event_rows) > 0)
      sum(is.na(data$type[event_rows])) / length(event_rows) * 100 else 0

    # Step 3: Phase A imputation (before transformation)
    phase_a <- apply_imputation_phase_a(data, imputation_method,
                                        missing_pattern, missing_pct)
    data      <- phase_a$data
    imp_diag  <- phase_a$diag
```

**Modification B** — Replace the CCA step-5 filtering and the dual pseudo-obs generation with:

```r
    # Step 5: Transform to landmark format
    transformed_data <- transform_with_covariates_complex(data, aa)
    if (is.null(transformed_data) || nrow(transformed_data) == 0)
      return(list(success = FALSE, error = "No data after transformation"))

    # Step 5b: Phase B imputation (after transformation)
    transformed_data <- apply_imputation_phase_b(transformed_data, data,
                                                 imputation_method,
                                                 missing_pattern, missing_pct)

    # Step 6: Generate pseudo-observations
    transformed_data <- apply_pseudo_observations(transformed_data, tau,
                                                  imputation_method,
                                                  missing_pattern, missing_pct)
    transformed_data_full <- transformed_data  # unified: no separate CC/full split
```

**Modification C** — In the results list (near the end of `run_comprehensive_simulation`), add imputation diagnostics alongside the existing c-index values:

```r
    imputation_entropy  = imp_diag$entropy,
    mismatch_rate       = imp_diag$mismatch_rate,
    mean_prob_correct   = imp_diag$mean_prob_correct,
    dr_propensity_mean  = imp_diag$dr_propensity_mean,
    rpm_aic             = imp_diag$rpm_aic,
```

> **Note on train/test split:** Because `transformed_data` is now unified (no `_cc` / `_full` split at this level), replace all references to `transformed_data_cc` with `transformed_data` and `transformed_data_full` with `transformed_data` throughout the train-test split and model fitting sections. The `test_data_cc` / `test_data_true` split happens below the transformation step (lines 386–437 in the current CCA script) and should be kept as-is since it depends on `next_event_observed`.

- [ ] **Step 3: Verify simulation_runner.R sources cleanly**

```bash
cd "Missing Types"
Rscript -e '
  source("simulation_engine.R")
  source("functions.R")
  source("simulation_runner.R")
  cat("All sourced OK\n")
  cat("run_comprehensive_simulation exists:", exists("run_comprehensive_simulation"), "\n")
'
```

Expected: packages load, `All sourced OK`, `run_comprehensive_simulation exists: TRUE`.

- [ ] **Step 4: Smoke-test with CCA scenario (2 sims, single-process)**

```bash
cd "Missing Types"
TEST_RUN=true N_SIMS=2 SCENARIO_NAME=missing_MAR_10pct_complete_case \
  Rscript -e '
    source("simulation_engine.R")
    source("functions.R")
    source("simulation_runner.R")
    imputation_methods <- c("complete_case")
    conf <- configure_simulation(imputation_methods)
    res  <- run_chunked_simulations(conf$scenario, conf$n_sims,
                                    conf$chunk_size, conf$save_interval)
    cat("Successful sims:", sum(sapply(res, function(x) x$success)), "\n")
  '
```

Expected: `Successful sims: 2`

- [ ] **Step 5: Commit**

```bash
cd "Missing Types"
git add simulation_runner.R
git commit -m "feat: add simulation_runner.R with shared RF/MERF/Cox pipeline and imputation dispatch"
```

---

## Task 3: Rewrite CCA wrapper

**Files:**
- Modify: `Missing Types/missing_types_method_comparison_cca.R`

- [ ] **Step 1: Replace entire file with thin wrapper**

```r
# ============================================================================
# METADATA
# ============================================================================
# Description: Complete-case analysis for recurrent events with missing types.
#              Thin wrapper: sources shared simulation_engine.R and
#              simulation_runner.R, then configures and runs.
# Last Updated: 2026-03-26
# ============================================================================

source("simulation_engine.R")
source("functions.R")
source("simulation_runner.R")

# ============================================================================
# METHOD-SPECIFIC CONFIGURATION
# ============================================================================

imputation_methods <- c("complete_case")

# ============================================================================
# RUN
# ============================================================================

conf             <- configure_simulation(imputation_methods)
scenario_results <- run_chunked_simulations(
  conf$scenario, conf$n_sims, conf$chunk_size, conf$save_interval
)
save_and_summarize_results(scenario_results, conf$scenario, conf$temp_dir)
```

- [ ] **Step 2: Test CCA wrapper**

```bash
cd "Missing Types"
TEST_RUN=true N_SIMS=2 SCENARIO_NAME=missing_MAR_10pct_complete_case \
  Rscript missing_types_method_comparison_cca.R
```

Expected: prints config banner, runs 2 sims, saves results, prints summary with c-index values.

- [ ] **Step 3: Commit**

```bash
cd "Missing Types"
git add missing_types_method_comparison_cca.R
git commit -m "refactor: reduce CCA script to thin wrapper (~20 lines)"
```

---

## Task 4: Rewrite IPW wrapper

**Files:**
- Modify: `Missing Types/missing_types_method_comparison_ipw.R`

- [ ] **Step 1: Replace entire file with thin wrapper**

```r
# ============================================================================
# METADATA
# ============================================================================
# Description: IPW (logistic propensity) for recurrent events with missing types.
#              Thin wrapper: sources simulation_engine.R and simulation_runner.R.
# Last Updated: 2026-03-26
# ============================================================================

source("simulation_engine.R")
source("functions.R")
source("simulation_runner.R")

imputation_methods <- c("ipw")

conf             <- configure_simulation(imputation_methods)
scenario_results <- run_chunked_simulations(
  conf$scenario, conf$n_sims, conf$chunk_size, conf$save_interval
)
save_and_summarize_results(scenario_results, conf$scenario, conf$temp_dir)
```

- [ ] **Step 2: Test IPW wrapper**

```bash
cd "Missing Types"
TEST_RUN=true N_SIMS=2 SCENARIO_NAME=missing_MAR_10pct_ipw \
  Rscript missing_types_method_comparison_ipw.R
```

Expected: `Successful sims: 2`

- [ ] **Step 3: Commit**

```bash
cd "Missing Types"
git add missing_types_method_comparison_ipw.R
git commit -m "refactor: reduce IPW script to thin wrapper"
```

---

## Task 5: Rewrite IPW-RF, RPM, RPM-RF, DR, DR-RF wrappers

Apply the same thin-wrapper pattern as Task 4 to the remaining 5 scripts. Each step: write wrapper → test 2 sims → commit.

**Files:** `missing_types_method_comparison_ipw_rf.R`, `_rpm.R`, `_rpm_rf.R`, `_dr.R`, `_dr_rf.R`

- [ ] **Step 1: Write and test IPW-RF wrapper**

```r
# METADATA: IPW-RF (RF propensity) — Last Updated: 2026-03-26
source("simulation_engine.R"); source("functions.R"); source("simulation_runner.R")
imputation_methods <- c("ipw_rf")
conf <- configure_simulation(imputation_methods)
scenario_results <- run_chunked_simulations(conf$scenario, conf$n_sims, conf$chunk_size, conf$save_interval)
save_and_summarize_results(scenario_results, conf$scenario, conf$temp_dir)
```

```bash
TEST_RUN=true N_SIMS=2 SCENARIO_NAME=missing_MAR_10pct_ipw_rf \
  Rscript missing_types_method_comparison_ipw_rf.R
```

- [ ] **Step 2: Write and test RPM wrapper**

```r
# METADATA: RPM (Rate Proportion Model) — Last Updated: 2026-03-26
source("simulation_engine.R"); source("functions.R"); source("simulation_runner.R")
imputation_methods <- c("rpm")
conf <- configure_simulation(imputation_methods)
scenario_results <- run_chunked_simulations(conf$scenario, conf$n_sims, conf$chunk_size, conf$save_interval)
save_and_summarize_results(scenario_results, conf$scenario, conf$temp_dir)
```

```bash
TEST_RUN=true N_SIMS=2 SCENARIO_NAME=missing_MAR_10pct_rpm \
  Rscript missing_types_method_comparison_rpm.R
```

- [ ] **Step 3: Write and test RPM-RF wrapper** (same pattern, `imputation_methods <- c("rpm_rf")`, test with `SCENARIO_NAME=missing_MAR_10pct_rpm_rf`)

- [ ] **Step 4: Write and test DR wrapper** (same pattern, `imputation_methods <- c("dr")`, test with `SCENARIO_NAME=missing_MAR_10pct_dr`)

- [ ] **Step 5: Write and test DR-RF wrapper** (same pattern, `imputation_methods <- c("dr_rf")`, test with `SCENARIO_NAME=missing_MAR_10pct_dr_rf`)

- [ ] **Step 6: Commit all 5 wrappers**

```bash
cd "Missing Types"
git add missing_types_method_comparison_ipw_rf.R missing_types_method_comparison_rpm.R \
        missing_types_method_comparison_rpm_rf.R missing_types_method_comparison_dr.R \
        missing_types_method_comparison_dr_rf.R
git commit -m "refactor: reduce IPW-RF, RPM, RPM-RF, DR, DR-RF scripts to thin wrappers"
```

---

## Task 6: Update GRF scripts to source simulation_engine.R

The GRF scripts keep their own `run_comprehensive_simulation()` but should source `simulation_engine.R` instead of duplicating lib setup, pkg loading, monitoring functions, and the chunked engine.

**Files:**
- Modify: `Missing Types/missing_types_method_comparison_grf_type_cov_all_methods.R`
- Modify: `Missing Types/missing_types_method_comparison_grf_stratified_all_methods.R`

- [ ] **Step 1: In each GRF script, replace lines 1–191 with a source call + minimal config**

Find the block from line 1 through the end of the `run_comprehensive_simulation_optimized` section (now already removed). Replace with:

```r
# ============================================================================
# METADATA
# ============================================================================
# Description: GRF type-covariate method — all imputation methods compared.
#              Uses simulation_engine.R for shared setup and parallel engine.
# Last Updated: 2026-03-26
# ============================================================================

source("simulation_engine.R")
source("functions.R")

# GRF-specific extra export needed by workers
n_trees_grf_global <- NULL  # set by configure_simulation below

imputation_methods <- c("complete_case", "ipw", "ipw_rf",
                        "rpm", "rpm_rf", "dr", "dr_rf")
conf        <- configure_simulation(imputation_methods)
n_trees_grf <- conf$n_trees_grf
```

- [ ] **Step 2: In the `run_chunked_simulations` call at the bottom of each GRF script, add the extra_exports argument**

Find the existing `run_chunked_simulations(...)` call (or equivalent main execution block) and update to use the shared function from `simulation_engine.R`:

```r
scenario_results <- run_chunked_simulations(
  conf$scenario, conf$n_sims, conf$chunk_size, conf$save_interval,
  extra_exports = "n_trees_grf"
)
save_and_summarize_results(scenario_results, conf$scenario, conf$temp_dir)
```

- [ ] **Step 3: Fix IPW-RF seed in GRF scripts**

Find and remove `seed = 123` from the `ranger::ranger(observed ~ ., ...)` call in the IPW-RF Phase B block inside each GRF script's `run_comprehensive_simulation()`. (This is line ~488 in the type-cov script.)

```r
# Before:
obs_model <- ranger::ranger(
  formula   = observed ~ .,
  data      = train_df,
  probability = TRUE,
  num.trees = 500,
  mtry      = length(ipw_features),
  seed      = 123
)

# After:
obs_model <- ranger::ranger(
  formula   = observed ~ .,
  data      = train_df,
  probability = TRUE,
  num.trees = 500,
  mtry      = length(ipw_features)
)
```

- [ ] **Step 4: Test GRF type-cov script**

```bash
cd "Missing Types"
TEST_RUN=true N_SIMS=2 SCENARIO_NAME=missing_MAR_10pct_complete_case \
  Rscript missing_types_method_comparison_grf_type_cov_all_methods.R
```

Expected: `Successful sims: 2`

- [ ] **Step 5: Test GRF stratified script**

```bash
cd "Missing Types"
TEST_RUN=true N_SIMS=2 SCENARIO_NAME=missing_MAR_10pct_complete_case \
  Rscript missing_types_method_comparison_grf_stratified_all_methods.R
```

Expected: `Successful sims: 2`

- [ ] **Step 6: Commit**

```bash
cd "Missing Types"
git add missing_types_method_comparison_grf_type_cov_all_methods.R \
        missing_types_method_comparison_grf_stratified_all_methods.R
git commit -m "refactor: GRF scripts source simulation_engine.R; fix IPW-RF seed=123"
```

---

## Task 7: Cross-method regression test

Run all 7 methods × 2 scenarios (MCAR_10 and MAR_50) as a quick integration check that the refactored pipeline produces non-NA c-index values.

- [ ] **Step 1: Run all methods for one scenario**

```bash
cd "Missing Types"
for method in complete_case ipw ipw_rf rpm rpm_rf dr dr_rf; do
  echo "=== Testing $method ==="
  TEST_RUN=true N_SIMS=2 SCENARIO_NAME=missing_MAR_50pct_${method} \
    Rscript missing_types_method_comparison_${method}.R 2>&1 | \
    grep -E "(Successful|ERROR|c_rf_strat)"
done
```

Expected: Each method prints `Successful sims: 2` with no ERROR lines.

- [ ] **Step 2: Update session log**

Append to `quality_reports/session_logs/2026-03-26_missing-types-simplify-review.md`:

```
- [HH:MM] Missing Types/ — structural dedup complete: created simulation_engine.R (~280 lines)
  and simulation_runner.R (~900 lines); reduced 7 method scripts to ~20-line thin wrappers;
  GRF scripts source simulation_engine.R; total lines ~12,000 → ~2,500 across these files
```

- [ ] **Step 3: Final commit**

```bash
cd "Missing Types"
git add quality_reports/session_logs/2026-03-26_missing-types-simplify-review.md
git commit -m "docs: log structural dedup completion in session log"
```

---

## Self-Review

**Spec coverage:**
- ✓ ~12,000 lines of duplication extracted into 2 shared files
- ✓ All 7 single-method scripts reduced to thin wrappers
- ✓ Both GRF scripts updated
- ✓ IPW-RF `seed=123` in GRF scripts fixed (previously missed in simplify pass)
- ✓ `clusterExport` simplified to only necessary objects (workers use `source("functions.R")`)
- ✓ DR indicator propagation now pre-sorts event data, eliminating per-row dplyr filter (partial efficiency fix)

**Invariants maintained:**
- SLURM submit scripts unchanged (same filenames invoked)
- `functions.R` unchanged (all domain logic stays there)
- `analyze_missing_types_results.R`, `analyze_combined_results.R` unchanged
- Archive scripts unchanged
