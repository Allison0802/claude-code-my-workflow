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
