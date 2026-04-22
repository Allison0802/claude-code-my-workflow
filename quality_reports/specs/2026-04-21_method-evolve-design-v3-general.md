# `method-evolve` Skill — Design Specification (v3, general)

**Status:** DRAFT — Round 3 rewrite, no specific sub-project assumed
**Author:** drafted with Claude (brainstorming skill)
**Date:** 2026-04-21
**Supersedes:** `2026-04-21_method-evolve-design-v2.md` (same-day v2, Missing-Types-flavored)
**Related paper:** Tsinghua FIB Lab, *AutoSOTA: An End-to-End Automated Research System for SOTA Model Discovery* (2026)

---

## Rewrite changes applied (v2 → v3 — general)

This revision removes all project-specific anchoring from the v2 spec. The evolutionary engine, program DB, sampler, resumability contract, and runtime discipline are unchanged in shape. What changed:

- **§1 (Goal).** The v1 target is no longer "IPW propensity feature-set search in Missing Types." The skill is a general search engine: any R evaluator that emits named scalar metrics per variant can be searched.
- **§2 (Non-goals).** Unchanged in structure; the target-estimator and target-sub-project non-goals are dropped because no estimator or sub-project is assumed.
- **§3 (Architecture).** Reusability claim retuned: the skill is domain-agnostic for three named slot kinds in v1 (`feature_set`, `hyperparameters`, `formula`), each carrying its own validator + proposer template.
- **§5 (Phase −1 prerequisites).** Generalized from a hardcoded Brier-score patch to a **patch applicator** driven by user-supplied patch templates and version-stamped files. The IBS-specific patch moves to an example.
- **§6 (Slot grammar).** Expanded from one slot kind to three. Each kind has a dedicated validator and proposer-prompt template under `templates/` in the skill.
- **§7 (Config schema).** Baselines are a **named map**, not hardcoded `oracle`/`CCA`. Metric names are user-defined throughout. Fitness is expressed as a **named template** or a **raw R expression** over per-variant scalars plus named-baseline scalars.
- **§8 (Fitness evaluation).** Three named templates (`direct_metric`, `recovery_ratio`, `weighted_sum`) all desugar to a raw expression evaluated with `rlang`. Denominator-floor and per-variant fallback semantics retained but re-phrased around the named `lower`/`upper` baselines.
- **§10 (Proposer).** Three prompt templates (`templates/proposer/feature_set.md`, `hyperparameters.md`, `formula.md`). The `model: "opus"` requirement and JSON parse contract are unchanged.
- **§11 (Runtime).** Compute backends become configurable strings (`local` | `slurm` | `custom`). Both tiers (screen, full) accept any backend. `promote`/`ingest` semantics retained.
- **§14 (Reference example).** Replaced the Missing-Types/IPW example with a self-contained synthetic toy (`examples/synthetic_cox/`) that the smoke test runs against. The Missing-Types IBS example moves under `examples/missing_types_ipw/` as an illustrative project-flavored config.

No v1 hard constraint was dropped. The evolutionary loop, gates-as-MC-critic, and in-session resumability envelope are identical in scope.

---

## 1. Goal

A Claude Code skill that applies an **evolutionary code-search loop** (FunSearch / AlphaEvolve pattern) to statistical methods implemented as R Monte Carlo scripts. The skill introspects a target sub-project, interviews the user to fill gaps, generates a project-specific configuration, and drives a generation-chunked search that proposes, evaluates, and ranks variants against hard statistical gates encoded in that configuration.

**v1 target:** any R evaluator that (a) takes a per-variant input file (feature list, hyperparameter JSON, or formula string), (b) runs a Monte Carlo simulation with user-specified `N_SIMS` and scenario parameters, and (c) writes a results RDS whose data frame contains named scalar metric columns. The skill contains no knowledge of the target's statistical content — no specific estimator, metric, baseline, or scenario is assumed.

Concretely, v1 is useful for: searching over propensity-model covariate sets, searching over random-forest hyperparameters, searching over Cox/GLM/GAM formula specifications, or any combination of those three slot kinds applied to an existing R Monte Carlo harness.

---

## 2. Non-goals (explicitly out of scope for v1)

- Auto-discovery of method improvements from raw PDFs (AutoSOTA phases 1–2).
- Additional slot kinds beyond `feature_set`, `hyperparameters`, `formula`. The engine exposes a pluggable slot-kind interface, but v1 ships only those three and errors cleanly on unknown kinds.
- Mixing multiple slot kinds inside one run. A single run searches over exactly one `slot.kind`.
- Multi-island or MAP-Elites samplers.
- Direct Anthropic API proposer (Task-tool subagent only).
- GPT / Codex reviewer loop on variants. Monte Carlo is the critic.
- Automated SSH / `sbatch` submission. `promote` prints commands; the user runs them.
- Docker-based environment grounding, paper-to-code grounding, or any of the AutoSOTA infrastructure stages 1–2.
- Language agnosticism. The evaluator must be an R script.

---

## 3. Architecture

**Two-layer split:**

```
┌────────────────────────────────────────────────────────────────┐
│  method-evolve skill (parent repo)                             │
│    .claude/skills/method-evolve/                               │
│      SKILL.md, workflow phases, DB format, sampler,            │
│      validators (3x), proposer templates (3x),                 │
│      patch applicator, report generator,                       │
│      examples/synthetic_cox/  (smoke-test config)              │
└────────────────────────────────────────────────────────────────┘
                           │ reads
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  config.yaml (project-specific, generated by Phase 0–1)        │
│    <subproject>/quality_reports/evolve/YYYY-MM-DD_<name>[-NN]/ │
└────────────────────────────────────────────────────────────────┘
                           │ drives
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  Generated driver (per-run, project-specific)                  │
│    <subproject>/scripts/R/evolve_<name>_driver.R               │
│    <subproject>/scripts/<backend>/evolve_<name>_promote.sh     │
└────────────────────────────────────────────────────────────────┘
```

