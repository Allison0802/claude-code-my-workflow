# runner_local.R — local `screen` tier runner.
# Paste of v2 T9 code with renames: run_variant_locally → run_variant_local,
# run_variants_parallel → run_screen_local.

suppressPackageStartupMessages({
  library(parallel)
  library(digest)
})

materialize_variant <- function(payload, variant_id, cache_dir) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(cache_dir, paste0(variant_id, ".rds"))
  saveRDS(payload, path)
  path
}

child_seed_for <- function(parent_seed, variant_id) {
  h <- digest::digest(paste0(parent_seed, "/", variant_id),
                      algo = "xxhash32", serialize = FALSE)
  strtoi(h, base = 16L) %% .Machine$integer.max
}

run_variant_local <- function(target_script, env_vars, results_file,
                               timeout_sec = 600L) {
  env_str <- vapply(names(env_vars),
    function(k) paste0(k, "=", shQuote(as.character(env_vars[[k]]))),
    character(1))
  cmd <- paste(c("env", env_str, "Rscript", shQuote(target_script)),
                collapse = " ")
  t0 <- Sys.time()
  status <- tryCatch(
    system(cmd, intern = FALSE, timeout = timeout_sec),
    error = function(e) list(status = -1L, msg = conditionMessage(e))
  )
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (is.list(status) || (is.numeric(status) && status != 0) ||
      !file.exists(results_file)) {
    return(list(ok = FALSE, status = "eval_error",
                elapsed_sec = elapsed,
                error = if (is.list(status)) status$msg else
                  sprintf("exit=%s",
                          if (is.numeric(status)) status else NA),
                results_file = results_file))
  }
  list(ok = TRUE, status = "ok", elapsed_sec = elapsed,
       results_file = results_file)
}

#' Parent-only writer discipline: children return records; caller serializes.
run_screen_local <- function(variant_jobs, n_workers = 5L) {
  parallel::mclapply(variant_jobs, function(j) {
    set.seed(j$child_seed)
    r <- run_variant_local(j$target_script, j$env_vars, j$results_file,
                            timeout_sec = j$timeout_sec %||% 600L)
    list(variant_id = j$variant_id, payload = j$payload,
         child_seed = j$child_seed, run = r)
  }, mc.cores = n_workers, mc.preschedule = FALSE, mc.cleanup = TRUE)
}
