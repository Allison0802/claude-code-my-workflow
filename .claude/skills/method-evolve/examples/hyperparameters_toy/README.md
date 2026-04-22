# examples/hyperparameters_toy — minimal hyperparameter-space demo

Reuses `examples/synthetic_cox/toy_evaluator.R`. The evaluator now
honors `payload$hyperparameters$iter_max` (via `coxph.control`), so
this toy varies `iter_max ∈ [3, 200]` as a 1-D hyperparameter search.

## Baselines

- `lower`: `iter_max = 3` → often-not-converged fit.
- `upper`: `iter_max = 200` → fully converged.

## Running

```
Rscript .claude/skills/method-evolve/examples/hyperparameters_toy/precompute_baselines.R
Rscript .claude/skills/method-evolve/R/cli.R scan \
  --config-path=.claude/skills/method-evolve/examples/hyperparameters_toy/config.yaml
Rscript .claude/skills/method-evolve/R/cli.R prereq \
  --config-path=.claude/skills/method-evolve/examples/hyperparameters_toy/config.yaml
```

Follow-up: baseline separation between `iter_max = 3` and `iter_max = 200`
on this well-conditioned DGP is typically small. If `denom_floor_epsilon`
trips, widen the range or change the `target` column to one that's
more iter-sensitive.
