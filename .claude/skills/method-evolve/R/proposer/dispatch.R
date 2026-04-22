# proposer/dispatch.R — proposer template loader, prompt renderer, and
# JSON response parser. Prompt rendering uses {{PLACEHOLDER}} substitution;
# per-slot-kind format_grammar methods fill in GRAMMAR_SPEC.

SKILL_DIR_FOR_PROPOSER <- function() me_skill_root()

#' Load the markdown template for a given slot kind.
load_proposer_template <- function(slot_kind) {
  path <- file.path(SKILL_DIR_FOR_PROPOSER(), "R", "proposer", "templates",
                    paste0(slot_kind, ".md"))
  if (!file.exists(path))
    me_stop("proposer template not found for slot.kind=%s at %s",
            slot_kind, path)
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

#' Render the proposer prompt by filling {{PLACEHOLDER}}s.
render_proposer_prompt <- function(slot_cfg, parents, neg_examples, batch_size) {
  tmpl <- load_proposer_template(slot_cfg$kind)
  subs <- list(
    SLOT_KIND      = slot_cfg$kind,
    BATCH_SIZE     = as.character(batch_size),
    GRAMMAR_SPEC   = format_grammar(slot_cfg),
    PARENTS_BLOCK  = format_parents(parents, slot_cfg$kind),
    NEG_EXAMPLES   = format_neg_examples(neg_examples, slot_cfg$kind)
  )
  for (k in names(subs))
    tmpl <- gsub(paste0("{{", k, "}}"), subs[[k]], tmpl, fixed = TRUE)
  tmpl
}

#' S3 generic: format the grammar spec for the proposer prompt.
#' Per-kind methods land in T14 (feature_set), T15 (hyperparameters),
#' T16 (formula). Default gives a minimal, safe description.
format_grammar <- function(slot_cfg) UseMethod("format_grammar", slot_cfg)

format_grammar.default <- function(slot_cfg)
  sprintf("(grammar for kind '%s' — format_grammar method not yet defined)",
          slot_cfg$kind %||% "unknown")

#' Format the parent-variants block. Intentionally generic — slot-specific
#' payload shape is rendered via toJSON for readability.
format_parents <- function(parents, slot_kind) {
  if (!length(parents))
    return("(no parent variants — seed generation)")
  lines <- vapply(parents, function(p) {
    payload_txt <- jsonlite::toJSON(p$proposal_payload, auto_unbox = TRUE)
    fit <- if (!is.null(p$screen$primary_fitness))
             sprintf("fit=%.3f", as.numeric(p$screen$primary_fitness))
           else "fit=NA"
    sprintf("- [%s] %s  %s", p$variant_id %||% "?", payload_txt, fit)
  }, character(1))
  paste(lines, collapse = "\n")
}

format_neg_examples <- function(neg_examples, slot_kind) {
  if (!length(neg_examples)) return("(no recent rejects)")
  lines <- vapply(neg_examples, function(n) {
    payload_txt <- jsonlite::toJSON(n$proposal_payload %||% n,
                                    auto_unbox = TRUE)
    reason <- n$failure_reason %||% "?"
    sprintf("- %s  reason=%s", payload_txt, reason)
  }, character(1))
  paste(lines, collapse = "\n")
}

#' Parse the proposer's JSON response. Strips ``` fences, validates that
#' the root is a non-empty array, and checks each item for the slot-kind-
#' specific required field.
parse_proposer_response <- function(raw_text, slot_kind) {
  text <- trimws(raw_text)
  # Strip optional leading ```json or ``` and trailing ```
  text <- sub("^```(json)?\\s*", "", text)
  text <- sub("\\s*```\\s*$", "", text)
  parsed <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE),
                     error = function(e) e)
  if (inherits(parsed, "error"))
    return(list(ok = FALSE,
                error = sprintf("parse_error: %s",
                                conditionMessage(parsed))))
  if (!is.list(parsed) || length(parsed) == 0L)
    return(list(ok = FALSE,
                error = "expected non-empty JSON array"))
  required_field <- switch(slot_kind,
    feature_set     = "feature_set_expr",
    hyperparameters = "hyperparameters",
    formula         = "formula_str",
    return(list(ok = FALSE,
                error = sprintf("unknown slot_kind: %s", slot_kind)))
  )
  for (i in seq_along(parsed)) {
    if (is.null(parsed[[i]][[required_field]]))
      return(list(ok = FALSE,
                  error = sprintf("item %d missing %s", i, required_field)))
  }
  list(ok = TRUE, proposals = parsed)
}

#' @export
format_grammar.feature_set <- function(slot_cfg) {
  paste(c(
    sprintf("- whitelist: %s",
            paste(slot_cfg$whitelist %||% character(), collapse = ", ")),
    sprintf("- transforms: %s",
            paste(vapply(slot_cfg$transforms %||% list(),
                         function(t) t$name, character(1)),
                  collapse = ", ")),
    sprintf("- interactions: %s", slot_cfg$interactions %||% "pairwise"),
    sprintf("- max_terms: %d", slot_cfg$max_terms %||% 5L),
    if (length(slot_cfg$forbidden_patterns %||% character()))
      sprintf("- forbidden_patterns: %s",
              paste(slot_cfg$forbidden_patterns, collapse = ", "))
    else NULL
  ), collapse = "
")
}

#' @export
format_grammar.hyperparameters <- function(slot_cfg) {
  paste(vapply(names(slot_cfg$params %||% list()), function(k) {
    spec <- slot_cfg$params[[k]]
    parts <- c(sprintf("- %s: type=%s", k, spec$type))
    if (!is.null(spec$range))
      parts <- c(parts, sprintf("range=[%s,%s]",
                                 spec$range[1], spec$range[2]))
    if (!is.null(spec$enum))
      parts <- c(parts, sprintf("enum=[%s]",
                                 paste(spec$enum, collapse = ",")))
    if (isTRUE(spec$log_scale))
      parts <- c(parts, "log_scale=true")
    paste(parts, collapse = ", ")
  }, character(1)), collapse = "
")
}
