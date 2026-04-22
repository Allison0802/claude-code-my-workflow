library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "config_schema.R"))

minimal_cfg <- function(slot_kind = "feature_set") {
  list(
    name = "t",
    target_script = "scripts/R/eval.R",
    prerequisites = list(
      list(id = "cols", type = "column-presence",
           smoke_env_vars = list(),
           required_columns = c("m"))
    ),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke", N_SIMS = 2L,
                                     N_SUBJECTS = 50L),
                     results_file_pattern = "out.rds"),
    substitutions = list(freeze_on_setup = c("run_date", "name"),
                         per_variant = c("VARIANT_PATH", "VARIANT_ID", "SEED_BLOCK"),
                         refreeze_behavior = "error"),
    slot = list(kind = slot_kind, max_terms = 5,
                whitelist = c("x1", "x2"), transforms = list(),
                interactions = "pairwise", forbidden_patterns = character()),
    baselines = list(lower = list(results_file = "lower.rds",
                                  meta_file = "lower.meta.json"),
                     upper = list(results_file = "upper.rds",
                                  meta_file = "upper.meta.json")),
    fitness = list(primary = list(template = "recovery_ratio",
                                  target = "m", lower = "lower.m",
                                  upper = "upper.m",
                                  direction = "higher_is_better"),
                   recovery = list(denom_floor_epsilon = 0.002,
                                   degenerate_scenario_action = "reject_and_halt",
                                   degenerate_variant_fallback = list(
                                     fallback_metric = "neg:m", cap = 0))),
    gates = list(list(metric = "abs_bias", tier = "both",
                      op = "<", threshold = 0.02)),
    budget = list(max_variants = 10, batch_size = 2,
                  max_generations = 3, promote_top_k = 2,
                  early_stop_after = 5),
    compute = list(screen = list(backend = "local", n_workers = 2),
                   full = list(backend = "local")),
    paths = list(out_dir = "out", variants_dir = "out/variants",
                 program_db = "out/db.jsonl",
                 state_file  = "out/state.json")
  )
}

test_that("validate_config accepts a minimal feature_set config", {
  expect_silent(validate_config(minimal_cfg("feature_set")))
})

test_that("validate_config rejects unknown slot.kind", {
  cfg <- minimal_cfg(); cfg$slot$kind <- "weird_thing"
  expect_error(validate_config(cfg), "unknown slot.kind")
})

test_that("validate_config rejects prereq referencing undeclared baseline", {
  cfg <- minimal_cfg()
  cfg$prerequisites <- c(cfg$prerequisites,
                         list(list(id = "x", type = "sidecar-meta",
                                   required_for = "missing_baseline")))
  expect_error(validate_config(cfg), "missing_baseline")
})

test_that("validate_config warns when fitness.primary.target has no column-presence guard", {
  cfg <- minimal_cfg()
  cfg$fitness$primary$target <- "unknown_col"  # not in column-presence required_columns
  expect_warning(validate_config(cfg), "unknown_col")
})

test_that("validate_config rejects unknown compute backend", {
  cfg <- minimal_cfg()
  cfg$compute$full$backend <- "bogus"
  expect_error(validate_config(cfg), "backend.*bogus")
})
