# report.R — generate leaderboard.md + slot-kind-aware plots from the DB.

#' Produce a markdown leaderboard + slot-kind-aware plots.
report_run <- function(cfg, out_dir) {
  db_path <- file.path(out_dir, "PROGRAM_DB.jsonl")
  if (!file.exists(db_path))
    me_stop("report: DB missing at %s", db_path)
  rows <- db_read(db_path)
  if (!length(rows)) {
    me_log("INFO", "report: DB is empty — writing placeholder leaderboard")
    writeLines(c("# Leaderboard (empty)", ""),
               file.path(out_dir, "leaderboard.md"))
    return(list(leaderboard = file.path(out_dir, "leaderboard.md"),
                plots = character()))
  }
  lb <- write_leaderboard_md(rows, out_dir, cfg)
  plots <- make_plots(rows, out_dir, cfg)
  list(leaderboard = lb, plots = plots)
}

write_leaderboard_md <- function(rows, out_dir, cfg) {
  slot_kind <- cfg$slot$kind %||% "unknown"
  # Collect gate-passers, rank by full$primary_fitness if present else screen.
  rank_val <- function(r) {
    if (!is.null(r$full$primary_fitness)) as.numeric(r$full$primary_fitness)
    else as.numeric(r$screen$primary_fitness %||% NA_real_)
  }
  passers <- Filter(function(r)
    isTRUE(r$full$gate_pass) || isTRUE(r$screen$gate_pass), rows)
  if (!length(passers)) passers <- rows
  vals <- vapply(passers, rank_val, numeric(1))
  ord <- order(vals, decreasing = TRUE)
  top <- passers[ord[seq_len(min(10L, length(ord)))]]

  lines <- c(
    sprintf("# method-evolve leaderboard — %s", cfg$name %||% "run"),
    sprintf("_Slot kind: **%s**_", slot_kind),
    "",
    "| Rank | Variant ID | Fitness | Tier | Payload |",
    "|---:|---|---:|---|---|"
  )
  for (i in seq_along(top)) {
    r <- top[[i]]
    fit <- rank_val(r)
    tier_txt <- if (!is.null(r$full$primary_fitness)) "full" else "screen"
    payload <- tryCatch(jsonlite::toJSON(r$proposal_payload, auto_unbox = TRUE),
                        error = function(e) "<error>")
    lines <- c(lines,
               sprintf("| %d | %s | %.4f | %s | `%s` |",
                       i, r$variant_id, fit, tier_txt, payload))
  }
  path <- file.path(out_dir, "leaderboard.md")
  writeLines(lines, path)
  path
}

#' Slot-kind-aware plots:
#'   feature_set:     top_feature_frequencies.pdf
#'   hyperparameters: top_hyperparameter_density.pdf
#'   formula:         top_formula_term_frequencies.pdf
#' All plots: 300 DPI, white background, Okabe-Ito palette.
make_plots <- function(rows, out_dir, cfg) {
  slot_kind <- cfg$slot$kind %||% "unknown"
  plot_path <- switch(slot_kind,
    feature_set     = file.path(out_dir, "top_feature_frequencies.pdf"),
    hyperparameters = file.path(out_dir, "top_hyperparameter_density.pdf"),
    formula         = file.path(out_dir, "top_formula_term_frequencies.pdf"),
    return(character())  # unknown kind → no plot
  )
  plot_payload_frequencies(rows, plot_path, slot_kind)
  plot_path
}

plot_payload_frequencies <- function(rows, path, slot_kind) {
  # Simple base-R plot to avoid ggplot2 as a hard dep.
  freqs <- extract_term_freqs(rows, slot_kind)
  pdf(path, width = 7, height = 5, bg = "white")
  on.exit(dev.off())
  if (!length(freqs)) {
    plot.new(); title(main = "No terms to plot"); return(invisible())
  }
  par(mar = c(4, 7, 2, 1), family = "sans")
  ord <- order(freqs)
  barplot(freqs[ord], horiz = TRUE, las = 1, col = "#0072B2",
          main = sprintf("Term frequency - %s", slot_kind),
          xlab = "Count (across top variants)")
}

extract_term_freqs <- function(rows, slot_kind) {
  # Collect terms/params across all rows' proposal_payload.
  terms <- unlist(lapply(rows, function(r) {
    p <- r$proposal_payload
    switch(slot_kind,
      feature_set     = p$feature_set_expr,
      hyperparameters = names(p$hyperparameters %||% list()),
      formula         = p$formula_str %||% character(),
      character(0)
    )
  }))
  if (!length(terms)) return(numeric(0))
  tb <- table(terms)
  setNames(as.numeric(tb), names(tb))
}
