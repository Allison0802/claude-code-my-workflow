---
name: method-evolve
description: Evolutionary variant search engine for R-based Monte Carlo evaluators. Runs a generation-chunked FunSearch-style loop where a Claude subagent proposes feature_set / hyperparameter / formula variants, a grammar validator filters ill-formed proposals, and a configurable Monte Carlo evaluator scores survivors against hard statistical gates and a named fitness template. Slot-kind-agnostic at the engine level; domain-specific content lives in per-run `config.yaml` + `examples/`. In-session resumable via `EVOLVE_STATE.json`. Compute backends — `local`, `slurm`, `custom` — print commands rather than auto-submit (user reviews). Use when the user says "evolve the feature set", "search for better covariates", "run method-evolve", or wants to explore variant designs systematically under fixed correctness gates.
---

# method-evolve

Evolutionary variant search for statistical estimators. General-purpose: brings a Claude-Code-managed proposer + validator + Monte Carlo evaluator loop to any R project with a per-variant evaluator script and pre-computed baseline RDS files.

## Quick reference — 7 entry points

| Command | Purpose |
|---|---|
| `cli.R scan --config-path=PATH` | Summarize a config; sanity-check before setup. |
| `cli.R prereq --config-path=PATH` | Run all Phase -1 prereq checks declared in config. |
| `cli.R setup --config-path=PATH --out-dir=DIR [--refreeze]` | Initialize run folder; freeze config_sha into EVOLVE_STATE.json. |
| `cli.R run --out-dir=DIR [--max-gens=N]` | Execute the evolution loop over generations. |
| `cli.R promote --out-dir=DIR [--dry-run]` | Promote top-K screen winners to the full tier. |
| `cli.R ingest --out-dir=DIR` | Pull full-tier results into PROGRAM_DB.jsonl. |
| `cli.R report --out-dir=DIR` | Generate leaderboard.md + slot-kind-aware plots. |

Spec reference: `quality_reports/specs/2026-04-21_method-evolve-design-v3-general.md`.

## Slot kinds shipped in v1

Three validators + proposer templates + toy examples:

- **`feature_set`** — variant is a chr vector of R model-formula terms, e.g. `c("x1", "log(x2)", "x1*x3")`. Grammar: whitelist + typed transforms (`log`/`sqrt`/`I(x^2)`/`ns(x, df=N)`) + pairwise-or-none interactions + `max_terms` + `forbidden_patterns`. See `examples/synthetic_cox/`.
- **`hyperparameters`** — variant is a named list of parameter values. JSON-schema-style validator: `integer`/`numeric` ranges, `categorical` enums, `log_scale` documentation hint. See `examples/hyperparameters_toy/`.
- **`formula`** — variant is a single R formula string with fixed LHS. RHS is walked via the `feature_set` grammar. See `examples/formula_toy/`.

## Prerequisite types (Phase -1)

Each `config.prerequisites[]` entry is type-tagged; the dispatcher picks the right check:

- **`source-patch`** — verify a version-stamped patch has been applied to the evaluator script (`# <marker>-patch-version: N`). Idempotent on re-run.
- **`sidecar-meta`** — verify named baseline RDS files have `.meta.json` sidecars whose `scenario_name`/`n_subjects`/`n_sims` match config.
- **`column-presence`** — run the evaluator in smoke mode (overridden `smoke_env_vars`) and verify named columns exist, are numeric, and have no `NA`.
- **`custom`** — user-supplied shell string; non-zero exit => fail. Escape hatch for project-specific checks.

## Fitness templates

`config.fitness.primary` is one of:

- **`direct_metric`** — fitness = `target` column (negated if `direction = lower_is_better`).
- **`recovery_ratio`** — fitness = `(target - lower) / (upper - lower)`, with inverted sign under `lower_is_better`. Degenerate denominator -> per-variant fallback metric (supports `neg:` prefix) capped at `cap`.
- **`weighted_sum`** — fitness = `sum(weight_i * metric_i)`.
- **`expr`** — raw rlang expression evaluated against the per-variant + named-baseline bindings (`<baseline>.<col>` keys).

## Compute backends

`config.compute.<screen|full>.backend` is one of:

