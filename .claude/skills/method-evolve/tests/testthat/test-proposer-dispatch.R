library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "proposer", "dispatch.R"))

test_that("parse_proposer_response strips ```json fences", {
  raw <- "```json\n[{\"feature_set_expr\": [\"x1\"], \"rationale\": \"\"}]\n```"
  res <- parse_proposer_response(raw, "feature_set")
  expect_true(res$ok)
  expect_length(res$proposals, 1L)
})

test_that("parse_proposer_response rejects shape mismatch", {
  raw <- '[{"hyperparameters": {"mtry": 5}}]'
  res <- parse_proposer_response(raw, "feature_set")
  expect_false(res$ok)
  expect_match(res$error, "feature_set_expr")
})

test_that("parse_proposer_response accepts hyperparameters shape", {
  raw <- '[{"hyperparameters": {"mtry": 5}, "rationale": "x"}]'
  res <- parse_proposer_response(raw, "hyperparameters")
  expect_true(res$ok)
})

test_that("parse_proposer_response accepts formula shape", {
  raw <- '[{"formula_str": "y ~ x1+x2", "rationale": "x"}]'
  res <- parse_proposer_response(raw, "formula")
  expect_true(res$ok)
})

test_that("parse_proposer_response rejects empty JSON array", {
  raw <- '[]'
  res <- parse_proposer_response(raw, "feature_set")
  expect_false(res$ok)
  expect_match(res$error, "empty")
})

test_that("parse_proposer_response rejects malformed JSON", {
  res <- parse_proposer_response("not json at all", "feature_set")
  expect_false(res$ok)
  expect_match(res$error, "parse_error")
})

test_that("load_proposer_template returns non-empty string for each slot kind", {
  for (k in c("feature_set", "hyperparameters", "formula")) {
    tmpl <- load_proposer_template(k)
    expect_true(nchar(tmpl) > 0)
    expect_match(tmpl, "\\{\\{SLOT_KIND\\}\\}|proposer")
  }
})

test_that("load_proposer_template errors on unknown slot_kind", {
  expect_error(load_proposer_template("bogus"),
               "proposer template not found")
})
