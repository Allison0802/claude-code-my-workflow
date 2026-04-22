library(testthat)
r_dir <- file.path(here::here(), ".claude", "skills", "method-evolve", "R")
cli_r <- file.path(r_dir, "cli.R")

run_cli <- function(args, env = character()) {
  env_pre <- paste(env, collapse = " ")
  cmd <- sprintf("%s Rscript %s %s", env_pre, shQuote(cli_r),
                  paste(args, collapse = " "))
  system(cmd, intern = FALSE, ignore.stdout = FALSE,
         ignore.stderr = FALSE)
}

write_min_config <- function(path, out_dir_placeholder = TRUE) {
  yaml::write_yaml(list(
    name = "t",
    target_script = "eval.R",
    prerequisites = list(
      list(id = "noop", type = "custom", check_command = "true")
    ),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke",
                                     N_SIMS = 2L,
                                     N_SUBJECTS = 50L),
                     results_file_pattern = "out.rds"),
    substitutions = list(freeze_on_setup = c("run_date", "name"),
                         per_variant = c("VARIANT_PATH", "VARIANT_ID",
                                          "SEED_BLOCK"),
                         refreeze_behavior = "error"),
    slot = list(kind = "feature_set", max_terms = 5L,
                whitelist = c("x1", "x2"), transforms = list(),
                interactions = "pairwise",
                forbidden_patterns = character()),
    baselines = list(lower = list(results_file = "lower.rds",
                                  meta_file = "lower.meta.json"),
                     upper = list(results_file = "upper.rds",
                                  meta_file = "upper.meta.json")),
    fitness = list(
      primary = list(template = "direct_metric", target = "m",
                     direction = "higher_is_better"),
      recovery = list(denom_floor_epsilon = 0.002,
                      degenerate_scenario_action = "reject_and_halt",
                      degenerate_variant_fallback = list(
                        fallback_metric = "m", cap = 0))
    ),
    gates = list(list(metric = "m", tier = "both", op = "<",
                      threshold = 1.0)),
    budget = list(max_variants = 4L, batch_size = 2L,
                  max_generations = 2L, promote_top_k = 1L,
                  early_stop_after = 2L),
    compute = list(screen = list(backend = "local", n_workers = 1L),
                   full = list(backend = "local")),
    paths = list(out_dir = "out", variants_dir = "out/variants",
                 program_db = "out/db.jsonl",
                 state_file  = "out/state.json")
  ), path)
}

test_that("cli version still works", {
  expect_equal(run_cli(c("version")), 0L)
})

test_that("cli --help exits zero", {
  expect_equal(run_cli(c("--help")), 0L)
})

test_that("cli scan accepts a minimal config", {
  tdir <- tempfile(); dir.create(tdir)
  cfg <- file.path(tdir, "config.yaml")
  write_min_config(cfg)
  expect_equal(run_cli(c("scan",
                          paste0("--config-path=", cfg))), 0L)
})

test_that("cli prereq runs the custom 'true' prereq and exits 0", {
  tdir <- tempfile(); dir.create(tdir)
  cfg <- file.path(tdir, "config.yaml")
  write_min_config(cfg)
  expect_equal(run_cli(c("prereq",
                          paste0("--config-path=", cfg))), 0L)
})

test_that("cli setup initializes EVOLVE_STATE.json", {
  tdir <- tempfile(); dir.create(tdir)
  cfg <- file.path(tdir, "config.yaml"); write_min_config(cfg)
  od  <- file.path(tdir, "run")
  expect_equal(run_cli(c("setup",
                          paste0("--config-path=", cfg),
                          paste0("--out-dir=", od))), 0L)
  expect_true(file.exists(file.path(od, "EVOLVE_STATE.json")))
  s <- jsonlite::fromJSON(file.path(od, "EVOLVE_STATE.json"),
                           simplifyVector = FALSE)
  expect_equal(s$schema_version, 2L)
  expect_equal(s$generation_phase, "proposing")
})

test_that("cli setup errors on config drift without --refreeze", {
  tdir <- tempfile(); dir.create(tdir)
  cfg <- file.path(tdir, "config.yaml"); write_min_config(cfg)
  od  <- file.path(tdir, "run")
  run_cli(c("setup", paste0("--config-path=", cfg),
             paste0("--out-dir=", od)))
  # mutate config — drift the sha
  yaml_current <- yaml::read_yaml(cfg)
  yaml_current$budget$batch_size <- 8L
  yaml::write_yaml(yaml_current, cfg)
  expect_gt(run_cli(c("setup", paste0("--config-path=", cfg),
                        paste0("--out-dir=", od))), 0L)
})

test_that("cli setup with --refreeze accepts drift", {
  tdir <- tempfile(); dir.create(tdir)
  cfg <- file.path(tdir, "config.yaml"); write_min_config(cfg)
  od  <- file.path(tdir, "run")
  run_cli(c("setup", paste0("--config-path=", cfg),
             paste0("--out-dir=", od)))
  yaml_current <- yaml::read_yaml(cfg)
  yaml_current$budget$batch_size <- 8L
  yaml::write_yaml(yaml_current, cfg)
  expect_equal(run_cli(c("setup",
                          paste0("--config-path=", cfg),
                          paste0("--out-dir=", od),
                          "--refreeze")), 0L)
})

test_that("cli run errors when no state present", {
  tdir <- tempfile(); dir.create(tdir)
  expect_gt(run_cli(c("run", paste0("--out-dir=", tdir))), 0L)
})

test_that("cli unknown command exits non-zero", {
  expect_gt(run_cli(c("nonsense")), 0L)
})

test_that("cli promote/ingest/report error with 'not yet implemented'", {
  tdir <- tempfile(); dir.create(tdir)
  cfg <- file.path(tdir, "config.yaml"); write_min_config(cfg)
  od  <- file.path(tdir, "run")
  run_cli(c("setup", paste0("--config-path=", cfg),
             paste0("--out-dir=", od)))
  expect_gt(run_cli(c("promote", paste0("--out-dir=", od))), 0L)
  expect_gt(run_cli(c("ingest",  paste0("--out-dir=", od))), 0L)
  expect_gt(run_cli(c("report",  paste0("--out-dir=", od))), 0L)
})
