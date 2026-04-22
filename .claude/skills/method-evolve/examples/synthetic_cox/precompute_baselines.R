# examples/synthetic_cox/precompute_baselines.R
# Generate baselines/{lower,upper}.rds + meta.json for the synthetic Cox toy.
#
# upper = oracle-ish feature set c("x1","x2","x3")
# lower = single weak feature  c("x1")
# Both use the same DGP (simulate_one) and n_sims/n_subjects/scenario
# pulled from env vars via toy_evaluator.R.

suppressPackageStartupMessages({
  library(survival)
  library(jsonlite)
  library(here)
})

skill_dir <- file.path(here::here(), ".claude", "skills", "method-evolve",
                       "examples", "synthetic_cox")
source(file.path(skill_dir, "toy_evaluator.R"))

out_dir <- file.path(skill_dir, "baselines")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

write_one <- function(name, fexpr) {
  set.seed(20260421L)
  scores <- replicate(n_sims, score_one(fexpr), simplify = TRUE)
  df <- as.data.frame(t(scores))
  rds_path  <- file.path(out_dir, paste0(name, ".rds"))
  meta_path <- file.path(out_dir, paste0(name, ".meta.json"))
  saveRDS(df, rds_path)
  jsonlite::write_json(list(
    scenario_name  = scenario,
    n_subjects     = n,
    n_sims         = n_sims,
    dgp_version    = "synth-cox-v1",
    evaluator_sha  = "toy-001",
    emit_extra_metric_patch_version = 1,
    created_at     = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  ), meta_path, auto_unbox = TRUE, pretty = TRUE)
  message("  wrote ", rds_path, " + ", meta_path)
}

message("precompute_baselines: n_subjects=", n, " n_sims=", n_sims,
        " scenario=", scenario)
write_one("upper", c("x1", "x2", "x3"))
write_one("lower", c("x1"))
message("precompute_baselines: done")
