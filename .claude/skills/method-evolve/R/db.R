# db.R — v3 Program DB (append-only JSONL, polymorphic proposal_payload,
# atomic variant_id allocation under filelock).
#
# Deltas from v2:
#   - make_db_record() takes slot_kind + proposal_payload (was: flat
#     feature_set_expr column)
#   - db_top_k ranks by screen$primary_fitness (was: screen$ibs_recovery)

suppressPackageStartupMessages({
  library(jsonlite)
  library(filelock)
})

#' Build a DB record. The screen and full fields follow the shape
#' list(gate_pass, primary_fitness, scalars, gate_failures).
make_db_record <- function(variant_id, generation, slot_kind,
                           proposal_payload, parent_ids = character(),
                           seed_block = NA_integer_,
                           llm_response_id = NA_character_,
                           screen = NULL, full = NULL,
                           timestamp = format(Sys.time(),
                                              "%Y-%m-%dT%H:%M:%S%z")) {
  list(
    variant_id       = variant_id,
    generation       = as.integer(generation),
    slot_kind        = slot_kind,
    proposal_payload = proposal_payload,
    parent_ids       = as.list(parent_ids),
    seed_block       = as.integer(seed_block),
    llm_response_id  = llm_response_id,
    screen           = screen,
    full             = full,
    timestamp        = timestamp
  )
}

db_append <- function(path, record) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  line <- jsonlite::toJSON(record, auto_unbox = TRUE,
                            null = "null", na = "null")
  con <- file(path, open = "at"); on.exit(close(con))
  cat(line, "\n", sep = "", file = con)
  invisible(TRUE)
}

db_read <- function(path) {
  if (!file.exists(path)) return(list())
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(lines)]
  lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
}

db_top_k <- function(path, k, metric = "primary_fitness") {
  rows <- db_read(path)
  passers <- Filter(function(r) isTRUE(r$screen$gate_pass), rows)
  if (!length(passers)) return(list())
  vals <- vapply(passers,
                 function(r) as.numeric(r$screen[[metric]] %||% NA_real_),
                 numeric(1))
  ord <- order(vals, decreasing = TRUE)
  passers[ord[seq_len(min(k, length(ord)))]]
}

allocate_variant_ids <- function(state_path, lock_path = paste0(state_path, ".lock"),
                                 count = 1L) {
  lk <- filelock::lock(lock_path, exclusive = TRUE, timeout = 10000)
  if (is.null(lk))
    me_stop("Could not acquire state file lock (%s)", lock_path)
  on.exit(filelock::unlock(lk))
  state <- if (file.exists(state_path) && file.size(state_path) > 0L) {
    jsonlite::fromJSON(paste(readLines(state_path, warn = FALSE), collapse = "\n"),
                        simplifyVector = FALSE)
  } else list()
  last <- as.integer(state$last_variant_id %||% 0L)
  ids <- sprintf("var_%05d", (last + 1L):(last + count))
  state$last_variant_id <- last + count
  tmp <- paste0(state_path, ".tmp")
  writeLines(jsonlite::toJSON(state, auto_unbox = TRUE, pretty = TRUE), tmp)
  file.rename(tmp, state_path)
  ids
}

rewrite_db_atomically <- function(path, mutator) {
  rows <- db_read(path)
  new_rows <- lapply(rows, mutator)
  tmp <- paste0(path, ".tmp")
  con <- file(tmp, open = "wt"); on.exit(try(close(con), silent = TRUE))
  for (r in new_rows) {
    cat(jsonlite::toJSON(r, auto_unbox = TRUE, null = "null", na = "null"),
        "\n", sep = "", file = con)
  }
  close(con); on.exit()
  file.rename(tmp, path)
  invisible(length(new_rows))
}
