# examples/synthetic_cox — self-contained smoke-test reference

This folder is the method-evolve skill's default smoke-test target.
Zero external deps beyond the `survival` package; the DGP is baked
into the evaluator.

## Structure

```text
synthetic_cox/
├── toy_evaluator.R             # ~60-line Cox simulator (no VARIANT_FILE → default fexpr)
├── precompute_baselines.R      # one-shot: generates baselines/{lower,upper}.{rds,meta.json}
├── config.yaml                 # uses every v3 feature: recovery_ratio fitness, 3 prereq types, 3 gates
├── baselines/
│   ├── upper.rds               # c("x1","x2","x3")  — oracle-like
│   ├── upper.meta.json
│   ├── lower.rds               # c("x1")             — weak single-feature
│   └── lower.meta.json
├── templates/
│   └── emit_extra_metric.patch # demo prereq patch (no-op; illustrative)
└── README.md
```

## Running the loop

```bash
# (one-time) generate baselines
SCENARIO_NAME=smoke N_SIMS=50 N_SUBJECTS=200 \
  Rscript .claude/skills/method-evolve/examples/synthetic_cox/precompute_baselines.R

# the skill's CLI path
CLI=.claude/skills/method-evolve/R/cli.R
CFG=.claude/skills/method-evolve/examples/synthetic_cox/config.yaml
RUN=/tmp/synth_cox_run

Rscript $CLI prereq  --config-path=$CFG
Rscript $CLI setup   --config-path=$CFG --out-dir=$RUN
Rscript $CLI run     --out-dir=$RUN --max-gens=2
Rscript $CLI promote --config-path=$CFG --out-dir=$RUN --dry-run
Rscript $CLI ingest  --config-path=$CFG --out-dir=$RUN
Rscript $CLI report  --config-path=$CFG --out-dir=$RUN
```

## What gets exercised

- **prereq:** 3 types in one run — `custom` (grep for patch marker),
  `sidecar-meta` (baseline meta sanity), `column-presence` (evaluator
  emits required columns).
- **setup:** freezes `config_sha` into `EVOLVE_STATE.json` (schema v2).
- **run:** currently a stub; full loop wiring is a future task.
- **promote:** `--dry-run` writes `promote_manifest.json`.
- **ingest:** pulls full-tier results into DB via `rewrite_db_atomically`.
- **report:** writes `leaderboard.md` + `top_feature_frequencies.pdf`.

## Baseline separation

The baseline setup is designed so that `recovery_ratio` is well-defined
for intermediate variants: `upper.my_metric` (oracle set x1+x2+x3) mean
≈ 0.66, `lower.my_metric` (single x1) mean ≈ 0.63, so the denominator
gap is ≈ 0.03 — comfortably above the `denom_floor_epsilon = 0.002`.

## Follow-ups

- `source-patch` prereq type currently uses the T1 IBS-specific marker
  regex (`# ibs-patch-version:`); a configurable marker name would let
  this example use `source-patch` directly instead of the `custom` grep
  workaround. Noted in the skill's plan as a v2 item.
- `evaluator.results_file_pattern` is not yet interpolated by the
  `column-presence` prereq check — tokens like `${SCENARIO_NAME}` /
  `${VARIANT_ID}` are passed through literally. For now the config
  pins a literal smoke path (`/tmp/synth_cox_smoke_var.rds`).
