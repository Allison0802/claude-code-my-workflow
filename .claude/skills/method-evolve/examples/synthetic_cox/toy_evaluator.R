# examples/synthetic_cox/toy_evaluator.R
# emit-extra-metric-patch-version: 1
# Tiny Cox-survival evaluator for method-evolve smoke tests.
#
# Reads VARIANT_FILE (RDS containing list(feature_set_expr = ...)) or
# falls back to a default feature_set, simulates Cox data per N_SUBJECTS,
# fits Cox with the proposed feature_set, returns a data.frame with
# scalar columns: my_metric, c_index, abs_bias, coverage.
#
# Called by method-evolve's driver (scaffold.R) or directly by the
# precompute_baselines.R script for reference baselines.

suppressPackageStartupMessages(library(survival))

`%||%` <- function(a, b) if (is.null(a)) b else a

env <- function(k, default = NULL, type = "character") {
  v <- Sys.getenv(k, unset = NA)
  if (is.na(v) || !nzchar(v)) return(default)
  switch(type,
         integer   = as.integer(v),
         numeric   = as.numeric(v),
         character = v)
}

set.seed(env("SEED_BLOCK", default = 1L, type = "integer") + 20260421L)
n         <- env("N_SUBJECTS", 200L, "integer")
n_sims    <- env("N_SIMS", 50L, "integer")
scenario  <- env("SCENARIO_NAME", "smoke")
variant_f <- env("VARIANT_FILE")
out_path  <- env("RESULTS_PATH",
                 sprintf("/tmp/synth_cox_%s_%s.rds",
                         scenario, env("VARIANT_ID", "var")))

default_fexpr <- c("x1", "x2", "x3")
fexpr <- if (!is.null(variant_f) && file.exists(variant_f)) {
  v <- readRDS(variant_f)
  v$feature_set_expr %||% default_fexpr
} else default_fexpr

# Additional payload shapes supported by the toy evaluator:
hp         <- NULL
formula_s  <- NULL
if (!is.null(variant_f) && file.exists(variant_f)) {
  v <- readRDS(variant_f)
  if (!is.null(v$hyperparameters)) hp <- v$hyperparameters
  if (!is.null(v$formula_str))     formula_s <- v$formula_str
}

simulate_one <- function() {
  X <- matrix(rnorm(n * 6), n, 6); colnames(X) <- paste0("x", 1:6)
  lp <- 0.5 * X[, 1] - 0.3 * X[, 2] + 0.2 * X[, 1] * X[, 3]
  Tt <- rexp(n, rate = exp(lp - max(lp)))
  Cc <- rexp(n, rate = exp(-max(lp)))
  time <- pmin(Tt, Cc); event <- as.integer(Tt <= Cc)
  data.frame(time = time, event = event, X)
}

score_one <- function(fexpr, hp = NULL, formula_s = NULL) {
  d <- simulate_one()
  fml <- if (!is.null(formula_s))
           as.formula(formula_s)
         else {
           rhs <- paste(fexpr, collapse = " + ")
           as.formula(sprintf("Surv(time, event) ~ %s", rhs))
         }
  ctrl <- if (!is.null(hp) && !is.null(hp$iter_max))
            coxph.control(iter.max = as.integer(hp$iter_max))
          else coxph.control()
  fit <- tryCatch(coxph(fml, data = d, control = ctrl),
                  error = function(e) NULL)
  if (is.null(fit))
    return(c(my_metric = NA_real_, c_index = NA_real_,
             abs_bias = NA_real_, coverage = NA_real_))
  cidx <- summary(fit)$concordance[1]
  beta <- coef(fit)
  truth <- c(x1 = 0.5, x2 = -0.3)
  truth_aligned <- truth[names(beta)]
  bias <- mean(abs(beta - truth_aligned), na.rm = TRUE)
  se <- sqrt(diag(vcov(fit)))
  cov_lo <- beta - 1.96 * se
  cov_hi <- beta + 1.96 * se
  cov_ok <- mean(truth_aligned >= cov_lo & truth_aligned <= cov_hi,
                 na.rm = TRUE)
  c(my_metric = as.numeric(cidx), c_index = as.numeric(cidx),
    abs_bias  = as.numeric(bias),  coverage = as.numeric(cov_ok))
}

scores <- replicate(n_sims, score_one(fexpr, hp = hp, formula_s = formula_s),
                    simplify = TRUE)
out <- as.data.frame(t(scores))
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(out, out_path)
message("Wrote ", out_path, " (", nrow(out), " rows)")
