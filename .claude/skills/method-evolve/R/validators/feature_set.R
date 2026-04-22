# validators/feature_set.R — v3 feature_set slot validator
#
# Implements spec §6.1 grammar rules using rlang::parse_expr +
# recursive whitelist/transform/interaction walker.

suppressPackageStartupMessages({ library(rlang) })

#' Validate a feature_set proposal payload.
#'
#' @param payload list; must contain $feature_set_expr (character vector of
#'   R model-term expressions).
#' @param slot_cfg list; slot configuration with fields whitelist, transforms
#'   (list of descriptor lists: name/head/arity/shape/kwargs), interactions
#'   ("none"/"pairwise"/"all"), max_terms (int), forbidden_patterns (chr).
#' @return list(grammar_valid, failure_reason).
validate_feature_set <- function(payload, slot_cfg) {
  feature_set <- payload$feature_set_expr
  if (is.null(feature_set) || !is.character(feature_set))
    return(list(grammar_valid = FALSE,
                failure_reason = "missing payload$feature_set_expr"))

  errors <- character()

  if (length(feature_set) > (slot_cfg$max_terms %||% Inf)) {
    errors <- c(errors, sprintf("exceeds max_terms: %d > %d",
                                 length(feature_set), slot_cfg$max_terms))
  }

  for (i in seq_along(feature_set)) {
    for (pat in slot_cfg$forbidden_patterns %||% character()) {
      if (grepl(pat, feature_set[[i]])) {
        errors <- c(errors, sprintf("term %d ('%s'): forbidden pattern '%s'",
                                     i, feature_set[[i]], pat))
      }
    }
  }

  walker <- .make_walker(slot_cfg$whitelist %||% character(),
                         slot_cfg$transforms %||% list(),
                         slot_cfg$interactions %||% "pairwise")

  for (i in seq_along(feature_set)) {
    term <- feature_set[[i]]
    e <- tryCatch(rlang::parse_expr(term),
                  error = function(err)
                    structure(list(msg = conditionMessage(err)),
                              class = "me_parse_err"))
    if (inherits(e, "me_parse_err")) {
      errors <- c(errors, sprintf("term %d ('%s'): parse_error: %s",
                                   i, term, e$msg))
      next
    }
    r <- walker(e)
    if (!r$ok)
      errors <- c(errors, sprintf("term %d ('%s'): %s", i, term, r$reason))
  }

  if (length(errors) == 0L)
    list(grammar_valid = TRUE, failure_reason = NULL)
  else
    list(grammar_valid = FALSE,
         failure_reason = paste(errors, collapse = "; "))
}

.make_walker <- function(whitelist, descriptors, interactions) {
  .check_base <- function(sym) {
    nm <- as.character(sym)
    if (!nm %in% whitelist)
      return(list(ok = FALSE,
                  reason = sprintf("base '%s' not in whitelist", nm)))
    list(ok = TRUE)
  }
  .check_transform <- function(e) {
    head <- as.character(e[[1L]])
    cands <- Filter(function(d) identical(d$head, head), descriptors)
    if (!length(cands))
      return(list(ok = FALSE,
                  reason = sprintf("transform '%s' not in descriptors", head)))
    args <- as.list(e)[-1L]
    for (d in cands) {
      if (!is.null(d$shape) && d$shape == "I(<base>^2)") {
        if (length(args) != 1L) next
        inner <- args[[1L]]
        if (is.call(inner) && as.character(inner[[1L]]) == "^" &&
            is.name(inner[[2L]]) && identical(inner[[3L]], 2)) {
          bc <- .check_base(inner[[2L]])
          if (bc$ok) return(list(ok = TRUE))
        }
        next
      }
      if (is.null(d$kwargs)) {
        if (length(args) == 1L && is.name(args[[1L]])) {
          bc <- .check_base(args[[1L]])
          if (bc$ok) return(list(ok = TRUE))
        }
      } else {
        if (length(args) < 1L || !is.name(args[[1L]])) next
        bc <- .check_base(args[[1L]]); if (!bc$ok) next
        nms <- names(args)
        named <- if (is.null(nms)) list() else args[nzchar(nms)]
        named_vals <- lapply(named, function(a)
                             tryCatch(eval(a), error = function(e) NULL))
        if (identical(named_vals[names(d$kwargs)], d$kwargs))
          return(list(ok = TRUE))
      }
    }
    list(ok = FALSE,
         reason = sprintf("kwargs_mismatch or ns_args_mismatch for '%s'", head))
  }
  .check_interaction <- function(e) {
    parts <- .flatten_interaction(e)
    arity <- length(parts)
    if (identical(interactions, "none"))
      return(list(ok = FALSE, reason = "interactions disabled"))
    if (identical(interactions, "pairwise") && arity > 2L)
      return(list(ok = FALSE,
                  reason = sprintf("three-way interaction under pairwise arity=%d", arity)))
    for (p in parts) {
      if (!is.name(p))
        return(list(ok = FALSE, reason = "interaction part not a bare base"))
      bc <- .check_base(p); if (!bc$ok) return(bc)
    }
    list(ok = TRUE)
  }
  .flatten_interaction <- function(e) {
    if (is.call(e) && as.character(e[[1L]]) %in% c("*", ":")) {
      c(.flatten_interaction(e[[2L]]), .flatten_interaction(e[[3L]]))
    } else list(e)
  }
  function(e) {
    if (is.name(e)) return(.check_base(e))
    if (is.call(e)) {
      head <- as.character(e[[1L]])
      if (head %in% c("*", ":")) return(.check_interaction(e))
      return(.check_transform(e))
    }
    list(ok = FALSE, reason = "unsupported expression form")
  }
}
