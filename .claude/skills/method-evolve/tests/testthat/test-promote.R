library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "db.R"))
source(file.path(r_dir, "runner_local.R"))
source(file.path(r_dir, "runner_slurm.R"))
source(file.path(r_dir, "runner_custom.R"))
source(file.path(r_dir, "runner_dispatch.R"))
source(file.path(r_dir, "promote.R"))

mk_record <- function(id, fit, pass = TRUE) {
  make_db_record(variant_id = id, generation = 0L,
                 slot_kind = "feature_set",
                 proposal_payload = list(feature_set_expr = "x1"),
                 parent_ids = character(), seed_block = 1L,
                 llm_response_id = "x",
                 screen = list(gate_pass = pass,
                               primary_fitness = fit,
                               scalars = list(),
                               gate_failures = character()))
}

mk_out_dir <- function() {
  od <- tempfile(); dir.create(od)
  db_path <- file.path(od, "PROGRAM_DB.jsonl")
  db_append(db_path, mk_record("var_00001", 0.9))
  db_append(db_path, mk_record("var_00002", 0.8))
  db_append(db_path, mk_record("var_00003", 0.99, pass = FALSE))  # gate fail
  od
}

mk_cfg <- function(k = 2L, seed_blocks = 2L) {
  list(
    budget = list(promote_top_k = k),
    compute = list(full = list(backend = "local", seed_blocks = seed_blocks)),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke")),
    paths = list(variants_dir = "variants")
  )
}

test_that("build_promote_manifest selects top-K gate-passers", {
  od <- mk_out_dir()
  m <- build_promote_manifest(mk_cfg(k = 2L, seed_blocks = 1L), od)
  expect_length(m$rows, 2L)
  # Top-2 by primary_fitness (excluding gate failers) → var_00001, var_00002
  ids <- vapply(m$rows, function(r) r$variant_id, character(1))
  expect_setequal(ids, c("var_00001", "var_00002"))
})

test_that("build_promote_manifest expands seed_blocks", {
  od <- mk_out_dir()
  m <- build_promote_manifest(mk_cfg(k = 2L, seed_blocks = 3L), od)
  expect_length(m$rows, 6L)  # 2 variants × 3 seed_blocks
  # Each variant appears 3 times with seed_block 1, 2, 3
  sbs <- vapply(m$rows[1:3], function(r) r$seed_block, integer(1))
  expect_setequal(sbs, 1:3)
})

test_that("promote_run dry_run writes manifest without dispatching", {
  od <- mk_out_dir()
  r <- promote_run(mk_cfg(), od, dry_run = TRUE)
  expect_false(r$submitted)
  expect_true(file.exists(r$manifest_path))
  m <- jsonlite::fromJSON(r$manifest_path, simplifyVector = FALSE)
  expect_length(m, 4L)  # 2 winners × 2 seed_blocks
})

test_that("promote_run with empty DB returns 0 rows gracefully", {
  od <- tempfile(); dir.create(od)
  # Empty DB
  writeLines(character(), file.path(od, "PROGRAM_DB.jsonl"))
  r <- promote_run(mk_cfg(), od, dry_run = TRUE)
  expect_equal(r$rows, 0L)
  expect_false(r$submitted)
})

test_that("build_promote_manifest errors on missing DB", {
  od <- tempfile(); dir.create(od)
  expect_error(build_promote_manifest(mk_cfg(), od), "DB missing")
})
