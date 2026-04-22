library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "validators", "hyperparameters.R"))

slot_cfg <- list(
  kind = "hyperparameters",
  params = list(
    mtry      = list(type = "integer",     range = c(1, 20)),
    ntree     = list(type = "integer",     range = c(100, 2000), log_scale = TRUE),
    splitrule = list(type = "categorical", enum  = c("gini", "extratrees"))
  )
)

test_that("validate_hyperparameters accepts valid in-range values", {
  payload <- list(hyperparameters = list(mtry = 5, ntree = 500,
                                         splitrule = "gini"))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_true(res$grammar_valid); expect_null(res$failure_reason)
})

test_that("validate_hyperparameters rejects unknown parameter key", {
  payload <- list(hyperparameters = list(mtry = 5, ntree = 500,
                                         splitrule = "gini", extra = 99))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "unknown parameter")
})

test_that("validate_hyperparameters rejects out-of-range integer", {
  payload <- list(hyperparameters = list(mtry = 999, ntree = 500,
                                         splitrule = "gini"))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "mtry.*range")
})

test_that("validate_hyperparameters rejects categorical not in enum", {
  payload <- list(hyperparameters = list(mtry = 5, ntree = 500,
                                         splitrule = "weird"))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "splitrule.*enum")
})

test_that("validate_hyperparameters rejects type mismatch", {
  payload <- list(hyperparameters = list(mtry = "five", ntree = 500,
                                         splitrule = "gini"))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "mtry.*integer")
})

test_that("validate_hyperparameters rejects missing required key", {
  payload <- list(hyperparameters = list(mtry = 5, ntree = 500))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "missing.*splitrule")
})