**Domain-agnosticism claim.** The skill is domain-agnostic for the three shipped slot kinds (`feature_set`, `hyperparameters`, `formula`). Additional slot kinds require a new grammar validator + a new proposer-prompt template + a new example smoke-test config, all in the skill repo. The skill contains zero knowledge of any specific metric, baseline, scenario, estimator, or sub-project.

**Key invariant for v1.** All domain knowledge (what columns exist in the evaluator output, what the baselines are called, what gates apply) flows through `config.yaml` and the user's evaluator script. The skill reads scalar numbers by name and applies configured logic to them. Nothing in the skill's code mentions any specific statistical concept beyond "scalar", "gate", "baseline", "recovery ratio", and "Monte Carlo seed block".

---

## 4. Workflow — entry points

Checkpointed, resumable:

```
/method-evolve scan    <subproject>       # Phase 0:  introspect, draft config
/method-evolve prereq                     # Phase -1: verify/apply upstream patches
/method-evolve setup   <name>             # Phase 1+2: interview, scaffold, smoke
/method-evolve run     [max_gens: N]      # Phase 3:  advance N generations
/method-evolve promote                    # Phase 4a: emit promote-wrapper commands
/method-evolve ingest                     # Phase 4b: import remote results into DB
/method-evolve report                     # Phase 4c: leaderboard + final report
```

`setup` calls `prereq` internally and **refuses to continue** until every prerequisite check passes (see §5). `prereq` is also exposed standalone.

CLI `max_gens` overrides `config.yaml.budget.max_generations` for a single invocation. This precedence is documented in the skill's `--help` output.

---

## 5. Phase −1: Prerequisites (generic patch applicator)

Prerequisites are upstream changes that must land in the target sub-project before any MC evaluation will produce the fields the skill needs. They are tracked as an ordered list in `config.prerequisites`; `prereq` runs the checks in order, reports pass/fail, and when it can apply a patch mechanically it offers to do so.

### 5.1 Prerequisite types

Three built-in types; all other mechanisms are user-written custom checks.

**`source-patch`** — apply a diff to a specific file, detect idempotently via a version-stamp header comment.

| Field | Purpose |
|---|---|
| `target` | Path relative to sub-project root |
| `required_version` | Integer. Must match the value in the target's stamp comment. |
| `patch_template` | Name of file under the skill's `templates/` or project's supplied path |
| `stamp_marker` | Regex to locate the stamp, default `^#\s*<id>-patch-version:\s*(\d+)` |

Detection logic:

1. If the target file does not contain a line matching `stamp_marker`, the patch has not been applied — `prereq` offers to apply `patch_template` and insert the stamp.
2. If the file contains the stamp with version `v == required_version`, the patch is current — skip.
3. If the file contains the stamp with `v < required_version`, the patch is stale — `prereq` halts with: "`<id>` patch is at version `<v>`, required `<required_version>`. Manual review required."
4. If the stamp version `v > required_version`, warn but do not halt (forward compatibility).

**`sidecar-meta`** — verify that named baseline RDS files have accompanying `.meta.json` sidecars describing the scenario, N, seed stream, and evaluator SHA under which they were generated.

| Field | Purpose |
|---|---|
| `required_for` | List of baseline names (keys in `config.baselines`) |
| `required_keys` | List of JSON keys that must be present, default `[scenario_name, n_subjects, n_sims, dgp_version, evaluator_sha]` |

Check: for each named baseline in `required_for`, load `<baseline>.meta.json`. Compare each key in `required_keys` against the corresponding key in `config.yaml` (where meaningful — e.g., `scenario_name`, `n_subjects`, `n_sims`). Any hard-key mismatch is a blocking error. `evaluator_sha` mismatch is a warning, not a failure.

**`column-presence`** — verify that running the evaluator on a smoke-scenario produces an output data frame containing the named metric columns referenced in `fitness` and `gates`.

| Field | Purpose |
|---|---|
| `smoke_env_vars` | Env-var overrides for a minimal-cost run (e.g., `N_SIMS: 2, N_SUBJECTS: 100`) |
| `required_columns` | List of column names that must appear and be numeric with no `NA` |

If any required column is missing, `setup` halts with: "Column `<name>` referenced by `fitness.primary` / `gates[i]` is not present in the evaluator output. Patch the evaluator to emit it, or update `config.yaml` to reference an existing column."

### 5.2 Prerequisite staleness log

`config.prerequisites` records, per prerequisite, the expected version and the observed version at last successful `prereq` run. Re-running `prereq` after any upstream change is cheap and idempotent.

### 5.3 User-supplied custom checks

Users may declare `type: custom` prerequisites with a `check_command:` field — a shell command run from sub-project root. Non-zero exit means fail. This is the escape hatch; most prerequisites should fit `source-patch` / `sidecar-meta` / `column-presence`.

---

## 6. Slot grammar — three validators

Each slot kind has (i) a structural validator (no R-code execution on proposer output), (ii) a proposer-prompt template, (iii) a per-variant file serialization, and (iv) a `config.slot` subschema.

### 6.1 `feature_set`

**Unit of search.** Ordered list of R model-formula terms, length ≤ `slot.max_terms`.

**Grammar:**

```
feature_set   := list of terms
term          := base | transform(base) | base1 * base2
base          ∈ slot.whitelist
transform     ∈ slot.transforms     (typed descriptors, see §6.4)
interactions  ∈ {none, pairwise, three-way}   # v1: pairwise only
```

