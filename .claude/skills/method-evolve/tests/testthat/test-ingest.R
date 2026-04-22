library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "db.R"))
source(file.path(r_dir, "fitness", "templates.R"))
source(file.path(r_dir, "evaluator.R"))
source(file.path(r_dir, "ingest.R"))

setup_run <- function() {
  od <- tempfile(); dir.create(od)
  db_path <- file.path(od, "PROGRAM_DB.jsonl")
  db_append(db_path, make_db_record(
    variant_id = "var_00001", generation = 0L, slot_kind = "feature_set",
    proposal_payload = list(feature_set_expr = "x"),
    parent_ids = character(), seed_block = 1L, llm_response_id = "x",
    screen = list(gate_pass = TRUE, primary_fitness = 0.5,
                  scalars = list(), gate_failures = character())))

  # Baselines
  saveRDS(data.frame(m = c(0.15, 0.2, 0.25)), file.path(od, "lower.rds"))
  saveRDS(data.frame(m = c(0.75, 0.8, 0.85)), file.path(od, "upper.rds"))

  # Full-tier result for var_00001 at seed_block=1
  results_path <- file.path(od, "full_var_00001_sb1.rds")
  saveRDS(data.frame(m = c(0.48, 0.5, 0.52)), results_path)

  # Manifest
  jsonlite::write_json(list(list(variant_id = "var_00001",
                                   seed_block = 1L,
                                   payload = list(feature_set_expr = "x"))),
                        file.path(od, "promote_manifest.json"),
                        auto_unbox = TRUE)
  od
}

mk_cfg <- function(od) {
  list(
    baselines = list(lower = list(results_file = file.path(od, "lower.rds")),
                     upper = list(results_file = file.path(od, "upper.rds"))),
    fitness = list(
      primary = list(template = "recovery_ratio", target = "m",
                     lower = "lower.m", upper = "upper.m",
                     direction = "higher_is_better"),
      recovery = list(denom_floor_epsilon = 0.002,
                      degenerate_scenario_action = "reject_and_halt",
                      degenerate_variant_fallback = list(fallback_metric = "m",
                                                         cap = 0))
    ),
    gates = list(list(metric = "m", tier = "full", op = "<", threshold = 1.0)),
    evaluator = list(
      env_vars = list(SCENARIO_NAME = "smoke"),
      results_file_pattern = file.path(od,
        "full_${VARIANT_ID}_sb${SEED_BLOCK}.rds")
    )
  )
}

test_that("load_baselines summarizes each declared baseline", {
  od <- setup_run()
  bm <- load_baselines(mk_cfg(od))
  expect_setequal(names(bm), c("lower", "upper"))
  expect_equal(bm$lower$m, 0.2, tolerance = 1e-4)
  expect_equal(bm$upper$m, 0.8, tolerance = 1e-4)
})

test_that("resolve_results_path substitutes VARIANT_ID + SEED_BLOCK", {
  od <- setup_run()
  cfg <- mk_cfg(od)
  p <- resolve_results_path(cfg,
    list(variant_id = "var_00001", seed_block = 1L), od)
  expect_true(grepl("full_var_00001_sb1.rds", p))
})

test_that("ingest_run patches DB with full-tier fitness", {
  od <- setup_run()
  r <- ingest_run(mk_cfg(od), od)
  expect_equal(r$patched, 1L)
  rows <- db_read(file.path(od, "PROGRAM_DB.jsonl"))
  rec <- Filter(function(x) x$variant_id == "var_00001", rows)[[1]]
  expect_false(is.null(rec$full))
  expect_true(rec$full$gate_pass)
  # Recovery: (0.5 - 0.2) / (0.8 - 0.2) = 0.5
  expect_equal(rec$full$primary_fitness, 0.5, tolerance = 1e-4)
})

test_that("ingest_run errors when manifest missing", {
  od <- tempfile(); dir.create(od)
  expect_error(ingest_run(mk_cfg(od), od), "manifest missing")
})

test_that("ingest_run skips variants with missing results files", {
  od <- setup_run()
  file.remove(file.path(od, "full_var_00001_sb1.rds"))
  r <- ingest_run(mk_cfg(od), od)
  expect_equal(r$patched, 0L)  # no results → no patch
})
