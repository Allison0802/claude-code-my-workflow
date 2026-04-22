library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "prereq.R"))

test_that("has_ibs_patch returns TRUE when version stamp matches", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c("# some code", "# ibs-patch-version: 1",
               "foo <- function() 1"), tmp)
  expect_true(has_ibs_patch(tmp, required_version = 1L))
})

test_that("has_ibs_patch returns FALSE when version stamp older", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c("# ibs-patch-version: 0"), tmp)
  expect_false(has_ibs_patch(tmp, required_version = 1L))
})

test_that("has_ibs_patch returns FALSE when no stamp", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c("# no stamp here"), tmp)
  expect_false(has_ibs_patch(tmp, required_version = 1L))
})

test_that("apply_ibs_patch prepends the patch and writes the stamp", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c("# original header", "body <- TRUE"), tmp)
  patch <- file.path(here::here(), ".claude", "skills", "method-evolve",
                     "examples", "missing_types_ipw", "templates", "prereq_ibs.R.patch")
  apply_ibs_patch(tmp, patch_path = patch)
  expect_true(has_ibs_patch(tmp, required_version = 1L))
  expect_match(paste(readLines(tmp), collapse = "\n"), "body <- TRUE", fixed = TRUE)
})

test_that("apply_ibs_patch is idempotent", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c("# original"), tmp)
  patch <- file.path(here::here(), ".claude", "skills", "method-evolve",
                     "examples", "missing_types_ipw", "templates", "prereq_ibs.R.patch")
  apply_ibs_patch(tmp, patch_path = patch)
  before <- paste(readLines(tmp), collapse = "\n")
  apply_ibs_patch(tmp, patch_path = patch)
  after <- paste(readLines(tmp), collapse = "\n")
  expect_equal(before, after)
})
