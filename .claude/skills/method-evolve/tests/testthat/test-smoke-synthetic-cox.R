library(testthat)
library(here)

r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
cli_r  <- file.path(r_dir, "cli.R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "db.R"))

run_cli <- function(args) {
  system2("Rscript", c(shQuote(cli_r), args),
          stdout = FALSE, stderr = FALSE)
}

cox_cfg <- file.path(here::here(), ".claude", "skills", "method-evolve",
                     "examples", "synthetic_cox", "config.yaml")

# ---------------------------------------------------------------------------
# T31-1: config exists
# ---------------------------------------------------------------------------
test_that("synthetic_cox config file exists", {
  expect_true(file.exists(cox_cfg))
})

# ---------------------------------------------------------------------------
# T31-2: prereq passes
# ---------------------------------------------------------------------------
test_that("prereq step passes against synthetic_cox config", {
  skip_if_not(file.exists(cox_cfg))
  skip_on_cran()
  expect_equal(run_cli(c("prereq",
                         paste0("--config-path=", cox_cfg))), 0L)
})

# ---------------------------------------------------------------------------
# T31-3: setup initialises EVOLVE_STATE.json with schema_version=2
# ---------------------------------------------------------------------------
test_that("setup initializes EVOLVE_STATE.json for synthetic_cox", {
  skip_if_not(file.exists(cox_cfg))
  od <- tempfile("evolve_smoke_"); dir.create(od)
  expect_equal(run_cli(c("setup",
                         paste0("--config-path=", cox_cfg),
                         paste0("--out-dir=", od))), 0L)
  state_path <- file.path(od, "EVOLVE_STATE.json")
  expect_true(file.exists(state_path))
  s <- jsonlite::fromJSON(state_path, simplifyVector = FALSE)
  expect_equal(s$schema_version, 2L)
  expect_equal(s$generation_phase, "proposing")
})

# ---------------------------------------------------------------------------
# T31-4: run stub exits 0 after setup (regression guard)
# ---------------------------------------------------------------------------
test_that("run stub exits 0 after setup (regression guard)", {
  skip_if_not(file.exists(cox_cfg))
  od <- tempfile("evolve_smoke_"); dir.create(od)
  run_cli(c("setup", paste0("--config-path=", cox_cfg),
            paste0("--out-dir=", od)))
  expect_equal(run_cli(c("run", paste0("--out-dir=", od))), 0L)
})

# ---------------------------------------------------------------------------
# T31-5: end-to-end scaffolded flow:
#   setup → seed DB → promote (dry-run) → ingest → report
# ---------------------------------------------------------------------------
test_that("end-to-end scaffolded flow: setup → seed DB → promote → ingest → report", {
  skip_if_not(file.exists(cox_cfg))

  # Step 1: setup
  od <- tempfile("evolve_smoke_e2e_"); dir.create(od)
  expect_equal(run_cli(c("setup",
                         paste0("--config-path=", cox_cfg),
                         paste0("--out-dir=", od))), 0L)

  # Step 2: seed a synthetic PROGRAM_DB.jsonl with 2 gate-passing variants.
  # var_00001 has higher fitness so it is the top-K winner that gets promoted.
  db_path <- file.path(od, "PROGRAM_DB.jsonl")
  db_append(db_path, make_db_record(
    variant_id       = "var_00001",
    generation       = 0L,
    slot_kind        = "feature_set",
    proposal_payload = list(feature_set_expr = c("x1", "x2", "x3")),
    parent_ids       = character(), seed_block = 1L, llm_response_id = "smoke",
    screen = list(gate_pass       = TRUE,
                  primary_fitness = 0.7,
                  scalars         = list(my_metric = 0.65, c_index = 0.65,
                                         abs_bias  = 0.1,  coverage = 0.94),
                  gate_failures   = character())
  ))
  db_append(db_path, make_db_record(
    variant_id       = "var_00002",
    generation       = 0L,
    slot_kind        = "feature_set",
    proposal_payload = list(feature_set_expr = c("x1", "x2")),
    parent_ids       = character(), seed_block = 1L, llm_response_id = "smoke",
    screen = list(gate_pass       = TRUE,
                  primary_fitness = 0.5,
                  scalars         = list(my_metric = 0.6, c_index = 0.6,
                                         abs_bias  = 0.1, coverage = 0.93),
                  gate_failures   = character())
  ))

  # Step 3: promote --dry-run (writes manifest, does not dispatch runners)
  expect_equal(run_cli(c("promote",
                         paste0("--config-path=", cox_cfg),
                         paste0("--out-dir=", od),
                         "--dry-run")), 0L)
  manifest_path <- file.path(od, "promote_manifest.json")
  expect_true(file.exists(manifest_path))

  # Step 4: write fake full-tier results at the literal path from the config.
  # synthetic_cox config uses:
  #   results_file_pattern: /tmp/synth_cox_smoke_var.rds
  # That path has no ${...} tokens, so resolve_results_path() returns it
  # verbatim for every manifest row. All variants get the same fake frame.
  pattern_out <- "/tmp/synth_cox_smoke_var.rds"
  if (!dir.exists(dirname(pattern_out))) {
    skip("Cannot write to /tmp — skipping ingest + report steps")
  }
  saveRDS(
    data.frame(my_metric = c(0.70, 0.72, 0.68),
               c_index   = c(0.70, 0.72, 0.68),
               abs_bias  = c(0.05, 0.08, 0.06),
               coverage  = c(0.95, 0.95, 0.96)),
    pattern_out
  )

  # Step 5: ingest — pulls fake results into DB full slot
  expect_equal(run_cli(c("ingest",
                         paste0("--config-path=", cox_cfg),
                         paste0("--out-dir=", od))), 0L)

  # At least one DB record should now have a full$primary_fitness entry
  rows <- db_read(db_path)
  any_full <- any(vapply(rows,
                         function(r) !is.null(r$full$primary_fitness),
                         logical(1)))
  expect_true(any_full)

  # Step 6: report — leaderboard.md + top_feature_frequencies.pdf
  expect_equal(run_cli(c("report",
                         paste0("--config-path=", cox_cfg),
                         paste0("--out-dir=", od))), 0L)
  expect_true(file.exists(file.path(od, "leaderboard.md")))
  # slot.kind = feature_set → plot file must be produced
  expect_true(file.exists(file.path(od, "top_feature_frequencies.pdf")))
})
