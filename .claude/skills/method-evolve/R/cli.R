#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(here); library(jsonlite); library(yaml); library(digest)
})

skill_r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
for (f in setdiff(list.files(skill_r_dir, pattern = "\\.R$",
                             full.names = TRUE, recursive = TRUE),
                  file.path(skill_r_dir, "cli.R"))) source(f)

# ---------------------------------------------------------------------- #
# arg parsing
# ---------------------------------------------------------------------- #
parse_cli_args <- function(argv) {
  if (length(argv) < 1L) me_stop("Usage: cli.R <command> [--key=value ...]")
  cmd  <- argv[[1L]]; rest <- argv[-1L]; opts <- list()
  for (a in rest) {
    if (!grepl("^--[^=]+(=|$)", a)) me_stop("Bad flag: %s (need --key or --key=value)", a)
    if (grepl("=", a)) {
      kv <- sub("^--", "", a)
      opts[[sub("=.*$", "", kv)]] <- sub("^[^=]+=", "", kv)
    } else {
      opts[[sub("^--", "", a)]] <- TRUE
    }
  }
  list(command = cmd, opts = opts)
}

cli_usage <- function() {
  message(paste(c(
    sprintf("method-evolve v%s", ME_VERSION),
    "Usage: cli.R <command> [--flag=value ...]",
    "",
    "Commands:",
    "  version                              Print version and exit",
    "  scan --config-path=PATH              Summarize config.yaml",
    "  prereq --config-path=PATH            Run all Phase -1 prereq checks",
    "  setup --config-path=PATH --out-dir=DIR [--refreeze]",
    "                                       Initialize run folder + freeze config_sha",
    "  run --out-dir=DIR [--max-gens=N]     Execute the evolution loop",
    "  promote --out-dir=DIR [--dry-run]    Promote screen winners to full tier",
    "  ingest --out-dir=DIR                 Pull full-tier results into DB",
    "  report --out-dir=DIR                 Generate leaderboard.md + plots",
    ""), collapse = "\n"))
}

# ---------------------------------------------------------------------- #
# shared helpers
# ---------------------------------------------------------------------- #
load_yaml_config <- function(path) {
  if (is.null(path) || !file.exists(path))
    me_stop("Config file not found: %s", as.character(path %||% "<missing --config-path>"))
  cfg <- yaml::read_yaml(path)
  validate_config(cfg)
  cfg
}

sha_of_file <- function(path) digest::digest(file = path, algo = "sha256")

resolve_out_dir <- function(opts) {
  od <- opts[["out-dir"]]
  if (is.null(od)) me_stop("--out-dir=DIR required")
  od
}

# ---------------------------------------------------------------------- #
# handlers
# ---------------------------------------------------------------------- #
cmd_version <- function(opts) cat(sprintf("method-evolve v%s\n", ME_VERSION))

cmd_scan <- function(opts) {
  cfg <- load_yaml_config(opts[["config-path"]])
  cat(sprintf("Config OK: name=%s slot.kind=%s backend(screen=%s,full=%s)\n",
              cfg$name, cfg$slot$kind,
              cfg$compute$screen$backend, cfg$compute$full$backend))
  cat(sprintf("  baselines: %s\n", paste(names(cfg$baselines), collapse = ", ")))
  cat(sprintf("  prereqs:   %s\n",
              paste(vapply(cfg$prerequisites %||% list(),
                            function(p) p$id, character(1)),
                    collapse = ", ")))
}

cmd_prereq <- function(opts) {
  cfg <- load_yaml_config(opts[["config-path"]])
  if (!length(cfg$prerequisites %||% list())) {
    me_log("INFO", "no prerequisites declared — nothing to do")
    return(invisible(TRUE))
  }
  for (p in cfg$prerequisites) {
    me_log("INFO", "Running prereq '%s' (type=%s)", p$id, p$type)
    res <- run_prereq_check(p, cfg)
    if (!isTRUE(res$pass))
      me_stop("prereq '%s' FAILED: %s", p$id, res$reason)
    me_log("INFO", "  OK: %s", res$reason)
  }
  invisible(TRUE)
}

