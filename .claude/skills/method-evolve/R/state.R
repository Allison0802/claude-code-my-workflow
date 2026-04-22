# state.R — EVOLVE_STATE.json schema v2 + mid-generation resumability.
# Paste of v2 T10 code with schema_version bumped 1 → 2 and addition of
# state_verify_schema_version() for v3 migration gating.

suppressPackageStartupMessages({ library(jsonlite) })

ME_STATE_SCHEMA <- 2L
ME_GEN_PHASES <- c("proposing", "validated", "evaluating",
                    "db_written", "generation_complete")

state_init <- function(path, run_id, config_sha, parent_seed) {
  s <- list(
    schema_version = ME_STATE_SCHEMA,
    run_id = run_id,
    config_sha = config_sha,
    parent_seed = as.integer(parent_seed),
    last_variant_id = 0L,
    current_generation = 0L,
    generation_phase = "proposing",
    generation_phase_progress = list(
      proposed = list(), validated = list(),
      evaluated = list(), db_written = list()
    ),
    gate_passers_history = list(),
    early_stop_counter = 0L,
    last_checkpoint_at = format(Sys.time(), "%FT%T%z")
  )
  state_save(path, s)
  invisible(s)
}

state_load <- function(path) {
  if (!file.exists(path)) return(NULL)
  jsonlite::fromJSON(paste(readLines(path, warn = FALSE), collapse = "\n"),
                     simplifyVector = FALSE)
}

state_save <- function(path, s) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  s$last_checkpoint_at <- format(Sys.time(), "%FT%T%z")
  tmp <- paste0(path, ".tmp")
  writeLines(jsonlite::toJSON(s, auto_unbox = TRUE, pretty = TRUE), tmp)
  file.rename(tmp, path)
  invisible(TRUE)
}

state_transition <- function(path, generation_phase = NULL,
                              current_generation = NULL,
                              last_variant_id = NULL, proposed = NULL,
                              validated = NULL, evaluated = NULL,
                              db_written = NULL,
                              gate_passers_this_gen = NULL) {
  s <- state_load(path) %||% me_stop("State file missing: %s", path)
  if (!is.null(generation_phase)) {
    if (!generation_phase %in% ME_GEN_PHASES)
      me_stop("Invalid generation_phase: %s", generation_phase)
    s$generation_phase <- generation_phase
  }
  if (!is.null(current_generation)) s$current_generation <- current_generation
  if (!is.null(last_variant_id)) s$last_variant_id <- last_variant_id
  for (k in c("proposed", "validated", "evaluated", "db_written")) {
    v <- get(k)
    if (!is.null(v)) s$generation_phase_progress[[k]] <- as.list(as.integer(v))
  }
  if (!is.null(gate_passers_this_gen)) {
    s$gate_passers_history <- c(s$gate_passers_history,
                                  as.integer(gate_passers_this_gen))
  }
  state_save(path, s)
  invisible(s)
}

state_verify_config_sha <- function(state, expected_sha) {
  if (!identical(state$config_sha, expected_sha))
    me_stop(paste("config_sha mismatch — config changed mid-run.",
                  "Start a new run folder. expected=%s got=%s"),
            expected_sha, state$config_sha)
  invisible(TRUE)
}

state_verify_schema_version <- function(state) {
  if (!identical(as.integer(state$schema_version), ME_STATE_SCHEMA))
    me_stop(paste("schema mismatch: state file is schema_version=%s,",
                  "skill expects %d. Start a new run folder."),
            as.character(state$schema_version %||% "<missing>"),
            ME_STATE_SCHEMA)
  invisible(TRUE)
}

state_resume_plan <- function(state) {
  phase <- state$generation_phase
  prog <- state$generation_phase_progress
  switch(phase,
    generation_complete = list(action = "start_next_generation"),
    db_written          = list(action = "start_next_generation"),
    evaluating          = list(
      action = "re_dispatch",
      variants_to_dispatch = as.list(
        setdiff(as.integer(unlist(prog$validated)),
                as.integer(unlist(prog$evaluated))))
    ),
    validated           = list(
      action = "re_dispatch",
      variants_to_dispatch = prog$validated
    ),
    proposing           = list(action = "re_propose"),
    me_stop("Unknown phase: %s", phase)
  )
}