**Validator.** Per term:

1. **Parse** with `rlang::parse_expr(term)`. Parse error ⇒ `failure_reason = "parse_error"`, rlang message captured.
2. **Walk** the resulting expression with a recursive allowlist walker:

   ```r
   walk_term <- function(e) {
     if (is.name(e))                          # bare identifier
       return(check_base(as.character(e)))
     if (is.call(e)) {
       head <- as.character(e[[1]])
       if (head == "*")   return(check_interaction(e))  # base * base
       if (head == ":")   return(check_interaction(e))  # base : base
       return(check_transform(head, e))                 # transform(args)
     }
     reject("unsupported expression form")
   }
   ```

3. `check_base` rejects anything not in `slot.whitelist`.
4. `check_transform` rejects heads not in `slot.transforms` (by descriptor name), then delegates argument validation to the transform descriptor (§6.4).
5. `check_interaction` verifies both operands pass `check_base` and that `slot.interactions` permits the arity.
6. After all terms pass, the full list is checked against `slot.max_terms` and `slot.forbidden_patterns` (regex over the original term string).

**Per-variant file.** RDS containing `list(feature_set_expr = c("age", "log(x)", ...))`.

### 6.2 `hyperparameters`

**Unit of search.** Named list of numeric/categorical parameters.

**Grammar (JSON-schema-style).** `config.slot.params` declares one entry per parameter:

```yaml
slot:
  kind: hyperparameters
  params:
    mtry:      { type: integer, range: [1, 20] }
    ntree:     { type: integer, range: [100, 2000], log_scale: true }
    min_node:  { type: integer, range: [1, 50] }
    splitrule: { type: categorical, enum: [gini, extratrees] }
```

**Validator.** A proposal is valid iff it is a JSON object whose keys are exactly `config.slot.params` keys, and each value satisfies its declared `type` + `range`/`enum`. Integer ranges are closed; numeric ranges are closed. `log_scale` is a proposer hint (used in the prompt), not a validation constraint.

**Per-variant file.** RDS containing the named list.

### 6.3 `formula`

**Unit of search.** A single R formula string `y ~ rhs` where `y` is fixed by config and `rhs` is the mutable part.

**Grammar.** `rhs` is the same grammar as `feature_set` (list of terms separated by `+`), plus the `config.slot.lhs` clause.

**Validator.**

1. Parse with `stats::as.formula`. Formula parse error ⇒ reject.
2. Compare `LHS` to `config.slot.lhs` (exact string match after `deparse`). Mismatch ⇒ reject.
3. Walk `RHS` term-by-term with the `feature_set` walker (§6.1).

**Per-variant file.** RDS containing `list(formula_str = "y ~ x1 + log(x2) + x3*x4")`.

### 6.4 Transform descriptors (shared by `feature_set` and `formula`)

`slot.transforms` is a **list of typed descriptors**, not placeholder strings. Each descriptor names the R head it matches and specifies permitted argument shapes:

```yaml
slot:
  transforms:
    - name: log
      head: log
      arity: 1
      args: []                       # no extra args
    - name: sqrt
      head: sqrt
      arity: 1
      args: []
    - name: square
      head: I
      arity: 1
      shape: "I(<base>^2)"           # walker enforces: inner expr is `^`,
                                     # lhs is a whitelisted base, rhs is literal 2
    - name: ns_df3
      head: ns
      arity: 1
      kwargs:
        df: 3                        # validator requires df == 3 exactly
    - name: ns_df4
      head: ns
      arity: 1
      kwargs:
        df: 4
```

The walker matches `ns(x, df=3)` by (a) head `ns`, (b) first positional arg a whitelisted base, (c) keyword args exactly `{df: 3}`. Anything else (e.g., `ns(x, df=5)` or `ns(x, knots=c(1,2))`) fails closed with `failure_reason = "ns_args_mismatch"`.

### 6.5 Slot-kind contract (for v2 extensions)

Adding a new slot kind means adding three files under the skill:

```
.claude/skills/method-evolve/
  validators/<kind>.R              # walk_term() / validate_proposal()
  templates/proposer/<kind>.md     # prompt template consumed by §10
  examples/<kind>_toy/             # smoke-test config + tiny evaluator
```

No engine code changes. The engine dispatches on `slot.kind` to load the matching validator and template.

---

## 7. Config schema

All fields required unless marked `# optional`. Two-layer substitution (§7.1).

