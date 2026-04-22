library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "prereq.R"))

test_that("check_sidecar_meta passes when all required keys match", {
  tdir <- tempfile(); dir.create(tdir)
  rds_path  <- file.path(tdir, "lower.rds")
  meta_path <- file.path(tdir, "lower.meta.json")
  saveRDS(data.frame(x = 1), rds_path)
  jsonlite::write_json(list(
    scenario_name  = "smoke", n_subjects = 100L, n_sims = 2L,
    dgp_version    = "test-v1", evaluator_sha = "abc123def456"
  ), meta_path, auto_unbox = TRUE)

  cfg <- list(
    baselines = list(lower = list(results_file = rds_path, meta_file = meta_path)),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke",
                                     N_SUBJECTS = 100L, N_SIMS = 2L))
  )
  prereq <- list(id = "baseline-meta", type = "sidecar-meta",
                 required_for = "lower",
                 required_keys = c("scenario_name", "n_subjects", "n_sims"))
  expect_true(check_sidecar_meta(prereq, cfg)$pass)
})

test_that("check_sidecar_meta fails on hard-key mismatch", {
  tdir <- tempfile(); dir.create(tdir)
  meta_path <- file.path(tdir, "lower.meta.json")
  saveRDS(data.frame(x = 1), file.path(tdir, "lower.rds"))
  jsonlite::write_json(list(scenario_name = "different",
                            n_subjects = 100L, n_sims = 2L),
                       meta_path, auto_unbox = TRUE)
  cfg <- list(
    baselines = list(lower = list(results_file = file.path(tdir, "lower.rds"),
                                  meta_file = meta_path)),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke",
                                     N_SUBJECTS = 100L, N_SIMS = 2L))
  )
  prereq <- list(id = "baseline-meta", type = "sidecar-meta",
                 required_for = "lower",
                 required_keys = c("scenario_name", "n_subjects", "n_sims"))
  res <- check_sidecar_meta(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "scenario_name")
})

test_that("check_sidecar_meta fails when meta file is missing", {
  tdir <- tempfile(); dir.create(tdir)
  saveRDS(data.frame(x = 1), file.path(tdir, "lower.rds"))
  cfg <- list(
    baselines = list(lower = list(results_file = file.path(tdir, "lower.rds"),
                                  meta_file = file.path(tdir, "lower.meta.json"))),
    evaluator = list(env_vars = list())
  )
  prereq <- list(id = "baseline-meta", type = "sidecar-meta",
                 required_for = "lower", required_keys = c("scenario_name"))
  res <- check_sidecar_meta(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "meta file missing")
})
