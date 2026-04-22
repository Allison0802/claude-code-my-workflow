library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "validators", "feature_set.R"))
source(file.path(r_dir, "validators", "hyperparameters.R"))
source(file.path(r_dir, "validators", "formula.R"))
source(file.path(r_dir, "validators", "dispatch.R"))

slot_cfg <- list(
  kind = "feature_set",
  max_terms = 20,
  whitelist = c("age", "sex", "n_prior_type1", "log_time", "e.time"),
  transforms = list(
    list(name = "log",    head = "log",  arity = 1L),
    list(name = "sqrt",   head = "sqrt", arity = 1L),
    list(name = "square", head = "I",    arity = 1L, shape = "I(<base>^2)"),
    list(name = "ns",     head = "ns",   arity = 1L, kwargs = list(df = 3)),
    list(name = "ns4",    head = "ns",   arity = 1L, kwargs = list(df = 4))
  ),
  interactions = "pairwise",
  forbidden_patterns = c("true_effect")
)

pl <- function(...) list(feature_set_expr = c(...))

test_that("validate_feature_set accepts bare whitelisted bases", {
  r <- validate_feature_set(pl("age", "sex", "n_prior_type1"), slot_cfg)
  expect_true(r$grammar_valid)
})

test_that("validate_feature_set accepts log(x) and sqrt(x)", {
  r <- validate_feature_set(pl("log(log_time)", "sqrt(e.time)"), slot_cfg)
  expect_true(r$grammar_valid)
})

test_that("validate_feature_set accepts I(x^2) via square descriptor", {
  r <- validate_feature_set(pl("I(age^2)"), slot_cfg)
  expect_true(r$grammar_valid)
})

test_that("validate_feature_set accepts ns(x, df=3) and ns(x, df=4)", {
  r <- validate_feature_set(pl("ns(age, df=3)", "ns(log_time, df=4)"), slot_cfg)
  expect_true(r$grammar_valid)
})

test_that("validate_feature_set rejects ns(x, df=5) — kwargs mismatch", {
  r <- validate_feature_set(pl("ns(age, df=5)"), slot_cfg)
  expect_false(r$grammar_valid)
  expect_match(r$failure_reason, "kwargs_mismatch|ns_args_mismatch")
})

test_that("validate_feature_set rejects non-whitelisted base", {
  r <- validate_feature_set(pl("age", "unknown_col"), slot_cfg)
  expect_false(r$grammar_valid)
})

test_that("validate_feature_set rejects disallowed transform exp(x)", {
  r <- validate_feature_set(pl("exp(age)"), slot_cfg)
  expect_false(r$grammar_valid)
})

test_that("validate_feature_set rejects forbidden pattern", {
  r <- validate_feature_set(pl("age", "true_effect"), slot_cfg)
  expect_false(r$grammar_valid)
})

test_that("validate_feature_set accepts pairwise interactions", {
  r <- validate_feature_set(pl("age*sex"), slot_cfg)
  expect_true(r$grammar_valid)
})

test_that("validate_feature_set rejects three-way under pairwise", {
  r <- validate_feature_set(pl("age*sex*n_prior_type1"), slot_cfg)
  expect_false(r$grammar_valid)
  expect_match(r$failure_reason, "three-way|arity")
})

test_that("validate_feature_set fails closed on unparseable term", {
  r <- validate_feature_set(pl("age +++"), slot_cfg)
  expect_false(r$grammar_valid)
  expect_match(r$failure_reason, "parse_error")
})

test_that("validate_feature_set enforces max_terms", {
  r <- validate_feature_set(pl(rep("age", 21)), slot_cfg)
  expect_false(r$grammar_valid)
  expect_match(r$failure_reason, "max_terms")
})

test_that("validate_proposal dispatcher routes feature_set correctly", {
  r <- validate_proposal(pl("age"), slot_cfg)
  expect_true(r$grammar_valid)
})

test_that("validate_proposal dispatcher errors on unknown slot.kind", {
  expect_error(validate_proposal(list(), list(kind = "weird")),
               "unknown slot.kind")
})

test_that("validate_hyperparameters returns invalid for empty payload", {
  res <- validate_hyperparameters(list(), list(kind = "hyperparameters", params = list()))
  expect_false(res$grammar_valid)
})

test_that("formula stub errors with informative message", {
  expect_error(validate_formula(list(), list(kind = "formula")),
               "not yet implemented")
})
