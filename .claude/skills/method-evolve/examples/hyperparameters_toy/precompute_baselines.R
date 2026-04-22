# examples/hyperparameters_toy/precompute_baselines.R
# Reuses toy_evaluator's score_one() with hp$iter_max override.
suppressPackageStartupMessages({ library(survival); library(jsonlite); library(here) })

evaluator_dir <- file.path(here::here(), ".claude", "skills", "method-evolve",
                            "examples", "synthetic_cox")
source(file.path(evaluator_dir, "toy_evaluator.R"))

out_dir <- file.path(here::here(), ".claude", "skills", "method-evolve",
                      "examples", "hyperparameters_toy", "baselines")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Reset hp to ensure the default-fexpr branch runs for baselines, but
# vary iter_max to generate distinct upper / lower summaries.
fexpr <- default_fexpr  # c("x1","x2","x3")

write_one <- function(name, iter_max) {
  set.seed(20260421L)
  scores <- replicate(n_sims,
    score_one(fexpr, hp = list(iter_max = as.integer(iter_max))),
    simplify = TRUE)
  df <- as.data.frame(t(scores))
  saveRDS(df, file.path(out_dir, paste0(name, ".rds")))
  jsonlite::write_json(list(
    scenario_name = scenario, n_subjects = n, n_sims = n_sims,
    dgp_version = "synth-cox-v1", evaluator_sha = "toy-001",
    emit_extra_metric_patch_version = 1,
    iter_max_used = as.integer(iter_max),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  ), file.path(out_dir, paste0(name, ".meta.json")),
                        auto_unbox = TRUE, pretty = TRUE)
  message("  wrote ", name, ".rds (iter_max=", iter_max, ")")
}

write_one("lower", iter_max = 3L)     # poorly-converged
write_one("upper", iter_max = 200L)   # fully-converged
message("hyperparameters_toy precompute: done")