- **`local`** — `parallel::mclapply` per-child Rscript subprocess. Good for screen tier on any machine.
- **`slurm`** — renders `env KEY=VAL sbatch --array=0 <submit_script>` commands and **prints them** (does not auto-submit). Users review and run manually. Full tier on clusters.
- **`custom`** — substitutes `${VARIANT_PATH}/${VARIANT_ID}/${SEED_BLOCK}/${SCENARIO_NAME}` in `submit_cmd` and runs via `system()`. Non-zero exit logs a warning but doesn't halt the batch.

## Reference example

`examples/synthetic_cox/` — ~60-line `toy_evaluator.R` simulating Cox-survival data, + pre-computed `baselines/{lower,upper}.rds` and `.meta.json`, + `config.yaml` using every v3 feature. This is the skill's smoke-test target (no external dependencies beyond the `survival` package). Run `cli.R prereq -> setup -> run -> promote -> ingest -> report` against it to verify the full loop.

## Reviewer backend (Codex / subagent fallback)

Per `.claude/rules/codex-fallback-protocol.md`: the proposer always uses a Claude subagent with `model: "opus"` (Codex MCP is not wired for this skill — no `REVIEWER_BACKEND` knob). Proposer prompts live in `R/proposer/templates/<slot_kind>.md`.

## Reproducibility checklist

- `here::here()` for all paths (anchored at parent repo root).
- `set.seed(YYYYMMDD)` once at the top of stochastic test code.
- Per-child seed derived deterministically as `xxhash32(parent_seed/variant_id)` — any variant can be bit-exactly re-run.
- `config_sha` frozen at setup into `EVOLVE_STATE.json`; any mid-run config drift requires explicit `--refreeze`.
- Parent-only DB writer discipline: worker children return records, caller serializes via `db_append`. Variant-ID allocation guarded by `filelock::lock` on `EVOLVE_STATE.json.lock`.
- Atomic state writes via `.tmp -> rename`.

## Files

```
.claude/skills/method-evolve/
├── SKILL.md                             # this file
├── R/
│   ├── cli.R                            # dispatcher: scan/prereq/setup/run/promote/ingest/report
│   ├── config_schema.R                  # validate_config (v3 schema)
│   ├── db.R                             # polymorphic DB records + atomic ID allocation
│   ├── evaluator.R                      # tier-aware gates + fitness-engine integration
│   ├── fitness/templates.R              # direct_metric / recovery_ratio / weighted_sum / expr
│   ├── prereq.R                         # 4 check_* + run_prereq_check dispatcher
│   ├── proposer/
│   │   ├── dispatch.R                   # load/render/parse + format_grammar S3 generic
│   │   └── templates/{feature_set,hyperparameters,formula}.md
│   ├── runner_local.R                   # mclapply + digest-seed per child
│   ├── runner_slurm.R                   # prints sbatch commands
│   ├── runner_custom.R                  # system() on templated submit_cmd
│   ├── runner_dispatch.R                # run_tier(tier, variants, cfg, state)
│   ├── sampler.R                        # top-K + random + gate-failure fallback
│   ├── state.R                          # EVOLVE_STATE.json schema_version=2
│   ├── utils.R                          # %||%, me_log, me_stop, me_skill_root
│   └── validators/
│       ├── dispatch.R                   # validate_proposal switch
│       ├── feature_set.R                # rlang walker
│       ├── formula.R                    # stats::as.formula + RHS delegation
│       └── hyperparameters.R            # JSON-schema-style
├── examples/
│   ├── synthetic_cox/                   # self-contained smoke-test reference (T27-T28)
│   ├── hyperparameters_toy/             # (T29)
│   ├── formula_toy/                     # (T30)
│   └── missing_types_ipw/               # illustrative, not shipped (T2)
└── tests/
    ├── testthat.R
    └── testthat/*.R                     # ~22 files, ~220 assertions
```

---

**Skill status:** v3 general-purpose engine, slot-kind-agnostic, backend-agnostic. Shipped with 3 slot-kind validators + 3 proposer templates + 4 prereq types + 4 fitness templates + 3 compute backends + 1 smoke-tested reference example.
