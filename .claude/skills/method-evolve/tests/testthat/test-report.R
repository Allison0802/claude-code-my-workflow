library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "db.R"))
source(file.path(r_dir, "report.R"))

mk_od_with_db <- function(slot_kind = "feature_set") {
  od <- tempfile(); dir.create(od)
  db_path <- file.path(od, "PROGRAM_DB.jsonl")
  payload <- switch(slot_kind,
    feature_set     = list(feature_set_expr = c("x1", "log(x2)")),
    hyperparameters = list(hyperparameters = list(mtry = 5L, ntree = 500L)),
    formula         = list(formula_str = "y ~ x1 + x2")
  )
  db_append(db_path, make_db_record(
    variant_id = "var_00001", generation = 0L,
    slot_kind = slot_kind, proposal_payload = payload,
    parent_ids = character(), seed_block = 1L, llm_response_id = "x",
    screen = list(gate_pass = TRUE, primary_fitness = 0.7,
                  scalars = list(), gate_failures = character()),
    full = NULL))
  db_append(db_path, make_db_record(
    variant_id = "var_00002", generation = 1L,
    slot_kind = slot_kind, proposal_payload = payload,
    parent_ids = character(), seed_block = 2L, llm_response_id = "y",
    screen = list(gate_pass = TRUE, primary_fitness = 0.8,
                  scalars = list(), gate_failures = character()),
    full = list(gate_pass = TRUE, primary_fitness = 0.9,
                scalars = list(), gate_failures = character())))
  od
}

test_that("report_run writes leaderboard.md for feature_set", {
  od <- mk_od_with_db("feature_set")
  res <- report_run(list(name = "t", slot = list(kind = "feature_set")), od)
  expect_true(file.exists(res$leaderboard))
  md <- paste(readLines(res$leaderboard), collapse = "\n")
  expect_match(md, "feature_set")
  expect_match(md, "var_00002")
  # var_00002 has full-tier fitness 0.9, should be ranked above var_00001 (0.7)
  expect_lt(regexpr("var_00002", md), regexpr("var_00001", md))
})

test_that("report_run generates slot-kind-specific plot file", {
  od <- mk_od_with_db("feature_set")
  res <- report_run(list(name = "t", slot = list(kind = "feature_set")), od)
  expect_equal(length(res$plots), 1L)
  expect_true(file.exists(res$plots))
  expect_match(res$plots, "top_feature_frequencies.pdf")

  od2 <- mk_od_with_db("hyperparameters")
  res2 <- report_run(list(name = "t",
                            slot = list(kind = "hyperparameters")), od2)
  expect_match(res2$plots, "top_hyperparameter_density.pdf")

  od3 <- mk_od_with_db("formula")
  res3 <- report_run(list(name = "t",
                            slot = list(kind = "formula")), od3)
  expect_match(res3$plots, "top_formula_term_frequencies.pdf")
})

test_that("report_run on empty DB writes placeholder leaderboard", {
  od <- tempfile(); dir.create(od)
  writeLines(character(), file.path(od, "PROGRAM_DB.jsonl"))
  res <- report_run(list(name = "t", slot = list(kind = "feature_set")), od)
  expect_true(file.exists(res$leaderboard))
  md <- paste(readLines(res$leaderboard), collapse = "\n")
  expect_match(md, "empty")
})

test_that("report_run errors when DB missing", {
  od <- tempfile(); dir.create(od)
  expect_error(report_run(list(slot = list(kind = "feature_set")), od),
               "DB missing")
})
