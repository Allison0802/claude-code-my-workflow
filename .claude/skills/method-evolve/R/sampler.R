# sampler.R — v3 sampler for parent selection across generations.
#
# Reads screen$primary_fitness (was: screen$ibs_recovery in v2). Slot-kind
# agnostic: operates on generic DB records regardless of payload shape.
#
# Three modes:
#   normal            — top-N gate-passers by primary_fitness + M random
#   gate_failure      — zero passers → top-N by fitness regardless +
#                       aggregated failure summary for the proposer
#   seed_generation   — empty DB → no parents (proposer seeds from scratch)

#' Sample parents for the next generation.
#'
#' @param db list of DB records (db_read output).
#' @param n_top integer top-K by primary_fitness.
#' @param n_random integer additional random samples from the rest.
#' @param metric string field name to rank by (default "primary_fitness").
#' @param seed optional integer seed for the random sample.
#' @return list(parents, fallback_mode, failure_summary).
sample_parents <- function(db, n_top = 3L, n_random = 1L,
                            metric = "primary_fitness", seed = NULL) {
  if (!length(db)) {
    return(list(parents = list(), fallback_mode = "seed_generation",
                failure_summary = character()))
  }
  passers <- Filter(function(r) isTRUE(r$screen$gate_pass), db)
  if (length(passers)) {
    vals <- vapply(passers, function(r)
                    as.numeric(r$screen[[metric]] %||% NA_real_),
                   numeric(1))
    ord <- order(vals, decreasing = TRUE)
    top_idx <- ord[seq_len(min(n_top, length(ord)))]
    rest <- setdiff(ord, top_idx)
    if (!is.null(seed)) set.seed(seed)
    rand_idx <- if (length(rest) && n_random > 0)
      sample(rest, min(n_random, length(rest))) else integer(0)
    return(list(parents = passers[c(top_idx, rand_idx)],
                fallback_mode = "normal",
                failure_summary = character()))
  }
  # Zero-gate-passer fallback: top-N by fitness regardless of gate_pass
  vals <- vapply(db, function(r)
                  as.numeric(r$screen[[metric]] %||% -Inf),
                 numeric(1))
  ord <- order(vals, decreasing = TRUE)
  top_idx <- ord[seq_len(min(n_top, length(ord)))]
  rest <- setdiff(ord, top_idx)
  if (!is.null(seed)) set.seed(seed)
  rand_idx <- if (length(rest) && n_random > 0)
    sample(rest, min(n_random, length(rest))) else integer(0)
  failures <- unique(unlist(lapply(db, function(r) r$screen$gate_failures)))
  list(parents = db[c(top_idx, rand_idx)],
       fallback_mode = "gate_failure",
       failure_summary = as.character(failures))
}
