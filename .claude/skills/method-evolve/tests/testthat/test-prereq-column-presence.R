library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "prereq.R"))

write_dummy_eval <- function(tdir, cols = c("a", "b"), with_na = FALSE) {
  script <- file.path(tdir, "dummy.R")
  writeLines(sprintf(
    "df <- data.frame(%s)\nsaveRDS(df, '%s')",
    paste(sprintf("%s = %s", cols,
                  if (with_na) "c(1, NA)" else "1:2"),
          collapse = ", "),
    file.path(tdir, "out.rds")), script)
  script
}

test_that("check_column_presence passes when all named columns appear", {
  tdir <- tempfile(); dir.create(tdir)
  script <- write_dummy_eval(tdir, cols = c("metric", "c_index"))
  cfg <- list(
    target_script = script,
    evaluator = list(
      env_vars = list(),
      results_file_pattern = file.path(tdir, "out.rds")
    )
  )
  prereq <- list(id = "cols", type = "column-presence",
                 smoke_env_vars = list(),
                 required_columns = c("metric", "c_index"))
  expect_true(check_column_presence(prereq, cfg)$pass)
})

test_that("check_column_presence fails on missing column", {
  tdir <- tempfile(); dir.create(tdir)
  script <- write_dummy_eval(tdir, cols = c("metric"))
  cfg <- list(
    target_script = script,
    evaluator = list(env_vars = list(),
                     results_file_pattern = file.path(tdir, "out.rds"))
  )
  prereq <- list(id = "cols", type = "column-presence",
                 smoke_env_vars = list(),
                 required_columns = c("metric", "c_index"))
  res <- check_column_presence(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "c_index")
})

test_that("check_column_presence fails on NA in required column", {
  tdir <- tempfile(); dir.create(tdir)
  script <- write_dummy_eval(tdir, cols = c("metric"), with_na = TRUE)
  cfg <- list(
    target_script = script,
    evaluator = list(env_vars = list(),
                     results_file_pattern = file.path(tdir, "out.rds"))
  )
  prereq <- list(id = "cols", type = "column-presence",
                 smoke_env_vars = list(), required_columns = c("metric"))
  res <- check_column_presence(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "NA")
})

test_that("check_column_presence fails on non-numeric column", {
  tdir <- tempfile(); dir.create(tdir)
  script_path <- file.path(tdir, "dummy.R")
  out_path    <- file.path(tdir, "out.rds")
  # Write a script that saves a character column
  writeLines(c(
    sprintf("df <- data.frame(metric = c('a','b'), stringsAsFactors = FALSE)"),
    sprintf("saveRDS(df, '%s')", out_path)
  ), script_path)

  cfg <- list(
    target_script = script_path,
    evaluator = list(env_vars = list(),
                     results_file_pattern = out_path)
  )
  prereq <- list(id = "cols", type = "column-presence",
                 smoke_env_vars = list(),
                 required_columns = c("metric"))
  res <- check_column_presence(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "not numeric")
})

test_that("check_column_presence honors smoke_env_vars override over base env_vars", {
  tdir <- tempfile(); dir.create(tdir)
  out_path <- file.path(tdir, "out.rds")
  script_path <- file.path(tdir, "dummy.R")
  # Script reads N_SIMS and writes n_sims as a column so we can verify the override
  writeLines(c(
    "n_sims <- as.integer(Sys.getenv('N_SIMS'))",
    sprintf("df <- data.frame(metric = 1, n_sims_seen = n_sims)"),
    sprintf("saveRDS(df, '%s')", out_path)
  ), script_path)

  cfg <- list(
    target_script = script_path,
    evaluator = list(env_vars = list(N_SIMS = 9999L),
                     results_file_pattern = out_path)
  )
  # smoke override should win
  prereq <- list(id = "cols", type = "column-presence",
                 smoke_env_vars = list(N_SIMS = 2L),
                 required_columns = c("metric", "n_sims_seen"))
  res <- check_column_presence(prereq, cfg)
  expect_true(res$pass)
  df <- readRDS(out_path)
  expect_equal(df$n_sims_seen[1], 2L)  # smoke won, not 9999
})
