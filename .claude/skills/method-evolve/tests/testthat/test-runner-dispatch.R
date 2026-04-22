library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "runner_local.R"))
source(file.path(r_dir, "runner_slurm.R"))
source(file.path(r_dir, "runner_custom.R"))
source(file.path(r_dir, "runner_dispatch.R"))

test_that("run_tier dispatches to local runner with empty variants", {
  cfg <- list(compute = list(screen = list(backend = "local", n_workers = 1L)))
  # Empty variants list: local runner returns an empty list of records.
  res <- run_tier("screen", variants = list(), cfg = cfg, state = NULL)
  expect_type(res, "list")
  expect_length(res, 0L)
})

test_that("run_tier errors on unknown backend", {
  cfg <- list(compute = list(screen = list(backend = "weird")))
  expect_error(run_tier("screen", list(), cfg, NULL), "unknown backend")
})

test_that("run_tier errors when backend is missing", {
  cfg <- list(compute = list(screen = list()))
  expect_error(run_tier("screen", list(), cfg, NULL), "backend missing")
})

test_that("run_tier_slurm emits sbatch commands without submitting", {
  tdir <- tempfile(); dir.create(tdir)
  ss <- file.path(tdir, "submit.sh"); file.create(ss)
  cfg <- list(
    compute = list(full = list(backend = "slurm", submit_script = ss)),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke"))
  )
  variants <- list(
    list(variant_id = "var_00001", path = "v1.rds", seed_block = 1L),
    list(variant_id = "var_00002", path = "v2.rds", seed_block = 2L)
  )
  res <- run_tier_slurm(variants, cfg, NULL, tier = "full")
  expect_true(res$deferred)
  expect_equal(res$backend, "slurm")
  expect_length(res$commands, 2L)
  expect_match(res$commands[[1]], "sbatch")
  expect_match(res$commands[[1]], "VARIANT_ID='var_00001'", fixed = TRUE)
})

test_that("run_tier_slurm errors when submit_script missing", {
  cfg <- list(compute = list(full = list(backend = "slurm")),
              evaluator = list(env_vars = list()))
  expect_error(run_tier_slurm(list(), cfg, NULL, tier = "full"),
               "submit_script required")
})

test_that("run_tier_custom substitutes placeholders and runs", {
  tdir <- tempfile(); dir.create(tdir)
  marker <- file.path(tdir, "custom_ran.txt")
  cfg <- list(
    compute = list(full = list(
      backend = "custom",
      submit_cmd = sprintf("echo ${VARIANT_ID} >> %s", marker))),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke"))
  )
  variants <- list(list(variant_id = "var_00001",
                          path = "v1.rds", seed_block = 7L))
  res <- run_tier_custom(variants, cfg, NULL, tier = "full")
  expect_true(res$deferred)
  expect_equal(res$backend, "custom")
  expect_length(res$submissions, 1L)
  # verify substitution actually executed
  expect_true(file.exists(marker))
  expect_equal(trimws(readLines(marker)), "var_00001")
})

test_that("run_tier_custom errors when submit_cmd missing", {
  cfg <- list(compute = list(full = list(backend = "custom")),
              evaluator = list(env_vars = list()))
  expect_error(run_tier_custom(list(), cfg, NULL, tier = "full"),
               "submit_cmd required")
})
