# config_schema.R — v3 config validator (spec §7)
#
# Validates the top-level config structure, slot.kind, compute.backend,
# prereq baseline references, and fitness.primary template/expr shape.
# Missing optional fields get defaults via %||% (defined in utils.R).

SLOT_KINDS        <- c("feature_set", "hyperparameters", "formula")
BACKENDS          <- c("local", "slurm", "custom")
PREREQ_TYPES      <- c("source-patch", "sidecar-meta", "column-presence", "custom")
FITNESS_TEMPLATES <- c("direct_metric", "recovery_ratio", "weighted_sum")

#' Validate a parsed v3 method-evolve config.
#'
#' @param cfg list parsed from config.yaml (via yaml::read_yaml).
#' @return invisibly TRUE on success. Stops with an informative error on
#'   schema violations; raises a warning (non-blocking) on soft issues like
#'   a fitness.primary.target not guarded by a column-presence prereq.
validate_config <- function(cfg) {
  required_top <- c("name", "target_script", "evaluator", "substitutions",
                    "slot", "baselines", "fitness", "gates", "budget",
                    "compute", "paths")
  miss <- setdiff(required_top, names(cfg))
  if (length(miss))
    me_stop("config missing top-level keys: %s", paste(miss, collapse = ", "))

  # slot.kind must be one of the three recognised kinds
  if (!cfg$slot$kind %in% SLOT_KINDS)
    me_stop("unknown slot.kind: %s (allowed: %s)",
            cfg$slot$kind, paste(SLOT_KINDS, collapse = ", "))

  # compute.<tier>.backend must be valid for screen and full tiers
  for (tier in c("screen", "full")) {
    b <- cfg$compute[[tier]]$backend
    if (is.null(b) || !b %in% BACKENDS)
      me_stop("compute.%s.backend invalid: %s (allowed: %s)",
              tier, as.character(b %||% "<missing>"),
              paste(BACKENDS, collapse = ", "))
  }

  # prerequisites: type must be known; sidecar-meta must reference declared baselines
  for (p in cfg$prerequisites %||% list()) {
    if (!p$type %in% PREREQ_TYPES)
      me_stop("prerequisite '%s': unknown type %s", p$id, p$type)
    if (p$type == "sidecar-meta") {
      miss_b <- setdiff(p$required_for, names(cfg$baselines))
      if (length(miss_b))
        me_stop("prereq '%s' references undeclared baselines: %s",
                p$id, paste(miss_b, collapse = ", "))
    }
  }

  # fitness.primary must be either a template block or a raw expr string
  fp <- cfg$fitness$primary
  if (!is.null(fp$expr)) {
    # raw expression — light syntactic check only (rlang not required;
    # use base parse() so there is no new hard dependency)
    tryCatch(parse(text = fp$expr),
             error = function(e)
               me_stop("fitness.primary.expr parse error: %s",
                       conditionMessage(e)))
  } else if (!is.null(fp$template)) {
    if (!fp$template %in% FITNESS_TEMPLATES)
      me_stop("fitness.primary.template invalid: %s (allowed: %s)",
              fp$template, paste(FITNESS_TEMPLATES, collapse = ", "))
    # warn (non-blocking) when the fitness target has no column-presence guard
    if (fp$template %in% c("direct_metric", "recovery_ratio")) {
      tgt <- fp$target
      has_colpres <- any(vapply(cfg$prerequisites %||% list(),
                                function(p) identical(p$type, "column-presence") &&
                                            tgt %in% (p$required_columns %||% character()),
                                logical(1)))
      if (!has_colpres)
        warning(sprintf(
          "fitness.primary.target '%s' is not declared in any column-presence prereq",
          tgt))
    }
  } else {
    me_stop("fitness.primary must have either 'template' or 'expr'")
  }

  invisible(TRUE)
}
