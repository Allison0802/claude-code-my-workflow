ME_VERSION <- "0.1.0"
`%||%` <- function(a, b) if (is.null(a)) b else a
me_log <- function(level, msg, ...) {
  ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  cat(sprintf("[%s] %s %s\n", ts, level, sprintf(msg, ...)), file = stderr())
}
me_stop <- function(msg, ...) stop(sprintf(msg, ...), call. = FALSE)
me_skill_root <- function() file.path(here::here(), ".claude", "skills", "method-evolve")
