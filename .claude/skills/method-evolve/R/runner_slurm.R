# runner_slurm.R — SLURM backend. Emits sbatch commands; does not submit.
#
# For each variant, renders an `env KEY=VALUE... sbatch --array=0 <submit_script>`
# command and prints it. Returns a list with $deferred=TRUE and $commands.

run_tier_slurm <- function(variants, cfg, state = NULL, tier = "full") {
  submit_script <- cfg$compute[[tier]]$submit_script
  if (is.null(submit_script))
    me_stop("compute.%s.submit_script required for slurm backend", tier)
  if (!file.exists(submit_script))
    me_stop("compute.%s.submit_script not found: %s", tier, submit_script)

  cmds <- vapply(variants, function(v) {
    env_str <- build_env_str(v, cfg)
    sprintf("env %s sbatch --array=0 %s", env_str, shQuote(submit_script))
  }, character(1))

  me_log("INFO", "SLURM %s-tier submission commands (%d):", tier, length(cmds))
  for (cmd in cmds) me_log("INFO", "  %s", cmd)
  list(deferred = TRUE, commands = cmds, backend = "slurm", tier = tier)
}

#' Build an `env KEY=VALUE` string for a single variant.
#' Includes VARIANT_PATH, VARIANT_ID, SEED_BLOCK, plus cfg$evaluator$env_vars.
build_env_str <- function(variant, cfg) {
  kvs <- c(
    list(VARIANT_PATH  = variant$path %||% variant$results_file %||% "",
         VARIANT_ID    = variant$variant_id %||% variant$id %||% "var",
         SEED_BLOCK    = as.character(variant$seed_block %||%
                                        variant$child_seed %||% 1L)),
    cfg$evaluator$env_vars %||% list()
  )
  paste(vapply(names(kvs), function(k)
                 sprintf("%s=%s", k, shQuote(as.character(kvs[[k]]))),
                 character(1)),
        collapse = " ")
}
