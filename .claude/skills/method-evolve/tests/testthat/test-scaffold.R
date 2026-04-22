library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "scaffold.R"))

mk_cfg <- function(kind) {
  list(
    name = "t",
    target_script = "evaluator.R",
    slot = list(kind = kind),
    evaluator = list(results_file_pattern = "out.rds"),
    paths = list(out_dir = "runout")
  )
}

test_that("scaffold_driver writes feature_set-serializing driver", {
  tdir <- tempfile(); dir.create(tdir)
  out <- file.path(tdir, "driver.R")
  scaffold_driver(mk_cfg("feature_set"), out)
  expect_true(file.exists(out))
  txt <- paste(readLines(out), collapse = "\n")
  expect_match(txt, "feature_set_expr")
  expect_match(txt, "jsonlite::fromJSON")
  expect_match(txt, "Slot kind: feature_set", fixed = TRUE)
})

test_that("scaffold_driver writes hyperparameters-serializing driver", {
  tdir <- tempfile(); dir.create(tdir)
  out <- file.path(tdir, "driver.R")
  scaffold_driver(mk_cfg("hyperparameters"), out)
  txt <- paste(readLines(out), collapse = "\n")
  expect_match(txt, "hyperparameters")
  expect_match(txt, "simplifyVector = FALSE", fixed = TRUE)
})

test_that("scaffold_driver writes formula-serializing driver", {
  tdir <- tempfile(); dir.create(tdir)
  out <- file.path(tdir, "driver.R")
  scaffold_driver(mk_cfg("formula"), out)
  txt <- paste(readLines(out), collapse = "\n")
  expect_match(txt, "formula_str")
})

test_that("scaffold_driver errors on unknown slot.kind", {
  tdir <- tempfile(); dir.create(tdir)
  out <- file.path(tdir, "driver.R")
  expect_error(scaffold_driver(mk_cfg("weird"), out), "unknown slot.kind")
})

test_that("scaffold_run resolves out_dir from cfg$paths$out_dir", {
  tdir <- tempfile(); dir.create(tdir)
  cfg <- mk_cfg("feature_set")
  cfg$paths$out_dir <- tdir
  p <- scaffold_run(cfg)
  expect_equal(basename(p), "driver.R")
  expect_true(file.exists(p))
})

test_that("driver script is executable", {
  tdir <- tempfile(); dir.create(tdir)
  out <- file.path(tdir, "driver.R")
  scaffold_driver(mk_cfg("feature_set"), out)
  mode <- file.info(out)$mode
  # 0755 → octal mode should have execute bit set for owner
  expect_true(as.integer(mode) %% 2 == 1 || as.integer(mode) >= 493)  # 493 = 0755
})
