library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "state.R"))

test_that("state_init writes schema v2 with all required fields", {
  tmp <- tempfile(fileext = ".json")
  state_init(tmp, run_id = "2026-04-21_t", config_sha = "abc123",
             parent_seed = 20260421L)
  s <- state_load(tmp)
  expect_equal(s$schema_version, 2L)
  expect_equal(s$run_id, "2026-04-21_t")
  expect_equal(s$config_sha, "abc123")
  expect_equal(s$last_variant_id, 0L)
  expect_equal(s$current_generation, 0L)
  expect_equal(s$generation_phase, "proposing")
})

test_that("state_transition writes atomically via .tmp rename", {
  tmp <- tempfile(fileext = ".json")
  state_init(tmp, run_id = "t", config_sha = "x", parent_seed = 1L)
  state_transition(tmp, generation_phase = "validated",
                   validated = c(1L, 2L, 3L))
  s <- state_load(tmp)
  expect_equal(s$generation_phase, "validated")
  expect_equal(as.integer(unlist(s$generation_phase_progress$validated)),
               c(1L, 2L, 3L))
  expect_false(file.exists(paste0(tmp, ".tmp")))
})

test_that("state_resume_plan advances on db_written", {
  tmp <- tempfile(fileext = ".json")
  state_init(tmp, run_id = "t", config_sha = "x", parent_seed = 1L)
  state_transition(tmp, generation_phase = "db_written",
                   db_written = c(1L, 2L, 3L))
  r <- state_resume_plan(state_load(tmp))
  expect_equal(r$action, "start_next_generation")
})

test_that("state_resume_plan re-dispatches unevaluated on evaluating crash", {
  tmp <- tempfile(fileext = ".json")
  state_init(tmp, run_id = "t", config_sha = "x", parent_seed = 1L)
  state_transition(tmp, generation_phase = "evaluating",
                   validated = c(1L, 2L, 3L, 4L),
                   evaluated = c(1L, 2L))
  r <- state_resume_plan(state_load(tmp))
  expect_equal(r$action, "re_dispatch")
  expect_equal(as.integer(unlist(r$variants_to_dispatch)), c(3L, 4L))
})

test_that("state_resume_plan re-proposes on proposing crash", {
  tmp <- tempfile(fileext = ".json")
  state_init(tmp, run_id = "t", config_sha = "x", parent_seed = 1L)
  r <- state_resume_plan(state_load(tmp))
  expect_equal(r$action, "re_propose")
})

test_that("state_verify_config_sha rejects changed config", {
  tmp <- tempfile(fileext = ".json")
  state_init(tmp, run_id = "t", config_sha = "abc123", parent_seed = 1L)
  expect_error(state_verify_config_sha(state_load(tmp), "different_sha"),
               "config changed|mismatch")
})

test_that("state_verify_config_sha passes on match", {
  tmp <- tempfile(fileext = ".json")
  state_init(tmp, run_id = "t", config_sha = "abc123", parent_seed = 1L)
  expect_silent(state_verify_config_sha(state_load(tmp), "abc123"))
})

test_that("state_verify_schema_version rejects v1 state files", {
  tmp <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(list(schema_version = 1L,
                                    run_id = "old", config_sha = "x"),
                              auto_unbox = TRUE), tmp)
  expect_error(state_verify_schema_version(state_load(tmp)),
               "schema mismatch|start a new run folder")
})
