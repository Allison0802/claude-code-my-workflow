test_that("cli version prints semver string", {
  cli_r <- file.path(
    here::here(), ".claude", "skills", "method-evolve", "R", "cli.R"
  )
  out <- system2("Rscript", c(cli_r, "version"),
                 stdout = TRUE, stderr = TRUE)
  expect_match(
    paste(out, collapse = "\n"),
    "method-evolve v[0-9]+\\.[0-9]+\\.[0-9]+"
  )
})

test_that("cli errors non-zero on unknown command", {
  cli_r <- file.path(
    here::here(), ".claude", "skills", "method-evolve", "R", "cli.R"
  )
  code <- suppressWarnings(
    system2("Rscript", c(cli_r, "nonsense"),
            stdout = FALSE, stderr = FALSE)
  )
  expect_gt(code, 0)
})
