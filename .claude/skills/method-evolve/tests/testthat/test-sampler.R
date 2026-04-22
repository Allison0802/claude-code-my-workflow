library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "sampler.R"))

mk <- function(id, pass, fit, failures = character()) list(
  variant_id = id, generation = 0L, parent_ids = list(),
  slot_kind = "feature_set",
  proposal_payload = list(feature_set_expr = "x"),
  grammar_valid = TRUE,
  screen = list(gate_pass = pass, primary_fitness = fit,
                scalars = list(), gate_failures = failures),
  full = NULL, seed_block = 1L, llm_response_id = "x", timestamp = "t")

test_that("sample_parents: normal path — top-3 gate-passers + 1 random", {
  db <- list(mk("a", TRUE, 0.9), mk("b", TRUE, 0.8), mk("c", TRUE, 0.7),
             mk("d", TRUE, 0.5), mk("e", TRUE, 0.3), mk("f", FALSE, 0.95))
  r <- sample_parents(db, n_top = 3L, n_random = 1L, seed = 1L)
  expect_equal(r$fallback_mode, "normal")
  expect_equal(length(r$parents), 4L)
  for (p in r$parents) expect_true(p$screen$gate_pass)
})

test_that("sample_parents: zero-gate-passer fallback engages", {
  db <- list(mk("a", FALSE, 0.5, c("abs_bias")),
             mk("b", FALSE, 0.4, c("coverage")))
  r <- sample_parents(db, n_top = 3L, n_random = 1L, seed = 1L)
  expect_equal(r$fallback_mode, "gate_failure")
  expect_gt(length(r$parents), 0L)
  expect_true(length(r$failure_summary) > 0L)
})

test_that("sample_parents: seed-generation mode on empty DB", {
  r <- sample_parents(list(), n_top = 3L, n_random = 1L, seed = 1L)
  expect_equal(r$fallback_mode, "seed_generation")
  expect_length(r$parents, 0L)
})
