# validators/formula.R — v3 formula slot validator (spec §6.3)
#
# Parses formula_str with stats::as.formula, checks LHS literal equality
# with slot_cfg$lhs, then extracts RHS term labels via stats::terms() and
# feeds them into validate_feature_set() for the usual walker checks.

#' Validate a formula-slot proposal payload.
#'
#' @param payload list with $formula_str (single string).
#' @param slot_cfg list with $kind = "formula", $lhs (string), and the
#'   feature-set fields used by the walker ($whitelist, $transforms,
#'   $interactions, $max_terms, $forbidden_patterns).
#' @return list(grammar_valid, failure_reason).
validate_formula <- function(payload, slot_cfg) {
  s <- payload$formula_str
  if (is.null(s) || !is.character(s) || length(s) != 1L || !nzchar(s))
    return(list(grammar_valid = FALSE,
                failure_reason = "missing payload$formula_str"))

  f <- tryCatch(stats::as.formula(s), error = function(e) e)
  if (inherits(f, "error"))
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("parse_error: %s",
                                         conditionMessage(f))))

  # Two-sided formula required for LHS equality check.
  if (length(f) < 3L)
    return(list(grammar_valid = FALSE,
                failure_reason = "parse_error: one-sided formula (missing LHS)"))

  lhs_observed <- paste(deparse(f[[2L]]), collapse = "")
  if (!identical(lhs_observed, slot_cfg$lhs))
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf(
                  "lhs mismatch: expected '%s', got '%s'",
                  slot_cfg$lhs, lhs_observed)))

  # Walk RHS terms by reusing the feature_set walker.
  rhs_terms <- attr(stats::terms(f), "term.labels")
  fake_payload <- list(feature_set_expr = rhs_terms)
  res <- validate_feature_set(fake_payload, slot_cfg)
  if (!res$grammar_valid)
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("rhs invalid: %s",
                                         res$failure_reason)))

  list(grammar_valid = TRUE, failure_reason = NULL)
}
