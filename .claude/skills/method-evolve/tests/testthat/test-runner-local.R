library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "runner_local.R"))

test_that("materialize_variant writes RDS at deterministic path", {
  cache <- tempfile(); dir.create(cache)
  payload <- list(feature_set_expr = c("age", "log(log_time)"))
  p <- materialize_variant(payload, "var_00042", cache)
  expect_true(file.exists(p))
  expect_match(p, "var_00042\\.rds$")
  expect_equal(readRDS(p), payload)
})

test_that("child_seed_for is deterministic given parent_seed + variant_id", {
  s1 <- child_seed_for(parent_seed = 20260421L, variant_id = "var_00042")
  s2 <- child_seed_for(parent_seed = 20260421L, variant_id = "var_00042")
  s3 <- child_seed_for(parent_seed = 20260421L, variant_id = "var_00043")
  expect_equal(s1, s2)
  expect_false(s1 == s3)
})

test_that("run_variant_local invokes target script and returns ok record", {
  tdir <- tempfile(); dir.create(tdir)
  fake <- file.path(tdir, "fake.R")
  writeLines(c(
    "out <- Sys.getenv('TEST_OUT')",
    "dir.create(out, showWarnings = FALSE, recursive = TRUE)",
    "df <- data.frame(sim = 1:5, m = 0.3)",
    "saveRDS(df, file.path(out, paste0(Sys.getenv('VARIANT_ID', 'x'), '.rds')))"
  ), fake)
  out_dir <- file.path(tdir, "results"); dir.create(out_dir)
  r <- run_variant_local(
    target_script = fake,
    env_vars = list(TEST_OUT = out_dir, VARIANT_ID = "var_00001"),
    results_file = file.path(out_dir, "var_00001.rds"),
    timeout_sec = 30L
  )
  expect_true(r$ok)
  expect_true(file.exists(r$results_file))
  expect_equal(r$status, "ok")
})

test_that("run_variant_local returns eval_error on script failure", {
  tdir <- tempfile(); dir.create(tdir)
  bad <- file.path(tdir, "bad.R")
  writeLines("stop('boom')", bad)
  r <- run_variant_local(target_script = bad, env_vars = list(),
                          results_file = tempfile(), timeout_sec = 10L)
  expect_false(r$ok)
  expect_equal(r$status, "eval_error")
})
