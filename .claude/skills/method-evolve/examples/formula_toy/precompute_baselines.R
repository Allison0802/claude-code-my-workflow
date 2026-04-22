# examples/formula_toy/precompute_baselines.R
# Reuses toy_evaluator's score_one() with formula_s override.
suppressPackageStartupMessages({ library(survival); library(jsonlite); library(here) })

evaluator_dir <- file.path(here::here(), ".claude", "skills", "method-evolve",
                            "examples", "synthetic_cox")
source(file.path(evaluator_dir, "toy_evaluator.R"))

out_dir <- file.path(here::here(), ".claude", "skills", "method-evolve",
                      "examples", "formula_toy", "baselines")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

write_one <- function(name, formula_s) {
  set.seed(20260421L)
  scores <- replicate(n_sims,
    score_one(fexpr = character(0), formula_s = formula_s),
    simplify = TRUE)
  df <- as.data.frame(t(scores))
  saveRDS(df, file.path(out_dir, paste0(name, ".rds")))
  jsonlite::write_json(list(
    scenario_name = scenario, n_subjects = n, n_sims = n_sims,
    dgp_version = "synth-cox-v1", evaluator_sha = "toy-001",
    emit_extra_metric_patch_version = 1,
    formula_used = formula_s,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  ), file.path(out_dir, paste0(name, ".meta.json")),
                        auto_unbox = TRUE, pretty = TRUE)
  message("  wrote ", name, ".rds (formula='", formula_s, "')")
}

write_one("lower", "Surv(time, event) ~ x1")
write_one("upper", "Surv(time, event) ~ x1 + x2 + x3")
message("formula_toy precompute: done")
