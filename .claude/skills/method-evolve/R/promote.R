# promote.R — top-K screen winners → full-tier (via runner_dispatch).

#' Build the promote manifest — one row per (variant × scenario × seed-block).
#' Reads top-K gate-passing variants from DB; uses their payload + IDs +
#' child seeds as the per-row VARIANT_PATH / VARIANT_ID / SEED_BLOCK.
build_promote_manifest <- function(cfg, out_dir) {
  db_path <- file.path(out_dir, "PROGRAM_DB.jsonl")
  if (!file.exists(db_path))
    me_stop("promote: DB missing at %s", db_path)
  k <- cfg$budget$promote_top_k %||% 3L
  winners <- db_top_k(db_path, k = k, metric = "primary_fitness")
  if (!length(winners)) {
    me_log("INFO", "promote: no gate-passers to promote")
    return(list(rows = list(), out_dir = out_dir))
  }
  seed_blocks <- cfg$compute$full$seed_blocks %||% 1L
  variants_dir <- cfg$paths$variants_dir %||%
    file.path(out_dir, "variants")
  rows <- list()
  for (w in winners) {
    for (sb in seq_len(seed_blocks)) {
      rows[[length(rows) + 1L]] <- list(
        variant_id   = w$variant_id,
        path         = file.path(variants_dir, paste0(w$variant_id, ".rds")),
        payload      = w$proposal_payload,
        seed_block   = sb,
        scenario     = cfg$evaluator$env_vars$SCENARIO_NAME %||% "default"
      )
    }
  }
  list(rows = rows, out_dir = out_dir)
}

#' Execute the promote step. dry_run=TRUE writes manifest only.
promote_run <- function(cfg, out_dir, dry_run = FALSE) {
  m <- build_promote_manifest(cfg, out_dir)
  manifest_path <- file.path(out_dir, "promote_manifest.json")
  jsonlite::write_json(m$rows, manifest_path,
                        auto_unbox = TRUE, pretty = TRUE)
  me_log("INFO", "promote: wrote %d rows to %s",
         length(m$rows), manifest_path)
  if (dry_run || !length(m$rows))
    return(list(manifest_path = manifest_path,
                submitted = FALSE, rows = length(m$rows)))
  state <- tryCatch(state_load(file.path(out_dir, "EVOLVE_STATE.json")),
                     error = function(e) NULL)
  res <- run_tier("full", m$rows, cfg, state)
  list(manifest_path = manifest_path, submitted = TRUE,
       rows = length(m$rows), backend_result = res)
}
