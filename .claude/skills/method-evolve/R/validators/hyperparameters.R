# validators/hyperparameters.R — v3 hyperparameters slot validator (spec §6.2)

#' Validate a hyperparameters proposal payload against a JSON-schema-style
#' params spec.
#'
#' @param payload list with $hyperparameters (named list of param values).
#' @param slot_cfg list with $kind = "hyperparameters" and $params (named list
#'   of per-parameter specs: {type = "integer"|"numeric"|"categorical",
#'   range = c(min, max) for numeric/integer, enum = character for
#'   categorical, log_scale = TRUE/FALSE (documented only)}).
#' @return list(grammar_valid, failure_reason).
validate_hyperparameters <- function(payload, slot_cfg) {
  hp <- payload$hyperparameters
  if (is.null(hp) || !is.list(hp))
    return(list(grammar_valid = FALSE,
                failure_reason = "missing payload$hyperparameters"))

  declared <- names(slot_cfg$params)
  given    <- names(hp)
  unknown  <- setdiff(given, declared)
  if (length(unknown))
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("unknown parameter key(s): %s",
                                         paste(unknown, collapse = ","))))
  missing  <- setdiff(declared, given)
  if (length(missing))
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("missing required key(s): %s",
                                         paste(missing, collapse = ","))))

  for (k in declared) {
    spec <- slot_cfg$params[[k]]; v <- hp[[k]]
    if (identical(spec$type, "integer")) {
      if (!is.numeric(v) || v != as.integer(v))
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: not integer", k)))
      if (v < spec$range[1] || v > spec$range[2])
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: out of range [%s,%s]",
                                             k, spec$range[1], spec$range[2])))
    } else if (identical(spec$type, "numeric")) {
      if (!is.numeric(v))
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: not numeric", k)))
      if (v < spec$range[1] || v > spec$range[2])
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: out of range [%s,%s]",
                                             k, spec$range[1], spec$range[2])))
    } else if (identical(spec$type, "categorical")) {
      if (!v %in% spec$enum)
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: not in enum (%s)",
                                             k, paste(spec$enum, collapse = ","))))
    } else {
      return(list(grammar_valid = FALSE,
                  failure_reason = sprintf("%s: unknown spec type %s",
                                           k, spec$type)))
    }
  }
  list(grammar_valid = TRUE, failure_reason = NULL)
}
