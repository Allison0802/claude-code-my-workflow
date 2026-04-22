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

test_that("render_proposer_prompt fills feature_set template", {
  slot_cfg <- list(kind = "feature_set", whitelist = c("a","b"),
                   transforms = list(list(name = "log")),
                   interactions = "pairwise", max_terms = 5L,
                   forbidden_patterns = character())
  class(slot_cfg) <- c("feature_set", "list")
  out <- render_proposer_prompt(slot_cfg, parents = list(),
                                neg_examples = list(), batch_size = 3L)
  # Placeholders all replaced (no {{X}} survives)
  expect_false(grepl("\\{\\{", out))
  expect_match(out, "whitelist: a, b", fixed = TRUE)
  expect_match(out, "feature_set_expr", fixed = TRUE)
})

test_that("render_proposer_prompt fills hyperparameters template", {
  slot_cfg <- list(kind = "hyperparameters",
                   params = list(
                     mtry      = list(type = "integer",
                                      range = c(1, 20)),
                     splitrule = list(type = "categorical",
                                      enum = c("gini", "extratrees"))
                   ))
  class(slot_cfg) <- c("hyperparameters", "list")
  out <- render_proposer_prompt(slot_cfg, parents = list(),
                                neg_examples = list(), batch_size = 4L)
  expect_false(grepl("\\{\\{", out))
  expect_match(out, "mtry: type=integer", fixed = TRUE)
  expect_match(out, "enum=\\[gini,extratrees\\]")
  expect_match(out, '"hyperparameters"', fixed = TRUE)
})
