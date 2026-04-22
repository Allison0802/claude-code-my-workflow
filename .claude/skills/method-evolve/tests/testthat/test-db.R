library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "db.R"))

mk_record <- function(id, kind, payload, fit = 0.5, pass = TRUE) {
  make_db_record(
    variant_id = id, generation = 0L, slot_kind = kind,
    proposal_payload = payload, parent_ids = character(),
    seed_block = 1L, llm_response_id = "x",
    screen = list(gate_pass = pass, primary_fitness = fit,
                  scalars = list(), gate_failures = character()))
}

test_that("make_db_record stores polymorphic payload by slot_kind", {
  r1 <- mk_record("var_00001", "feature_set",
                   list(feature_set_expr = c("x1", "log(x2)")))
  expect_equal(r1$slot_kind, "feature_set")
  expect_equal(r1$proposal_payload$feature_set_expr, c("x1", "log(x2)"))

  r2 <- mk_record("var_00002", "hyperparameters",
                   list(hyperparameters = list(mtry = 5L)))
  expect_equal(r2$proposal_payload$hyperparameters$mtry, 5L)

  r3 <- mk_record("var_00003", "formula",
                   list(formula_str = "Surv(time, event) ~ x1"))
  expect_equal(r3$proposal_payload$formula_str,
               "Surv(time, event) ~ x1")
})

test_that("db_append writes one JSONL line and db_read round-trips", {
  tmp <- tempfile(fileext = ".jsonl")
  db_append(tmp, mk_record("var_00001", "feature_set",
                            list(feature_set_expr = c("x1"))))
  expect_length(readLines(tmp), 1L)
  rows <- db_read(tmp)
  expect_equal(rows[[1]]$variant_id, "var_00001")
  expect_equal(rows[[1]]$slot_kind, "feature_set")
})

test_that("db_append is append-only", {
  tmp <- tempfile(fileext = ".jsonl")
  db_append(tmp, mk_record("var_00001", "feature_set",
                            list(feature_set_expr = c("x1"))))
  db_append(tmp, mk_record("var_00002", "feature_set",
                            list(feature_set_expr = c("x2"))))
  rows <- db_read(tmp)
  expect_length(rows, 2L)
  expect_equal(rows[[1]]$variant_id, "var_00001")
  expect_equal(rows[[2]]$variant_id, "var_00002")
})

test_that("db_top_k excludes gate-failers and ranks by primary_fitness", {
  tmp <- tempfile(fileext = ".jsonl")
  db_append(tmp, mk_record("a", "feature_set",
                            list(feature_set_expr = "x"),
                            fit = 0.9, pass = TRUE))
  db_append(tmp, mk_record("b", "feature_set",
                            list(feature_set_expr = "y"),
                            fit = 0.5, pass = TRUE))
  db_append(tmp, mk_record("c", "feature_set",
                            list(feature_set_expr = "z"),
                            fit = 0.99, pass = FALSE))  # gate fail
  top <- db_top_k(tmp, k = 5L, metric = "primary_fitness")
  expect_length(top, 2L)
  expect_equal(top[[1]]$variant_id, "a")
  expect_equal(top[[2]]$variant_id, "b")
})

test_that("allocate_variant_ids returns contiguous block and updates state", {
  tdir <- tempfile(); dir.create(tdir)
  lock  <- file.path(tdir, "state.json.lock")
  state <- file.path(tdir, "state.json")
  writeLines(jsonlite::toJSON(list(last_variant_id = 42L),
                               auto_unbox = TRUE), state)
  ids <- allocate_variant_ids(state, lock_path = lock, count = 3L)
  expect_equal(ids, c("var_00043", "var_00044", "var_00045"))
  s <- jsonlite::fromJSON(paste(readLines(state), collapse = "\n"),
                           simplifyVector = FALSE)
  expect_equal(s$last_variant_id, 45L)
})

test_that("allocate_variant_ids initializes from empty state", {
  tdir <- tempfile(); dir.create(tdir)
  lock  <- file.path(tdir, "state.json.lock")
  state <- file.path(tdir, "state.json")
  writeLines(jsonlite::toJSON(list(), auto_unbox = TRUE), state)
  ids <- allocate_variant_ids(state, lock_path = lock, count = 2L)
  expect_equal(ids, c("var_00001", "var_00002"))
})

test_that("rewrite_db_atomically preserves unchanged + patches matching", {
  tmp <- tempfile(fileext = ".jsonl")
  db_append(tmp, mk_record("var_00001", "feature_set",
                            list(feature_set_expr = "x"), fit = 0.5))
  db_append(tmp, mk_record("var_00002", "feature_set",
                            list(feature_set_expr = "y"), fit = 0.6))
  rewrite_db_atomically(tmp, function(r) {
    if (r$variant_id == "var_00001") {
      r$full <- list(primary_fitness = 0.81, scalars = list(),
                     gate_pass = TRUE, gate_failures = character())
    }
    r
  })
  rows <- db_read(tmp)
  expect_length(rows, 2L)
  matched <- Filter(function(r) r$variant_id == "var_00001", rows)[[1]]
  expect_equal(matched$full$primary_fitness, 0.81)
})
