library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "prereq.R"))

test_that("check_custom passes on zero exit", {
  prereq <- list(id = "ok", type = "custom", check_command = "true")
  expect_true(check_custom(prereq, list())$pass)
})

test_that("check_custom fails on non-zero exit", {
  prereq <- list(id = "fail", type = "custom", check_command = "false")
  res <- check_custom(prereq, list())
  expect_false(res$pass)
  expect_match(res$reason, "non-zero exit")
})

test_that("run_prereq_check dispatches to the correct handler by type", {
  # source-patch dispatch: construct a fake prereq + config that would exit
  # early with a clear failure reason (file doesn't exist).
  tdir <- tempfile(); dir.create(tdir)
  target <- file.path(tdir, "no_such.R")
  # sidecar-meta: baseline meta file doesn't exist
  prereq_sc <- list(id = "sc", type = "sidecar-meta",
                    required_for = "lower",
                    required_keys = c("scenario_name"))
  cfg_sc <- list(
    baselines = list(lower = list(results_file = file.path(tdir, "lower.rds"),
                                  meta_file   = file.path(tdir, "lower.meta.json"))),
    evaluator = list(env_vars = list())
  )
  res_sc <- run_prereq_check(prereq_sc, cfg_sc)
  expect_false(res_sc$pass)
  expect_match(res_sc$reason, "meta file missing")

  # custom dispatch: zero exit
  expect_true(run_prereq_check(list(id = "ok", type = "custom",
                                    check_command = "true"),
                               list())$pass)
})

test_that("run_prereq_check errors on unknown type", {
  expect_error(run_prereq_check(list(id = "x", type = "bogus"), list()),
               "unknown prereq type")
})
