# fitness/templates.R — v3 fitness named-template engine (spec §8.1).
#
# compute_fitness(fp, scalars, baselines_map) returns the primary fitness
# scalar. `fp` is the fitness.primary block: either {$template, $target,
# $lower, $upper, $direction, $terms} or {$expr}. Raw expressions are
# evaluated via rlang::eval_tidy against a flat bindings env built from
# scalars + baselines_map (keyed as "<baseline_name>.<col>").

#' Compute primary fitness from per-variant scalars + named baseline scalars.
#'
#' @param fp     fitness.primary block (has $template + fields, OR $expr).
#' @param scalars named numeric list/vector — per-variant scalars.
#' @param baselines_map named list of named lists —
#'   baselines_map$<name>$<col>.
#' @return single numeric scalar.
compute_fitness <- function(fp, scalars, baselines_map) {
  bindings <- build_bindings(scalars, baselines_map)
  if (!is.null(fp$expr)) {
    expr <- rlang::parse_expr(fp$expr)
    return(rlang::eval_tidy(expr, data = bindings))
  }
  if (is.null(fp$template))
    me_stop("fitness.primary missing both $template and $expr")
  switch(fp$template,
    direct_metric  = direct_metric_value(fp, bindings),
    recovery_ratio = recovery_ratio_value(fp, bindings),
    weighted_sum   = weighted_sum_value(fp, bindings),
    me_stop("unknown fitness template: %s", fp$template)
  )
}

build_bindings <- function(scalars, baselines_map) {
  out <- as.list(scalars)
  for (bn in names(baselines_map)) {
    for (cn in names(baselines_map[[bn]])) {
      out[[paste0(bn, ".", cn)]] <- baselines_map[[bn]][[cn]]
    }
  }
  out
}

direct_metric_value <- function(fp, b) {
  v <- b[[fp$target]]
  if (identical(fp$direction, "lower_is_better")) -v else v
}

recovery_ratio_value <- function(fp, b) {
  tgt   <- b[[fp$target]]
  lower <- b[[fp$lower]]
  upper <- b[[fp$upper]]
  if (identical(fp$direction, "lower_is_better")) {
    (lower - tgt) / (lower - upper)
  } else {
    (tgt - lower) / (upper - lower)
  }
}

weighted_sum_value <- function(fp, b) {
  sum(vapply(fp$terms, function(t) t$weight * b[[t$metric]], numeric(1)))
}