```yaml
name: my-search

target_script: scripts/R/my_evaluator.R    # relative to subproject root

prerequisites:
  - id: emit-extra-metric
    type: source-patch
    target: scripts/R/my_evaluator.R
    required_version: 1
    patch_template: emit_extra_metric.patch        # under <subproject>/templates/
  - id: baseline-metadata
    type: sidecar-meta
    required_for: [baseline_lower, baseline_upper]
  - id: required-columns
    type: column-presence
    smoke_env_vars: { SCENARIO_NAME: smoke, N_SIMS: 2, N_SUBJECTS: 100 }
    required_columns: [my_metric, c_index, abs_bias, coverage]

evaluator:
  env_vars:
    SCENARIO_NAME: hardest_scenario
    N_SIMS: 50
    N_SUBJECTS: 500
    VARIANT_FILE: ${VARIANT_PATH}
  results_file_pattern: "results/${SCENARIO_NAME}_${VARIANT_ID}.rds"

substitutions:
  freeze_on_setup:        # resolved ONCE at `setup`, then frozen in config.yaml
    - run_date            # ISO date at setup time
    - name                # top-level `name:` field
  per_variant:            # resolved per variant at run time
    - VARIANT_PATH        # absolute path to variants/var_NNNNN.rds
    - VARIANT_ID          # "var_NNNNN"
    - SEED_BLOCK          # integer block index for reproducible seeds
    - SCENARIO_NAME       # permits scenario loops in `full` tier
  refreeze_behavior: "error"    # `setup` refuses to overwrite frozen values;
                                # `--refreeze` required to allow it

slot:
  kind: feature_set        # or "hyperparameters" or "formula"
  # --- feature_set fields ---
  max_terms: 20
  whitelist: [x1, x2, x3, x4, x5, x6]      # user-supplied
  transforms:
    - {name: log,     head: log,  arity: 1}
    - {name: sqrt,    head: sqrt, arity: 1}
    - {name: square,  head: I,    arity: 1, shape: "I(<base>^2)"}
    - {name: ns_df3,  head: ns,   arity: 1, kwargs: {df: 3}}
  interactions: pairwise
  forbidden_patterns: ["^true_", ".*_future$"]
  # --- hyperparameters fields (if kind=hyperparameters) ---
  # params: { mtry: {type: integer, range: [1,20]}, ... }
  # --- formula fields (if kind=formula) ---
  # lhs: "Surv(time, event)"
  # (the rhs grammar reuses feature_set fields)

baselines:
  scenario_match_required: true
  baseline_lower: { results_file: results/lower_hard.rds,
                    meta_file:    results/lower_hard.meta.json }
  baseline_upper: { results_file: results/upper_hard.rds,
                    meta_file:    results/upper_hard.meta.json }

fitness:
  primary:
    template: recovery_ratio                       # named template; see §8.1
    target: my_metric                              # column in per-variant results
    lower:  baseline_lower.my_metric               # from baselines map
    upper:  baseline_upper.my_metric
    direction: higher_is_better
    # OR raw expression escape hatch:
    # expr: "(baseline_lower.my_metric - my_metric) / (baseline_lower.my_metric - baseline_upper.my_metric)"
  recovery:
    denom_floor_epsilon: 0.002
    degenerate_scenario_action: reject_and_halt
    degenerate_variant_fallback:
      fallback_metric: "neg:my_metric"              # smaller target ⇒ negate
      cap: 0

gates:
  - {metric: abs_bias, tier: screen, op: "<",  threshold: 0.02}
  - {metric: abs_bias, tier: full,   op: "<",  threshold: 0.02}
  - {metric: coverage, tier: screen, op: in,   range: [0.91, 0.99]}
  - {metric: coverage, tier: full,   op: in,   range: [0.93, 0.97]}
  - {metric: c_index,  tier: both,   op: ">=", expr: "baseline_lower.c_index - 0.01"}

budget:
  max_variants: 200
  batch_size: 10
  max_generations: 20          # CLI `max_gens` overrides for a single invocation
  promote_top_k: 10
  early_stop_after: 5

compute:
  screen:
    backend: local             # "local" | "slurm" | "custom"
    n_workers: 5
    variants_cache: ~/.method-evolve-cache/${run_date}_${name}
  full:
    backend: slurm
    submit_script: scripts/slurm/my_full_submit.sh    # user-supplied; skill calls it
    promote:
      wrapper_script: scripts/slurm/evolve_${name}_promote.sh   # skill-generated
      output_namespace: "results/full/${run_date}_${name}/${VARIANT_ID}/${SCENARIO_NAME}/seed_${SEED_BLOCK}"
      array_index_formula: "v * S + s"   # v = variant rank in promote_top_k,
                                         # S = scenarios in full grid,
                                         # s = scenario index
      manifest_file: "${out_dir}/promote_manifest.json"
    remote_host: ""            # used only to print rsync/ssh commands
    remote_path: ""

paths:
  out_dir: "quality_reports/evolve/${run_date}_${name}"    # +`-NN` if same-day collision
  variants_dir: "${out_dir}/variants"
  program_db: "${out_dir}/PROGRAM_DB.jsonl"
  state_file: "${out_dir}/EVOLVE_STATE.json"
```

### 7.1 Substitution semantics

Two layers, labeled:

- **`substitutions.freeze_on_setup`** — resolved exactly once, at `setup`, then written back into `config.yaml` as literal values. `run`, `promote`, `ingest`, and `report` never re-resolve these. If the user wants a new `run_date`, they must either start a new run folder or pass `--refreeze` to `setup`, which explicitly overwrites frozen values.
- **`substitutions.per_variant`** — resolved per variant at the moment the variant is dispatched to the evaluator. In v1: `VARIANT_PATH`, `VARIANT_ID`, `SEED_BLOCK`, `SCENARIO_NAME`.

### 7.2 Re-run-`setup` behavior

`setup` is idempotent for fields not in `freeze_on_setup`. For frozen fields, it refuses to overwrite unless `--refreeze` is passed. This prevents silent run-date drift across sessions.

---

## 8. Fitness evaluation

### 8.1 Primary metric — named templates + raw-expression escape hatch

`fitness.primary` may be one of three named templates (syntactic sugar) or a raw `expr` (escape hatch). Both desugar to a single `rlang`-evaluated expression over a name bindings table that contains:

- All scalar columns from the per-variant evaluator RDS (e.g., `my_metric`, `abs_bias`, `coverage`, `c_index`).
- Dotted accessors into each named baseline's columns (e.g., `baseline_lower.my_metric`, `baseline_upper.c_index`), resolved from the baseline's RDS file.

**Named templates.** In all templates `lower` is the **worse-performance** baseline scalar and `upper` is the **better-performance** baseline scalar. The user assigns these labels by convention; the engine does not infer performance direction from the numerical values.

