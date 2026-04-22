# evaluator.R — v3 generalized evaluator (spec §8).
#
# Inputs:
#   variant_scalars: named list — per-variant summary scalars (column means).
#   baselines_map:   named list of named lists — baselines_map$<baseline>$<col>.
#   cfg:             full config (reads $baselines, $fitness, $gates).
#   tier:            "screen" | "full".
#
# Output (score_variant):
#   list(gate_pass, primary_fitness, scalars, gate_failures, status).
#   status in {"ok", "fallback_engaged"}.

#' Collapse a per-simulation results frame into a single row of scalar means.
summarize_results <- function(df) {
  as.list(setNames(
    vapply(df, function(col) {
      if (is.numeric(col)) mean(col, na.rm = TRUE) else NA_real_
    }, numeric(1)),
    names(df)
  ))
}

#' Halt setup if baselines' lower/upper gap is below epsilon for the primary
#' recovery_ratio fitness template.
check_scenario_denom_floor <- function(baselines_map, cfg) {
  fp <- cfg$fitness$primary
  eps <- cfg$fitness$recovery$denom_floor_epsilon %||% 0.002
  if (!identical(fp$template, "recovery_ratio")) return(invisible(TRUE))
  bindings <- build_bindings(list(), baselines_map)
  lower <- bindings[[fp$lower]]
  upper <- bindings[[fp$upper]]
  if (is.null(lower) || is.null(upper))
    me_stop(paste("check_scenario_denom_floor: could not resolve",
                  "lower='%s' or upper='%s'"),
            fp$lower %||% "?", fp$upper %||% "?")
  d <- abs(upper - lower)
  if (d < eps) {
    me_stop(paste("Scenario non-informative for recovery_ratio:",
                  "|upper - lower| = %.6f < epsilon=%.6f (denom floor).",
                  "Adjust baselines or tighten scenario."),
            d, eps)
  }
  invisible(TRUE)
}

#' Per-gate evaluation.
.gate_ok <- function(value, gate, bindings) {
  if (is.null(value) || !is.finite(value)) return(FALSE)
  switch(gate$op,
    "<"  = value <  gate$threshold,
    "<=" = value <= gate$threshold,
    ">"  = {
      th <- if (!is.null(gate$expr))
              rlang::eval_tidy(rlang::parse_expr(gate$expr), data = bindings)
            else gate$threshold
      value > th
    },
    ">=" = {
      th <- if (!is.null(gate$expr))
              rlang::eval_tidy(rlang::parse_expr(gate$expr), data = bindings)
            else gate$threshold
      value >= th
    },
    "in" = value >= gate$range[[1L]] && value <= gate$range[[2L]],
    me_stop("Unknown gate op: %s", gate$op)
  )
}

#' Apply cfg$gates filtered by tier; returns list(gate_pass, gate_failures).
apply_gates <- function(variant_scalars, baselines_map, cfg,
                        tier = c("screen", "full")) {
  tier <- match.arg(tier)
  bindings <- build_bindings(variant_scalars, baselines_map)
  failures <- character()
  for (g in (cfg$gates %||% list())) {
    gtier <- g$tier %||% "both"
    if (!(gtier %in% c(tier, "both"))) next
    val <- bindings[[g$metric]]
    if (!.gate_ok(val, g, bindings)) {
      failures <- c(failures,
                    sprintf("%s(%s) failed op='%s'", g$metric, tier, g$op))
    }
  }
  list(gate_pass = length(failures) == 0L, gate_failures = failures)
}

#' True if the recovery denominator is degenerate at the variant level.
.denom_degenerate <- function(fp, bindings, eps) {
  if (!identical(fp$template, "recovery_ratio")) return(FALSE)
  lower <- bindings[[fp$lower]]; upper <- bindings[[fp$upper]]
  if (is.null(lower) || is.null(upper)) return(TRUE)
  abs(upper - lower) < eps
}

#' Resolve a fallback metric (supports "neg:<name>" prefix) against bindings.
.fallback_value <- function(fallback_metric, bindings) {
  if (startsWith(fallback_metric, "neg:")) {
    nm <- sub("^neg:", "", fallback_metric)
    return(-as.numeric(bindings[[nm]] %||% NA_real_))
  }
  as.numeric(bindings[[fallback_metric]] %||% NA_real_)
}

#' score_variant: tier-aware pass. Applies gates, computes primary fitness
#' (with per-variant fallback on degenerate denom), returns DB-shape.
score_variant <- function(variant_scalars, baselines_map, cfg,
                          tier = c("screen", "full")) {
  tier <- match.arg(tier)
  bindings <- build_bindings(variant_scalars, baselines_map)
  fp  <- cfg$fitness$primary
  eps <- cfg$fitness$recovery$denom_floor_epsilon %||% 0.002
  fb  <- cfg$fitness$recovery$degenerate_variant_fallback

  status <- "ok"
  fitness_value <- if (.denom_degenerate(fp, bindings, eps)) {
    status <- "fallback_engaged"
    val <- .fallback_value(fb$fallback_metric, bindings)
    if (!is.null(fb$cap))
      val <- min(val, fb$cap)
    val
  } else {
    compute_fitness(fp, variant_scalars, baselines_map)
  }

  gates <- apply_gates(variant_scalars, baselines_map, cfg, tier = tier)

  list(
    gate_pass       = gates$gate_pass,
    primary_fitness = fitness_value,
    scalars         = variant_scalars,
    gate_failures   = gates$gate_failures,
    status          = status
  )
}
