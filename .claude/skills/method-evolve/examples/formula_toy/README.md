# examples/formula_toy — minimal formula-space demo

Reuses `examples/synthetic_cox/toy_evaluator.R`, which also
honors `payload$formula_str` (extended in T29). This toy searches
R-formula variants with fixed LHS `Surv(time, event)` and a
whitelist of 6 predictors.

## Baselines

- `lower`: `Surv(time, event) ~ x1`
- `upper`: `Surv(time, event) ~ x1 + x2 + x3`

## Running

```
Rscript .claude/skills/method-evolve/examples/formula_toy/precompute_baselines.R
Rscript .claude/skills/method-evolve/R/cli.R scan \
  --config-path=.claude/skills/method-evolve/examples/formula_toy/config.yaml
Rscript .claude/skills/method-evolve/R/cli.R prereq \
  --config-path=.claude/skills/method-evolve/examples/formula_toy/config.yaml
```
