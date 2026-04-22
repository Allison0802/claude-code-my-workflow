#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(here); library(jsonlite)
})

skill_r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
for (f in setdiff(
       list.files(skill_r_dir, pattern = "\\.R$",
                  full.names = TRUE, recursive = TRUE),
       file.path(skill_r_dir, "cli.R"))) source(f)

parse_cli_args <- function(argv) {
  if (length(argv) < 1L) me_stop("Usage: cli.R <command> [--key=value ...]")
  cmd  <- argv[[1L]]; rest <- argv[-1L]; opts <- list()
  for (a in rest) {
    if (!grepl("^--[^=]+=", a)) me_stop("Bad flag: %s (need --key=value)", a)
    kv <- sub("^--", "", a)
    opts[[sub("=.*$", "", kv)]] <- sub("^[^=]+=", "", kv)
  }
  list(command = cmd, opts = opts)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  p <- parse_cli_args(args)
  switch(p$command,
    version = cat(sprintf("method-evolve v%s\n", ME_VERSION)),
    me_stop("Unknown command: %s", p$command)
  )
}
if (!interactive()) main()
