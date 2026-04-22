library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "fitness", "templates.R"))

# Fixtures
scalars <- list(my_metric = 0.4, c_index = 0.7,
                abs_bias = 0.01, coverage = 0.95)
baselines_map <- list(
  baseline_lower = list(my_metric = 0.2, c_index = 0.6),
  baseline_upper = list(my_metric = 0.8, c_index = 0.9)
)

test_that("direct_metric template returns target as-is when higher_is_better", {
  cfg <- list(template = "direct_metric", target = "my_metric",
              direction = "higher_is_better")
  expect_equal(compute_fitness(cfg, scalars, baselines_map), 0.4)
})

test_that("direct_metric template negates when lower_is_better", {
  cfg <- list(template = "direct_metric", target = "abs_bias",
              direction = "lower_is_better")
  expect_equal(compute_fitness(cfg, scalars, baselines_map), -0.01)
})

test_that("recovery_ratio = 1 when target equals upper, higher_is_better", {
  cfg <- list(template = "recovery_ratio", target = "my_metric",
              lower = "baseline_lower.my_metric",
              upper = "baseline_upper.my_metric",
              direction = "higher_is_better")
  s <- scalars; s$my_metric <- 0.8
  expect_equal(compute_fitness(cfg, s, baselines_map), 1)
})

test_that("recovery_ratio = 0 when target equals lower, higher_is_better", {
  cfg <- list(template = "recovery_ratio", target = "my_metric",
              lower = "baseline_lower.my_metric",
              upper = "baseline_upper.my_metric",
              direction = "higher_is_better")
  s <- scalars; s$my_metric <- 0.2
  expect_equal(compute_fitness(cfg, s, baselines_map), 0)
})

test_that("recovery_ratio interpolates linearly", {
  cfg <- list(template = "recovery_ratio", target = "my_metric",
              lower = "baseline_lower.my_metric",
              upper = "baseline_upper.my_metric",
              direction = "higher_is_better")
  s <- scalars; s$my_metric <- 0.5  # halfway between 0.2 and 0.8
  expect_equal(compute_fitness(cfg, s, baselines_map), 0.5)
})

test_that("recovery_ratio inverts under lower_is_better", {
  # Under lower_is_better, lower = worse (larger value), upper = better (smaller)
  bm <- list(baseline_lower = list(m = 0.8),
             baseline_upper = list(m = 0.2))
  cfg <- list(template = "recovery_ratio", target = "m",
              lower = "baseline_lower.m", upper = "baseline_upper.m",
              direction = "lower_is_better")
  s <- list(m = 0.2)
  expect_equal(compute_fitness(cfg, s, bm), 1)
})

test_that("weighted_sum aggregates correctly", {
  cfg <- list(template = "weighted_sum",
              terms = list(list(metric = "my_metric", weight = 1.0),
                           list(metric = "c_index",   weight = 0.5)))
  expect_equal(compute_fitness(cfg, scalars, baselines_map),
               1.0 * 0.4 + 0.5 * 0.7)
})

test_that("raw expr evaluates against the bindings", {
  cfg <- list(expr = "(baseline_lower.my_metric - my_metric) / (baseline_lower.my_metric - baseline_upper.my_metric)")
  s <- scalars; s$my_metric <- 0.5
  expect_equal(compute_fitness(cfg, s, baselines_map),
               (0.2 - 0.5) / (0.2 - 0.8))
})

test_that("raw expr errors on undefined identifier", {
  cfg <- list(expr = "nonexistent + my_metric")
  expect_error(compute_fitness(cfg, scalars, baselines_map),
               "object 'nonexistent' not found")
})
