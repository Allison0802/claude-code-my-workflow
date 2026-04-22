library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "validators", "feature_set.R"))
source(file.path(r_dir, "validators", "formula.R"))

slot_cfg <- list(
  kind = "formula",
  lhs  = "Surv(time, event)",
  whitelist = c("x1", "x2", "x3"),
  transforms = list(
    list(name = "log", head = "log", arity = 1L)
  ),
  interactions = "pairwise",
  forbidden_patterns = character(),
  max_terms = 5
)

test_that("validate_formula accepts a valid formula", {
  payload <- list(formula_str = "Surv(time, event) ~ x1 + log(x2) + x1*x3")
  res <- validate_formula(payload, slot_cfg)
  expect_true(res$grammar_valid)
})

test_that("validate_formula rejects mismatched LHS", {
  payload <- list(formula_str = "y ~ x1 + x2")
  res <- validate_formula(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "lhs.*mismatch")
})

test_that("validate_formula rejects unparseable strings", {
  payload <- list(formula_str = "not a formula at all")
  res <- validate_formula(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "parse_error")
})

test_that("validate_formula rejects RHS with non-whitelisted base", {
  payload <- list(formula_str = "Surv(time, event) ~ x1 + bogus_var")
  res <- validate_formula(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "bogus_var")
})

test_that("validate_formula rejects missing payload$formula_str", {
  res <- validate_formula(list(), slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "missing payload")
})