| Template | Required fields | Desugars to |
|---|---|---|
| `direct_metric` | `target`, `direction` | `target` if `direction == higher_is_better`; `-target` if `lower_is_better` |
| `recovery_ratio` | `target`, `lower`, `upper`, `direction` | `(target - lower) / (upper - lower)` if `direction == higher_is_better`; `(lower - target) / (lower - upper)` if `lower_is_better` |
| `weighted_sum` | `terms: list of {metric: str, weight: num}` | `Σ weightᵢ · metricᵢ` |

Both `recovery_ratio` forms equal `1` when `target == upper` (variant matches the better baseline) and `0` when `target == lower` (variant matches the worse baseline). Higher fitness is always better after desugaring.

**Raw expression:**

```yaml
fitness:
  primary:
    expr: "(baseline_lower.my_metric - my_metric) / (baseline_lower.my_metric - baseline_upper.my_metric)"
```

Any identifier appearing in `expr` must resolve in the name bindings table; `setup` validates this statically.

### 8.2 Gates (configurable tier thresholds)

Gates are user-declared with explicit `tier` in `{screen, full, both}`. Example:

```yaml
gates:
  - {metric: abs_bias, tier: both,   op: "<",  threshold: 0.02}
  - {metric: coverage, tier: screen, op: in,   range: [0.91, 0.99]}
  - {metric: coverage, tier: full,   op: in,   range: [0.93, 0.97]}
```

**Noise-budget guidance (documentation, not enforcement).** The skill's `setup` prints a noise-budget summary: for each gate referencing a proportion metric, it computes the Wald MC SE at the configured `N_SIMS` (`SE = sqrt(p·(1-p)/N_SIMS)` for nominal proportion `p`) and flags gates whose half-width is smaller than 1 MC SE as "likely over-tight; expect high false-rejection under the null". Worked example: at `N_SIMS = 50` and nominal coverage `0.95`, `SE ≈ sqrt(0.95·0.05/50) ≈ 0.031`; a symmetric `±0.02` window therefore flags ~50% of truly-calibrated variants. Widening the screen-tier window to roughly `±2·SE` (e.g., `[0.91, 0.99]`) brings false-rejection under the null to about 17% — recommended but not enforced.

A `--gate-calibration` dry-run mode runs the gates against the **lower baseline** (which, for a well-calibrated estimator, should pass all gates). If it doesn't, the gates are too tight for the scenario and `setup` warns.

Failed variants are retained in the DB with `gate_pass: false` and per-gate failure flags — used as negative examples in subagent prompts.

### 8.3 Recovery ratio denominator handling

The denominator of `recovery_ratio` is `upper - lower` (or `lower - upper` under `lower_is_better`); both have magnitude `|upper - lower|`.

**Denominator floor.** At scenario setup, `setup` computes `D = |upper - lower|` from the baseline RDS files. If `D < fitness.recovery.denom_floor_epsilon` (default `0.002`), the scenario is **rejected as non-informative** and `setup` halts with a message: "The scenario you selected has `baseline_lower.<metric>` ≈ `baseline_upper.<metric>` — this search cannot meaningfully recover. Pick a different scenario or widen the relevant parameter."

