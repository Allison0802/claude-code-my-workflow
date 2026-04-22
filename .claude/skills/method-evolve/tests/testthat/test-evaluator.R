library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "fitness", "templates.R"))
source(file.path(r_dir, "evaluator.R"))

# Fixtures
variant_scalars <- list(my_metric = 0.5, c_index = 0.72,
                        abs_bias = 0.01, coverage = 0.95)
baselines_map <- list(
  baseline_lower = list(my_metric = 0.2, c_index = 0.60),
  baseline_upper = list(my_metric = 0.8, c_index = 0.90)
)

mk_cfg <- function(gates = list(), fallback_metric = "neg:abs_bias",
                   fp_direction = "higher_is_better") {
  list(
    baselines = list(baseline_lower = list(), baseline_upper = list()),
    fitness = list(
      primary = list(template = "recovery_ratio", target = "my_metric",
                     lower = "baseline_lower.my_metric",
                     upper = "baseline_upper.my_metric",
                     direction = fp_direction),
      recovery = list(denom_floor_epsilon = 0.002,
                      degenerate_scenario_action = "reject_and_halt",
                      degenerate_variant_fallback = list(
                        fallback_metric = fallback_metric, cap = 0))
    ),
    gates = gates
  )
}

test_that("summarize_results computes column means over a results frame", {
  df <- data.frame(my_metric = c(0.4, 0.5, 0.6),
                   c_index   = c(0.7, 0.7, 0.74),
                   abs_bias  = c(0.01, 0.02, 0.03))
  s <- summarize_results(df)
  expect_equal(s$my_metric, 0.5)
  expect_equal(s$c_index, 0.71333, tolerance = 1e-4)
})

test_that("apply_gates tier-filters correctly", {
  gates <- list(
    list(metric = "abs_bias", tier = "both",   op = "<",  threshold = 0.05),
    list(metric = "coverage", tier = "screen", op = "in", range = c(0.90, 1.00))
  )
  cfg <- mk_cfg(gates)
  r <- apply_gates(variant_scalars, baselines_map, cfg, tier = "screen")
  expect_true(r$gate_pass)
  # At full tier, the screen-only coverage gate is excluded
  r2 <- apply_gates(variant_scalars, baselines_map, cfg, tier = "full")
  expect_true(r2$gate_pass)
})

test_that("apply_gates reports failures with informative reasons", {
  gates <- list(list(metric = "abs_bias", tier = "both",
                     op = "<", threshold = 0.001))
  cfg <- mk_cfg(gates)
  r <- apply_gates(variant_scalars, baselines_map, cfg, tier = "screen")
  expect_false(r$gate_pass)
  expect_true(any(grepl("abs_bias", r$gate_failures)))
})

test_that("apply_gates supports expr form for >= op using bindings", {
  gates <- list(list(metric = "c_index", tier = "both",
                     op = ">=", expr = "baseline_lower.c_index + 0.05"))
  cfg <- mk_cfg(gates)
  r <- apply_gates(variant_scalars, baselines_map, cfg, tier = "screen")
  expect_true(r$gate_pass)  # 0.72 >= 0.60 + 0.05 = 0.65
})

test_that("check_scenario_denom_floor halts when baselines too close", {
  # Make lower very close to upper
  bm <- list(baseline_lower = list(my_metric = 0.80),
             baseline_upper = list(my_metric = 0.801))
  cfg <- mk_cfg()
  expect_error(check_scenario_denom_floor(bm, cfg),
               "non-informative|denom")
})

test_that("check_scenario_denom_floor passes when gap > epsilon", {
  cfg <- mk_cfg()
  expect_silent(check_scenario_denom_floor(baselines_map, cfg))
})

test_that("score_variant returns full DB-shape with primary_fitness", {
  gates <- list(list(metric = "abs_bias", tier = "both",
                     op = "<", threshold = 0.05))
  cfg <- mk_cfg(gates)
  r <- score_variant(variant_scalars, baselines_map, cfg, tier = "screen")
  expect_named(r, c("gate_pass", "primary_fitness", "scalars",
                    "gate_failures", "status"),
               ignore.order = TRUE)
  expect_true(is.numeric(r$primary_fitness))
  expect_true(r$gate_pass)
  expect_equal(r$scalars$my_metric, 0.5)
  expect_equal(r$status, "ok")
})

test_that("score_variant uses fallback metric on degenerate denom", {
  # Force denom ~= 0 by aligning upper with lower
  bm <- list(baseline_lower = list(my_metric = 0.5),
             baseline_upper = list(my_metric = 0.500001))
  cfg <- mk_cfg(gates = list(), fallback_metric = "neg:abs_bias")
  # The compute_fitness would return a huge recovery_ratio due to tiny denom;
  # the evaluator should detect abs(lower-upper) < epsilon per variant and
  # substitute -abs_bias (so score = -0.01), capped at 0 (so still -0.01).
  r <- score_variant(variant_scalars, bm, cfg, tier = "screen")
  expect_equal(r$primary_fitness, -0.01)
  expect_equal(r$status, "fallback_engaged")
})

test_that("score_variant caps fallback result at config.fitness.recovery...cap", {
  bm <- list(baseline_lower = list(my_metric = 0.5),
             baseline_upper = list(my_metric = 0.500001))
  # Use neg:c_index which would be -0.72; cap=0 means min(-0.72, 0) = -0.72
  cfg <- mk_cfg(gates = list(), fallback_metric = "neg:c_index")
  r <- score_variant(variant_scalars, bm, cfg, tier = "screen")
  expect_equal(r$primary_fitness, -0.72)  # negative, not clipped up
  expect_equal(r$status, "fallback_engaged")
})
