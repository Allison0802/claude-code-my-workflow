# ingest.R — pulls per-variant full-tier results into DB records.

#' Read the promote manifest, find each variant's full-tier results RDS,
#' summarize scalars, compute primary_fitness via T10, patch DB record's
#' full slot with primary_fitness + gate_pass + gate_failures.
ingest_run <- function(cfg, out_dir) {
  manifest_path <- file.path(out_dir, "promote_manifest.json")
  if (!file.exists(manifest_path))
    me_stop("ingest: promote manifest missing at %s. Run promote first.",
            manifest_path)
  manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)

  # Group manifest rows by variant_id; merge across seed_blocks by row-binding
  # scalar frames. results path comes from cfg$evaluator$results_file_pattern
  # with VARIANT_ID + SEED_BLOCK substituted.
  by_variant <- split(manifest, vapply(manifest, function(r) r$variant_id,
                                         character(1)))

  baselines_map <- load_baselines(cfg)
  db_path <- file.path(out_dir, "PROGRAM_DB.jsonl")
  patched <- list()

  for (vid in names(by_variant)) {
    rows <- by_variant[[vid]]
    frames <- lapply(rows, function(r) {
      path <- resolve_results_path(cfg, r, out_dir)
      if (!file.exists(path)) {
        me_log("WARN", "ingest: results file missing for %s (seed_block=%d): %s",
               vid, as.integer(r$seed_block), path)
        return(NULL)
      }
      readRDS(path)
    })
    frames <- Filter(Negate(is.null), frames)
    if (!length(frames)) {
      me_log("WARN", "ingest: no full-tier results for %s — skipping", vid)
      next
    }
    combined <- do.call(rbind, frames)
    scalars <- summarize_results(combined)
    scored <- score_variant(scalars, baselines_map, cfg, tier = "full")
    patched[[vid]] <- scored
  }

  # Atomic rewrite: replace full field for each patched variant.
  n <- rewrite_db_atomically(db_path, function(rec) {
    if (!is.null(patched[[rec$variant_id]])) {
      rec$full <- patched[[rec$variant_id]]
    }
    rec
  })
  me_log("INFO", "ingest: patched %d/%d records with full-tier results",
         length(patched), n)
  list(patched = length(patched), db_records = n)
}

#' Resolve a results file path from the cfg pattern + manifest row.
resolve_results_path <- function(cfg, row, out_dir) {
  pattern <- cfg$evaluator$results_file_pattern %||% "results.rds"
  p <- pattern
  p <- gsub("${VARIANT_ID}",   row$variant_id %||% "", p, fixed = TRUE)
  p <- gsub("${SEED_BLOCK}",   as.character(row$seed_block %||% 1L),
             p, fixed = TRUE)
  p <- gsub("${SCENARIO_NAME}",
             cfg$evaluator$env_vars$SCENARIO_NAME %||% "default",
             p, fixed = TRUE)
  p <- gsub("${OUT_DIR}", out_dir, p, fixed = TRUE)
  p
}

#' Load each baseline's summary scalars from its results_file RDS.
load_baselines <- function(cfg) {
  bm <- list()
  for (nm in names(cfg$baselines %||% list())) {
    if (nm == "scenario_match_required") next  # config flag, not a baseline
    rf <- cfg$baselines[[nm]]$results_file
    if (is.null(rf) || !file.exists(rf)) {
      me_log("WARN", "ingest: baseline '%s' results file missing: %s", nm,
             rf %||% "<unset>")
      next
    }
    bm[[nm]] <- summarize_results(readRDS(rf))
  }
  bm
}