**Per-variant denominator degeneracy** (mid-run, rare). If a variant lands `target` such that the recovery ratio is numerically unstable (e.g., signs inverted by MC noise on that variant's seeds), the variant falls back to `fitness.recovery.degenerate_variant_fallback.fallback_metric`. The fallback value is one of:

- a bare column name (e.g., `c_index`) — used as-is,
- a column name prefixed with `neg:` (e.g., `neg:my_metric`) — desugared to `-my_metric`, used when the underlying metric is smaller-is-better and must be flipped to fit the higher-is-better fitness convention.

`gate_pass` is unaffected by the fallback; only the primary fitness uses it. Values > 1 (variant beats the better baseline by MC noise) are kept as-is and flagged for inspection during `promote`.

---

## 9. Program DB and sampler

### 9.1 DB format

Append-only JSONL, one variant per line. Example for `slot.kind = feature_set`:

```json
{
  "variant_id": "var_00042",
  "generation": 4,
  "parent_ids": ["var_00031", "var_00028", "var_00035", "var_00019"],
  "slot_kind": "feature_set",
  "proposal_payload": {
    "feature_set_expr": ["x1", "log(x2)", "x1*x3", "ns(x4, df=3)"]
  },
  "grammar_valid": true,
  "screen": {
    "my_metric": 0.142,
    "primary_fitness": 0.68,
    "recovery_source": "primary",
    "c_index": 0.721,
    "abs_bias": 0.011,
    "coverage": 0.948,
    "gate_pass": true,
    "gate_failures": [],
    "status": "ok"
  },
  "full": null,
  "seed_block": 1042,
  "llm_response_id": "gen_04_variant_02",
  "timestamp": "2026-04-21T23:17:04-04:00"
}
```

`proposal_payload` schema varies by `slot_kind`: `feature_set` → `{feature_set_expr: [...]}`; `hyperparameters` → `{hyperparameters: {name: value, ...}}`; `formula` → `{formula_str: "..."}`. `recovery_source` is `"primary"` or `"fallback"` (§8.3). `full` is populated by `ingest` (§11.3).

### 9.2 Writer discipline

**Parent-process-only writer.** Only the driver's main R process appends to `PROGRAM_DB.jsonl`. Child workers (from `mclapply`) never open the DB file. The sequence is:

1. Parent opens `PROGRAM_DB.jsonl` with `O_APPEND` and holds the file handle.
2. Parent allocates a `variant_id` block for the generation **before** spawning workers (§9.3).
3. Parent dispatches each variant to a child worker via `mclapply`.
4. Each child returns a **record object** (list) — not a log line.
5. After `mclapply` joins, the parent serializes each returned record to a single JSON line and appends in the same order as the allocated IDs.
6. After all lines are appended, the parent calls `flush` + `fsync` before writing the checkpoint (§15).

This eliminates write races and partial-line corruption.

### 9.3 Atomic `variant_id` allocation

Before generation G spawns workers:

```r
gen_size      <- length(valid_candidates)
last_used_id  <- parent_state$last_variant_id
new_ids       <- sprintf("var_%05d", (last_used_id + 1):(last_used_id + gen_size))
parent_state$last_variant_id <- last_used_id + gen_size
# commit new parent_state to EVOLVE_STATE.json.tmp, rename over
# THEN dispatch workers, passing each worker its assigned variant_id
```

The allocation block is guarded by a `flock` on `EVOLVE_STATE.json.lock` so that a user accidentally starting a second `/method-evolve run` in the same folder gets a clean error rather than a collision.

### 9.4 Per-child seed derivation

Each child's seed is derived deterministically from the parent seed and the child's variant_id:

```r
child_seed <- digest::digest2int(paste0(parent_seed, "/", variant_id))
set.seed(child_seed)
```

`seed_block` is recorded in the DB record (§9.1) so any variant can be re-run bit-exactly.

### 9.5 Sampler (parent selection)

Default: top-3 gate-passers by primary fitness + 1 random gate-passer (diversity).

**Zero-gate-passer fallback.** If the pool of gate-passers is empty (common in gen 0 and gen 1), the sampler degrades in this order:

1. Top-3 variants by primary fitness regardless of gate-pass status, + 1 random variant, **plus** a prompt flag `gate_failure_mode: true` that tells the proposer: "none of these parents passed gates — your proposals should specifically address `<list of gate failures seen so far>`."
2. If even `PROGRAM_DB.jsonl` is empty (generation 0), the sampler returns no parents and the proposer is given a "seed generation" prompt variant that asks for diverse starting variants from the slot's vocabulary.

The sampler never deadlocks.

---

## 10. Subagent proposer

### 10.1 Prompt templates — one per slot kind

Three templates shipped under `templates/proposer/`:

- `feature_set.md`
- `hyperparameters.md`
- `formula.md`

Each template is filled from `config.yaml` at runtime with the same skeleton:

```
[System — persona: "expert statistical methodologist"]
[Project context: slot kind + evaluator summary + scenario summary (≤ 300 words)]
[Grammar specification:
   — feature_set:      whitelist, transforms, interactions, forbidden patterns, max_terms
   — hyperparameters:  params schema (type, range, enum, log_scale hints)
   — formula:          lhs (fixed), rhs grammar same as feature_set]
[Parent variants (top-3 + 1 random, or sampler-fallback set):
   proposal_payload + screen scores + gate status for each]
[Failed-variant negative examples:
   capped at 5, oldest-first eviction — most recent failures win]
[Task: propose BATCH_SIZE new variants as a JSON array.]
[Output contract (see §10.2): strict JSON schema, no prose, no code fences preferred]
```

`model: "opus"` is **always explicit** in the Task tool call (per `.claude/rules/codex-fallback-protocol.md`). The template selected depends on `config.slot.kind`; an unknown kind is an error in `setup` (§6.5).

### 10.2 JSON parse contract

Expected output shape by slot kind:

```json
// feature_set
[{"feature_set_expr": ["x1", "log(x2)", "x1*x3"], "rationale": "short free text"}, ...]

// hyperparameters
[{"hyperparameters": {"mtry": 5, "ntree": 500, "min_node": 10}, "rationale": "..."}, ...]

// formula
[{"formula_str": "y ~ x1 + log(x2) + x1*x3", "rationale": "..."}, ...]
```

**Robust parse pipeline:**

1. Strip Markdown code fences if present (` ```json ... ``` `).
2. Trim whitespace.
3. Attempt `jsonlite::fromJSON(simplifyVector = FALSE)`; require the root to be an array of objects with the slot-appropriate shape.
4. If parse fails or shape mismatches, **retry once** with a correction prompt that includes the original response and the parser's error. Save both attempts under `generations/gen_NN/`.
5. If the retry also fails, record the generation's failure in `EVOLVE_STATE.json`, checkpoint, and exit cleanly. User re-runs `/method-evolve run` to advance.

### 10.3 Negative-example cap

`max_negative_examples: 5`. Oldest-first eviction — the prompt always surfaces the most recent 5 grammar rejections so the proposer learns the current edge of the vocabulary rather than ancient bugs. Total prompt size is capped so context does not blow up across generations.

---

## 11. Runtime model

### 11.1 Where each tier runs

| Tier | Environment | Mechanism |
|---|---|---|
| Skill workflow (subagent, DB, validator, reports) | Local (Claude Code) | native |
| Screen MC evals | per `compute.screen.backend` | `local` ⇒ `mclapply`; `slurm` ⇒ array submission (rare for screen); `custom` ⇒ user cmd |
| Full MC evals | per `compute.full.backend` | `local` (small problems); `slurm` (typical); `custom` |
| Program DB, logs, reports | Local | native |
| Variant RDS cache | Local, non-synced (`~/.method-evolve-cache/…`) | native |

### 11.2 `local` backend — parallelism and worker isolation

- Parent R process manages the generation loop, the DB handle, and the state file.
- Children spawned via `mclapply(mc.cores = n_workers, mc.preschedule = FALSE)` to isolate failures.
- Each child runs `Rscript target_script` as a **subprocess**, not an in-process `source()` — a worker crash cannot corrupt the parent's memory.
- `mc.cleanup = TRUE` and explicit `tools::pskill` on the parent's SIGINT handler so `Ctrl-C` reliably kills all children.
- Per-child working directory is the variants_cache so synced directories (e.g., OneDrive) never see per-variant writes.

### 11.3 `slurm` backend — `promote` and `ingest`

**`promote`** generates a wrapper script at `compute.full.promote.wrapper_script`:

1. Takes the top-`promote_top_k` gate-passing variants from the DB.
2. Writes `${out_dir}/promote_manifest.json` listing each `(variant_id, rank, scenario, SLURM array index, output path)`. Paths follow `compute.full.promote.output_namespace` (§7) so every `(variant × scenario × seed-block)` triple has a **unique, collision-free output directory**.
3. Emits, to stdout, the exact `rsync` + `ssh` + `sbatch --array=...` commands to run, parameterized by the manifest.

The wrapper itself, when executed on the SLURM cluster via `sbatch`, computes `v = variant_rank`, `s = scenario_index` from `$SLURM_ARRAY_TASK_ID` via `compute.full.promote.array_index_formula` and exports the per-variant macros (`VARIANT_PATH`, `VARIANT_ID`, `SEED_BLOCK`, `SCENARIO_NAME`) plus every key in `evaluator.env_vars` (with substitutions applied) before calling the project's existing `submit_script` body. `${SCENARIO_NAME}` alone never names an output; the full namespace from `compute.full.promote.output_namespace` is always used.

**`ingest`** is the results-flow-back command:

1. User runs `rsync` (commands printed by `promote`) to pull remote outputs back into `<subproject>/results/full/`.
2. `method-evolve ingest` reads `promote_manifest.json`, walks the expected output paths, loads each per-variant×scenario RDS, aggregates across scenarios per variant, computes full-tier metrics, and **patches the `full` field** in the corresponding DB record (rewrite `PROGRAM_DB.jsonl` atomically: write to `.tmp`, fsync, rename).
3. Missing output directories are reported but do not block ingest of the rest.
4. `ingest` is idempotent — re-running it overwrites the `full` field with the latest computation.

`report` then consumes the patched DB to build the leaderboard.

### 11.4 `custom` backend

User supplies:

- `submit_cmd` — a shell command that enqueues/runs one variant. Skill substitutes `${VARIANT_ID}`, `${VARIANT_PATH}`, `${SCENARIO_NAME}`, `${SEED_BLOCK}` before shelling out.
- `pull_cmd` — a shell command run by `ingest` to fetch results back.

No smoke-test coverage; documented as an escape hatch for unusual clusters.

### 11.5 Failure modes

- Subagent parse failure → one retry, then clean checkpoint + exit (§10.2).
- Grammar validator rejection → recorded, continue.
- Evaluator subprocess crash → record `screen.status: "eval_error"`, continue.
- Local package missing → surfaced in Phase 2 smoke test, not mid-run.
- Remote Full timeout → surfaced when `ingest` finds no output; re-submit and re-ingest.

---

## 12. Outputs

```
<subproject>/quality_reports/evolve/YYYY-MM-DD_<name>[-NN]/
  config.yaml                               # final (post-interview, post-freeze)
  config.draft.yaml                         # Phase 0 output, retained
  EVOLVE_STATE.json                         # checkpoint (schema in §15)
  EVOLVE_STATE.json.lock                    # flock guard
  PROGRAM_DB.jsonl                          # append-only DB
  promote_manifest.json                     # written by `promote`
  variants/
    var_00001.rds ... var_00NNN.rds
  generations/
    gen_00/{prompt.md, response_raw.txt, response_parsed.json, log.txt}
    gen_01/...
  leaderboard.md
  final_report.md
  plots/
    fitness_by_gen.pdf
    top_feature_frequencies.pdf             # when slot.kind=feature_set
    top_hyperparameter_density.pdf          # when slot.kind=hyperparameters
    gate_pass_rate_by_gen.pdf
```

The `-NN` suffix (e.g., `2026-04-21_my-search-02`) is appended automatically when a same-day re-run of the same `name` would otherwise collide (per `CLAUDE.md` Skill Output Storage).

---

## 13. Project conventions honored

- `here::here()` for all paths inside generated driver scripts.
- `set.seed(YYYYMMDD)` at top of driver.
- Okabe-Ito palette for plots (`.claude/rules/r-code-conventions.md`).
- Dated subfolder per run with sequence-number suffix on collision (§12).
- Session logging per `.claude/rules/session-logging.md`.
- Skill outputs under `quality_reports/evolve/` follow the `<skill-category>/YYYY-MM-DD_<description>/` pattern.

---

## 14. Reference example — synthetic Cox toy

Shipped at `.claude/skills/method-evolve/examples/synthetic_cox/`:

```
examples/synthetic_cox/
  config.yaml                 # slot.kind=feature_set, 2 baselines, recovery_ratio fitness
  toy_evaluator.R             # ~60 lines: simulate Cox data, fit, emit scalars
  baselines/
    lower.rds + lower.meta.json
    upper.rds + upper.meta.json
  templates/
    emit_extra_metric.patch   # demo source-patch prerequisite
  README.md                   # 1-page walkthrough
```

`toy_evaluator.R` generates `n_subjects` Cox observations from a linear predictor in `x1..x6`, fits a Cox model with the proposed `feature_set_expr`, and emits a results RDS containing the columns `my_metric`, `c_index`, `abs_bias`, `coverage`. Zero external dependencies beyond `survival`. Baselines are pre-computed for a low-noise and high-noise regime so the `recovery_ratio` denominator is non-degenerate.

**Smoke test covers, end-to-end, against this example:**

- zero-parent seed generation (gen 0),
- grammar rejection and recording of negative examples,
- variant eval → DB write → checkpoint,
- crash-during-eval resume (§15.2),
- `promote` dry-run (prints commands, writes manifest, does not submit),
- synthetic zero-gate-passer mode (triggered by tightening gates in a smoke-only config),
- `ingest` of locally-produced "full" results so the `full.*` patching path is exercised.

A second example (`examples/hyperparameters_toy/`) covers `slot.kind = hyperparameters` with the same toy evaluator but a different proposer path. A third (`examples/formula_toy/`) covers `slot.kind = formula`. Both are structurally minimal duplicates of `synthetic_cox`.

A project-flavored worked example lives under `examples/missing_types_ipw/` (feature-set search over a propensity model for a sub-project's IPW evaluator). It is not exercised by the smoke test and is not required for the skill to run anywhere; it exists only to illustrate a realistic end-to-end config.

---

## 15. Resumability contract

### 15.1 `EVOLVE_STATE.json` schema

```json
{
  "schema_version": 1,
  "run_id": "2026-04-21_my-search",
  "config_sha": "<sha256 of frozen config.yaml>",
  "parent_seed": 20260421,
  "last_variant_id": 42,
  "current_generation": 4,
  "generation_phase": "validated",
  "generation_phase_progress": {
    "proposed":   [43, 44, 45, 46, 47, 48, 49, 50, 51, 52],
    "validated":  [43, 44, 46, 47, 48, 49, 50, 51, 52],
    "evaluated":  [43, 44, 46, 47, 48],
    "db_written": [43, 44, 46, 47, 48]
  },
  "gate_passers_history": [0, 1, 2, 3, 5],
  "early_stop_counter": 2,
  "last_checkpoint_at": "2026-04-21T23:17:04-04:00"
}
```

`generation_phase ∈ {"proposing", "validated", "evaluating", "db_written", "generation_complete"}`. Written atomically (`.tmp` + rename) after every phase transition.

### 15.2 Mid-generation resumability semantics

On `run` restart:

1. Read `EVOLVE_STATE.json`. Verify `config_sha` matches the current `config.yaml`; if not, refuse to resume ("config changed mid-run; start a new run folder").
2. If `generation_phase == "db_written"`, advance to next generation.
3. If `generation_phase == "evaluating"`, re-dispatch only the variants in `validated \ evaluated` (no re-proposal). Pre-allocated `variant_id`s are preserved.
4. If `generation_phase == "validated"` (process died after validation, before any eval), re-dispatch the full `validated` set.
5. If `generation_phase == "proposing"` (process died during subagent call), discard the partial proposal and re-propose. `last_variant_id` is **not** advanced until allocation actually happens, so no ID leakage.

This gives mid-generation resumability with bounded rework: at most one generation's worth of evaluation may be redone on a crash.

---

## 16. Future extensions (v2+)

- **Additional slot kinds:** `model_config` (nested JSON schema), `augmentation_fn` (sandboxed R function body). Each requires validator + proposer template + example, per §6.5.
- **Mixed-slot-kind runs (AutoSOTA-inspired).** Let one run propose from multiple slot kinds simultaneously, with Normal-Path / Leap-Path anti-stagnation (force a higher-granularity mutation when the last K iterations were all one slot kind). Requires per-variant slot-kind tagging in the DB and a mixed-kind proposer template.
- **Failure-signature memory across runs** (AutoSOTA `AgentFix`-inspired). Accumulate grammar-rejection and gate-failure patterns across runs to seed future negative-example pools.
- IPCW-weighted Brier alongside pseudo-Brier as a fitness recipe.
- Multi-island / MAP-Elites samplers.
- Direct Anthropic API proposer with prompt caching.
- Optional GPT / Codex reviewer on promoted winners.
- SSH-automated promotion (`compute.full.ssh_submit: true` opt-in).
- Richer `column-presence` prerequisites (per-column dtype and range checks).

---

## 17. Explicit decisions log

| # | Decision | Chosen |
|---|---|---|
| 1 | Skill scope | general evolutionary search engine; no specific sub-project, estimator, metric, or baseline assumed |
| 2 | v1 slot kinds shipped | `feature_set`, `hyperparameters`, `formula` |
| 3 | Slot-kind interface | fixed-set + contract-in-repo (validator + template + example per kind); pluggable in v2 |
| 4 | Slot-kind mixing inside one run | **not** v1; deferred to v2 with Normal/Leap-Path anti-stagnation |
| 5 | Primary fitness | named templates (`direct_metric`, `recovery_ratio`, `weighted_sum`) + raw `expr` escape hatch |
| 6 | Baselines | user-named map; engine has no knowledge of `oracle`/`CCA`/etc. |
| 7 | Prerequisites | generic patch applicator + sidecar-meta + column-presence + custom check types |
| 8 | Compute backends | configurable per-tier: `local` / `slurm` / `custom` |
| 9 | Reviewer loop | none (MC is the critic) |
| 10 | Proposer backend | Claude Opus subagent via Task tool (explicit `model: "opus"`) |
| 11 | Runtime shape | in-session, gen-chunked, resumable, mid-generation safe |
| 12 | Local parallelism | `n_workers = 5`; parent-only DB writer; atomic ID allocation; derived per-child seeds |
| 13 | Promote results flow | `promote` prints commands + writes manifest; `ingest` patches `full.*` fields |
| 14 | Same-day re-run folders | `-NN` suffix on name collision |
| 15 | CLI vs config precedence | CLI `max_gens` overrides `budget.max_generations` |
| 16 | Reference example | synthetic Cox toy + hyperparameters toy + formula toy; project-flavored examples (e.g. Missing-Types IPW) are optional, unshipped |
| 17 | Migration from v2 | T0 scaffold survives unchanged; T1 applicator *machinery* survives; Missing-Types-specific IBS patch template moves from `templates/` to `examples/missing_types_ipw/templates/` as a non-default example |
