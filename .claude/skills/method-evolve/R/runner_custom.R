# runner_custom.R — Custom backend. Runs submit_cmd per variant via system()
# with ${VARIANT_PATH}/${VARIANT_ID}/${SEED_BLOCK}/${SCENARIO_NAME}
# substituted in. Non-zero exit is logged but does not halt the batch —
# users review via ingest time.

run_tier_custom <- function(variants, cfg, state = NULL, tier = "full") {
  cmd_tmpl <- cfg$compute[[tier]]$submit_cmd
  if (is.null(cmd_tmpl))
    me_stop("compute.%s.submit_cmd required for custom backend", tier)

  scenario <- cfg$evaluator$env_vars$SCENARIO_NAME %||% ""
  results <- vector("list", length(variants))
  for (i in seq_along(variants)) {
    v <- variants[[i]]
    cmd <- cmd_tmpl
    cmd <- gsub("${VARIANT_PATH}",
                 v$path %||% v$results_file %||% "", cmd, fixed = TRUE)
    cmd <- gsub("${VARIANT_ID}",
                 v$variant_id %||% v$id %||% "var", cmd, fixed = TRUE)
    cmd <- gsub("${SEED_BLOCK}",
                 as.character(v$seed_block %||% v$child_seed %||% 1L),
                 cmd, fixed = TRUE)
    cmd <- gsub("${SCENARIO_NAME}", scenario, cmd, fixed = TRUE)
    status <- tryCatch(system(cmd, intern = FALSE, ignore.stdout = FALSE,
                               ignore.stderr = FALSE),
                       error = function(e) -1L)
    if (status != 0)
      me_log("WARN", "custom submit_cmd exit=%d for %s", status,
             v$variant_id %||% "?")
    results[[i]] <- list(variant_id = v$variant_id, cmd = cmd,
                          status = status)
  }
  list(deferred = TRUE, submissions = results,
       backend = "custom", tier = tier,
       message = "custom backend: results retrieval is via pull_cmd at ingest time")
}