cmd_setup <- function(opts) {
  cfg_path <- opts[["config-path"]]
  od <- resolve_out_dir(opts)
  cfg <- load_yaml_config(cfg_path)
  refreeze <- isTRUE(opts[["refreeze"]])

  dir.create(od, recursive = TRUE, showWarnings = FALSE)
  config_sha <- sha_of_file(cfg_path)
  state_path <- file.path(od, "EVOLVE_STATE.json")

  if (file.exists(state_path)) {
    s <- state_load(state_path)
    state_verify_schema_version(s)
    if (identical(s$config_sha, config_sha)) {
      me_log("INFO", "setup: state exists with matching config_sha — no-op")
      return(invisible(TRUE))
    }
    if (!refreeze)
      me_stop(paste("setup: state exists with different config_sha.",
                    "Pass --refreeze to accept the drift or start a",
                    "new --out-dir."))
    me_log("INFO", "setup: refreezing config_sha (was=%s new=%s)",
           substr(s$config_sha, 1, 8), substr(config_sha, 1, 8))
  }

  parent_seed <- cfg$parent_seed %||%
    as.integer(format(Sys.Date(), "%Y%m%d"))
  run_id <- sprintf("%s_%s",
                    format(Sys.time(), "%Y-%m-%d_%H%M%S"),
                    cfg$name %||% "run")
  state_init(state_path, run_id = run_id, config_sha = config_sha,
             parent_seed = parent_seed)
  me_log("INFO", "setup: initialized run %s at %s", run_id, od)
  invisible(TRUE)
}

cmd_run <- function(opts) {
  od <- resolve_out_dir(opts)
  max_gens <- as.integer(opts[["max-gens"]] %||% NA)
  state_path <- file.path(od, "EVOLVE_STATE.json")
  if (!file.exists(state_path))
    me_stop("run: state file missing — did you setup? (%s)", state_path)
  s <- state_load(state_path)
  state_verify_schema_version(s)
  me_log("INFO", "run: would execute up to gen=%s from state gen=%d phase=%s",
         if (is.na(max_gens)) "(config)" else max_gens,
         s$current_generation, s$generation_phase)
  me_log("INFO", "run: full loop implementation deferred — see T24-T26 and smoke T31")
  invisible(TRUE)
}

cmd_promote <- function(opts) {
  od <- resolve_out_dir(opts)
  cfg <- load_yaml_config(opts[["config-path"]] %||%
    me_stop("promote: --config-path=PATH required"))
  dry <- isTRUE(opts[["dry-run"]])
  res <- promote_run(cfg, od, dry_run = dry)
  me_log("INFO", "promote: %d rows, manifest at %s, submitted=%s",
         res$rows, res$manifest_path, res$submitted)
  invisible(TRUE)
}
cmd_ingest  <- function(opts) {
  od <- resolve_out_dir(opts)
  cfg <- load_yaml_config(opts[["config-path"]] %||%
    me_stop("ingest: --config-path=PATH required"))
  res <- ingest_run(cfg, od)
  me_log("INFO", "ingest: patched %d of %d records",
         res$patched, res$db_records)
  invisible(TRUE)
}
cmd_report  <- function(opts) me_stop("report not yet implemented (T26)")

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0 || args[[1]] %in% c("-h", "--help", "help")) {
    cli_usage(); return(invisible(0))
  }
  p <- parse_cli_args(args)
  switch(p$command,
    version = cmd_version(p$opts),
    scan    = cmd_scan(p$opts),
    prereq  = cmd_prereq(p$opts),
    setup   = cmd_setup(p$opts),
    run     = cmd_run(p$opts),
    promote = cmd_promote(p$opts),
    ingest  = cmd_ingest(p$opts),
    report  = cmd_report(p$opts),
    me_stop("Unknown command: %s (try --help)", p$command)
  )
}
if (!interactive()) main()
