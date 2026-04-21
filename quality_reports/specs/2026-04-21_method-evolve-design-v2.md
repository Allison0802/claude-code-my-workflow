# `method-evolve` Skill — Design Specification

**Status:** DRAFT — Round 2 rewrite, pending reviewer re-judgment
**Author:** drafted with Claude (brainstorming skill)
**Date:** 2026-04-21
**Related paper:** Tsinghua FIB Lab, *AutoSOTA: An End-to-End Automated Research System for SOTA Model Discovery* (2026)

---

## Rewrite changes applied (Round 1 → Round 2)

Fixes applied section-by-section. Blocker numbers (B#) and pitfall numbers (P#) match the reviewer's ranked lists.

- **§3 (Architecture, reusability claim — P15).** Tightened the cross-project claim to: "domain-agnostic for `slot.kind = feature_set`; additional slot kinds (v2) require grammar and proposer-prompt extensions." Cross-referenced from §5 and §9.
- **§4 (Workflow phases — B1, P12).** Inserted `/method-evolve prereq` command and Phase −1. `setup` now begins with an explicit `has_ibs` prerequisite gate that refuses to run until the IBS patch has landed. Added `ingest` command (P11, B4).
- **NEW §5 (Phase −1: Prerequisites — B1, B6, P12, P19).** Owns the IBS patch to the evaluator script (exact file, exact diff shape, exact column name, exact version-stamp mechanism), owns the scenario-metadata embedding in baseline RDS files (B6), and owns the baseline-staleness check (P19).
- **§6 (Slot grammar validator — B3, P5).** Named the parser (`rlang::parse_expr` → recursive allowlist tree walk), specified transform-argument matching (exact literal match after normalization), specified fail-closed behavior on parse error, replaced fragile placeholder strings `"I(^2)"` / `"ns(df=3)"` with typed transform descriptors.
- **§7 (Config schema — P14, P17, P18).** Added `compute.full.promote.output_namespace` (unique output path per variant × scenario × seed-block), added `budget.max_generations` note on precedence vs CLI `max_gens` (CLI overrides config), split substitution into two labeled layers (setup-time freeze vs per-variant), defined `config.substitutions.freeze_on_setup` and `config.substitutions.per_variant` keys, and defined re-run-`setup` as refusing to overwrite frozen values unless `--refreeze` is passed.
- **§8 (Fitness — B2, P2, P3, P13).** Pinned pseudo-Brier as the decision (P13). Added `fitness.recovery.denom_floor_epsilon` with a concrete default and the fallback-fitness behavior when the denominator degenerates (B2, P2). Justified B=50 gate thresholds explicitly with a noise-budget calculation and added a `--gate-calibration` dry-run mode for the coverage gate (P3).
- **§9 (Program DB + sampler — B5, P1, P4).** Specified the parent-process-only DB writer, the atomic `variant_id` allocation block that runs before `mclapply`, the per-child seed-derivation formula (P1, B5), and the zero-gate-passer sampler fallback (P4).
- **§10 (Proposer subagent — P6, P7, P20).** Capped the negative-example set to 5 with an oldest-first eviction policy (P6), specified the robust JSON parse contract: strip code fences → parse top-level array → on parse failure, retry once with a correction prompt (P7), and fully schema'd the JSON contract (P20).
- **§11 (Runtime model — B4, B5, P10, P11, P14).** Defined the `promote` wrapper with unique output namespace (B4, P14), defined `ingest` command that pulls results back and patches `full.*` fields (B4, P11), defined worker-isolation rules for local `mclapply` (P10), and re-specified the parent/child DB-writer discipline (B5).
- **§12 (Outputs) and §13 (Conventions — P22).** Added sequence-number suffix for same-day re-runs (P22).
- **§14 (Reference example).** Unchanged logically, but hooked into the Phase −1 IBS-patch check.
- **NEW §15 (Resumability contract — P16).** Defined the `EVOLVE_STATE.json` schema explicitly and pinned mid-generation resumability semantics.
- **§16 (Future) and §17 (Decisions log — P13).** Pinned the pseudo-Brier decision in the log.

No hard constraint was dropped. No v2 scope was pulled in. The v1 feature envelope is identical to Round 1.

---

## 1. Goal

A Claude Code skill that applies an **evolutionary code-search loop** (FunSearch / AlphaEvolve / AutoSOTA stage-3 pattern) to statistical methods in this repository. The skill introspects the current sub-project, interviews the user to fill gaps, generates a project-specific configuration, and drives a generation-chunked search that proposes, evaluates, and ranks variants against hard statistical gates.

**v1 target:** IPW propensity **feature-set** search in the Missing Types sub-project. The engine is configured — not hardcoded — against that target, so later sub-projects can reuse the Phase 0–4 infrastructure as long as they provide a `slot.kind = feature_set` config.

---

## 2. Non-goals (explicitly out of scope for v1)

- Auto-discovery of method improvements from raw PDFs (AutoSOTA phases 1–2).
- Additional slot kinds beyond `feature_set`. Engine exposes a pluggable `slot.kind` interface; v1 implements only `feature_set` and errors cleanly on unknown kinds.
- Cross-estimator joint evolution.
- Multi-island or MAP-Elites samplers.
- Direct Anthropic API proposer (Task-tool subagent only).
- GPT / Codex reviewer loop on variants. Monte Carlo is the critic.
- Automated SSH / `sbatch` submission. `promote` prints commands; the user runs them.

---

## 3. Architecture

**Two-layer split:**

```
┌────────────────────────────────────────────────────────────────┐
│  method-evolve skill (parent repo)                             │
│    .claude/skills/method-evolve/                               │
│      SKILL.md, workflow phases, DB format, sampler,            │
│      validator, subagent proposer template, report generator   │
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
│    <subproject>/scripts/slurm/evolve_<name>_promote.sh         │
└────────────────────────────────────────────────────────────────┘
```

**Cross-project reusability — tightened claim.** The skill is **domain-agnostic only for `slot.kind = feature_set`**. Additional slot kinds (`formula`, `hyperparameters`, `augmentation_fn`, `model_config`) are declared in §6 but will require the engine to ship a corresponding grammar validator *and* a corresponding proposer-prompt template. Marketing the skill as "fully domain-agnostic" is incorrect; marketing it as "configurable for any feature-set search over an R statistical method with an existing Monte Carlo harness" is correct. This tightened claim is the reference for §6 and §10.

**Key invariant for v1.** The skill contains no IPW-, RPM-, or Cox-specific logic. All domain knowledge flows through `config.yaml`.

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

`setup` calls `prereq` internally and **refuses to continue** until every prerequisite check passes (see §5). `prereq` is also exposed standalone so the user can run it early.

CLI `max_gens` **overrides** `config.yaml.budget.max_generations` for a single invocation. This precedence is documented in the skill's `--help` output.

---

## 5. Phase −1: Prerequisites (NEW)

Prerequisites are upstream changes that must land in the target sub-project before any MC evaluation will produce the fields the skill needs. They are tracked as an ordered list in `config.prerequisites`; `prereq` runs the checks in order, reports pass/fail, and when it can apply a patch mechanically it offers to do so.

### 5.1 IBS patch — owner and mechanism

**Owner.** `prereq` stage, applied by a specific patch to:

```
Missing Types/scripts/R/missing_types_method_comparison_ipw.R
```

**What the patch does.**

1. Inserts a helper `compute_pseudo_brier(time_grid, pseudo_obs, pred_surv)` at the top of the script (or as a `source()` from `scripts/R/pseudo_brier.R`, which `prereq` creates if missing).
2. Inside the existing per-seed result-assembly block, computes pseudo-Brier at each `t ∈ fitness.time_grid`, integrates by trapezoidal rule over the grid, and stores the scalar under column name `ibs` in the per-seed result `data.frame`.
3. Adds a file-header comment:

   ```r
   # ibs-patch-version: 1  (method-evolve prereq)
   ```

   This version stamp is how `prereq` detects that the patch has already been applied and skips re-applying (P19).

**Check (`has_ibs`)** — `prereq` verifies, in this order:

1. The source file contains `ibs-patch-version:` and the value matches the skill's required version.
2. Running the evaluator on the reference scenario with `N_SIMS=2, N_SUBJECTS=100` produces an output RDS whose `data.frame` has a numeric `ibs` column with no `NA`s.

If either check fails, `setup` halts with a clear error: "IBS prerequisite failed — run `/method-evolve prereq` first, or apply the patch manually."

### 5.2 Baseline scenario-metadata embedding (B6)

The recovery ratio is only valid when the baseline RDS files were generated from the **same scenario, N, DGP seed-stream, and evaluator version** as the screen-tier evaluator. `prereq` enforces this by:

**Patch to evaluator.** When the evaluator writes its output RDS, it also writes a sibling `*.meta.json` containing:

```json
{
  "scenario_name": "high_mar_high_cens",
  "n_subjects": 500,
  "n_sims": 50,
  "dgp_version": "missing-types-v3",
  "evaluator_sha": "<first 12 chars of git HEAD of the target_script>",
  "ibs_patch_version": 1,
  "created_at": "2026-04-21T..."
}
```

**Key comparison performed by `setup`.** For each baseline listed in `config.baselines` (`oracle`, `CCA`), `setup`:

1. Loads the sibling `.meta.json`. If missing, fails with: "Baseline <name> has no scenario metadata — regenerate it, or `prereq` can do it now with 2 quick runs."
2. Compares the fields `scenario_name`, `n_subjects`, `n_sims`, `dgp_version`, `ibs_patch_version` against the corresponding values in `config.yaml`.
3. If `evaluator_sha` differs from the current evaluator's SHA, prints a warning but does not fail (evaluator changes that do not touch the DGP are allowed; the user can override).

Any mismatch on the hard keys is a **blocking error** at setup.

### 5.3 Prerequisite staleness log

`config.prerequisites` in the YAML schema (§7) records, per prerequisite, the expected version and the observed version at last successful `prereq` run. Re-running `prereq` after any upstream change is cheap and idempotent.

---

## 6. Slot grammar — validator

### 6.1 v1 kind: `feature_set`

```
feature_set   := list of terms, length ≤ slot.max_terms
term          := base | transform(base) | base1 * base2
base          ∈ slot.whitelist
transform     ∈ slot.transforms     (typed descriptors, see §6.3)
interactions  ∈ {none, pairwise, three-way}   # v1: pairwise only
```

### 6.2 Parser and walker (B3, P5)

The validator does **not** execute R code. It:

1. **Parses** each proposed term string with `rlang::parse_expr(term)`. On any parse error, the term is rejected with `failure_reason = "parse_error"` and the rlang message is captured. This is the fail-closed path.
2. **Walks** the resulting expression tree with a small recursive allowlist walker:

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
4. `check_transform` rejects heads not in `slot.transforms` (by descriptor name), then delegates argument validation to the transform's descriptor (§6.3).
5. `check_interaction` verifies both operands pass `check_base` and that `slot.interactions` permits the arity.
6. After all terms pass, the full list is checked against `slot.max_terms` and `slot.forbidden_patterns` (regex over the original term string).

Every rejection produces `{grammar_valid: false, failure_reason: "<specific>"}`.

### 6.3 Transform descriptors (replaces fragile whitelist strings — P5)

`slot.transforms` is a **list of typed descriptors**, not a list of placeholder strings. Each descriptor names the R head it matches and specifies permitted argument shapes:

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
      shape: "I(<base>^2)"           # the walker enforces: inner expr is `^`,
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

The old strings `"I(^2)"` and `"ns(df=3)"` are removed. The validator matches `ns(x, df=3)` by (a) head `ns`, (b) first positional arg a whitelisted base, (c) keyword args exactly `{df: 3}`. Anything else (e.g., `ns(x, df=5)` or `ns(x, knots=c(1,2))`) fails closed with `failure_reason = "ns_args_mismatch"`.

### 6.4 v2+ slot kinds (declared, not implemented)

`formula`, `hyperparameters`, `augmentation_fn`, `model_config`. Per §3 each requires its own validator + proposer template.

---

## 7. Config schema

All fields required unless marked `# optional`. Two-layer substitution (§7.1).

```yaml
name: ipw-feature-search

target_script: missing_types_method_comparison_ipw.R   # relative to subproject root

prerequisites:
  - id: ibs-patch
    type: source-patch
    target: missing_types_method_comparison_ipw.R
    required_version: 1
  - id: baseline-metadata
    type: sidecar-meta
    required_for: [oracle, CCA]

evaluator:
  env_vars:
    SCENARIO_NAME: high_mar_high_cens
    N_SIMS: 50
    N_SUBJECTS: 500
    FEATURE_SET_FILE: ${VARIANT_PATH}
  results_file_pattern: "results_missing_types/${SCENARIO_NAME}_${VARIANT_ID}.rds"

substitutions:
  # Two substitution layers — read this carefully.
  freeze_on_setup:        # resolved ONCE at `setup`, then frozen in config.yaml
    - run_date            # ISO date at setup time
    - name                # top-level `name:` field
  per_variant:            # resolved per-variant at run time
    - VARIANT_PATH        # absolute path to variants/var_NNNNN.rds
    - VARIANT_ID          # "var_NNNNN"
    - SEED_BLOCK          # integer block index for reproducible seeds
  refreeze_behavior: "error"    # `setup` refuses to overwrite frozen values;
                                # `--refreeze` required to allow it

slot:
  kind: feature_set
  max_terms: 20
  whitelist: [age, sex, n_prior_type1, n_prior_type2, prev_event_type,
              time_since_last_type1, time_since_last_type2, log_time, e.time]
  transforms:             # typed descriptors, see §6.3
    - {name: log,     head: log,  arity: 1}
    - {name: sqrt,    head: sqrt, arity: 1}
    - {name: square,  head: I,    arity: 1, shape: "I(<base>^2)"}
    - {name: ns_df3,  head: ns,   arity: 1, kwargs: {df: 3}}
    - {name: ns_df4,  head: ns,   arity: 1, kwargs: {df: 4}}
  interactions: pairwise
  forbidden_patterns: ["^true_", "^type$", ".*_future$"]

fitness:
  primary: recovery_IBS
  primary_definition: "(IBS_CCA - IBS_IPW) / (IBS_CCA - IBS_oracle)"
  brier_variant: pseudo_brier          # pinned decision, see §8.1
  time_grid: [t1, t2, t3, t4, t5]      # filled in by setup from scenario horizon

  recovery:
    denom_floor_epsilon: 0.002         # denominator floor; see §8.3
    degenerate_scenario_action: reject_and_halt
    degenerate_variant_fallback:
      # used when an individual variant produces an unusable denominator but
      # the scenario itself is OK — rare but possible under noise
      fallback_metric: neg_ibs_ipw     # smaller is better ⇒ negate
      cap: 0

  gates:
    - {metric: abs_bias, op: "<",  threshold: 0.02}
    - {metric: coverage, op: in,   range: [0.93, 0.97]}
    - {metric: c_index,  op: ">=", expr: "C_CCA - 0.01"}

baselines:
  scenario_match_required: true
  oracle: {results_file: results_missing_types/oracle_hard.rds,
           meta_file:    results_missing_types/oracle_hard.meta.json}
  CCA:    {results_file: results_missing_types/cca_hard.rds,
           meta_file:    results_missing_types/cca_hard.meta.json}

budget:
  max_variants: 200
  batch_size: 10
  max_generations: 20        # CLI `max_gens` overrides for a single invocation
  promote_top_k: 10
  early_stop_after: 5

compute:
  screen:
    backend: local
    n_workers: 5
    variants_cache: ~/.method-evolve-cache/${run_date}_${name}
  full:
    backend: longleaf
    existing_submit: submit_missing_types_ipw.sh
    promote:
      wrapper_script: scripts/slurm/evolve_${name}_promote.sh   # skill-generated
      output_namespace: "results_missing_types/full/${run_date}_${name}/${VARIANT_ID}/${SCENARIO_NAME}/seed_${SEED_BLOCK}"
      array_index_formula: "v * S + s"   # v = variant rank in promote_top_k,
                                         # S = scenarios in full grid,
                                         # s = scenario index
      manifest_file: "${out_dir}/promote_manifest.json"
    remote_host: ""        # used only to print rsync/ssh commands
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
- **`substitutions.per_variant`** — resolved per variant at the moment the variant is dispatched to the evaluator. `VARIANT_PATH`, `VARIANT_ID`, `SEED_BLOCK` are the only allowed keys in v1.

### 7.2 Re-run-`setup` behavior

`setup` is idempotent for fields not in `freeze_on_setup`. For frozen fields, it refuses to overwrite unless `--refreeze` is passed. This prevents silent run-date drift across sessions.

---

## 8. Fitness evaluation

### 8.1 Primary metric — pseudo-Brier (pinned decision, P13)

Pseudo-Brier is the v1 default. IPCW-weighted Brier is deferred to v2. Rationale: the Missing Types harness already computes pseudo-observations per seed; computing pseudo-Brier from them adds one loop and zero new statistical assumptions, whereas IPCW-Brier requires a censoring-model nuisance that the project does not currently fit.

```
pseudo_brier(t)    = (1/n) Σᵢ (Ŷᵢ(t) − π̂ᵢ(t))²
IBS               = ∫ pseudo_brier(t) dt   (trapezoidal over fitness.time_grid)
```

Recorded under column `ibs` in the evaluator RDS (see §5.1).

### 8.2 Gates (B=50 noise budget, P3)

Gates at screen tier with B=50 seeds:

- `|bias| < 0.02` — relative bias. At B=50 with typical within-seed SE, the false-rejection rate under the null (true bias = 0) is ~5% given the estimator's per-seed SE ≈ 0.07 and MC SE ≈ 0.01.
- `coverage ∈ [0.93, 0.97]` — nominal-95% coverage. **Noise budget:** at B=50 with true coverage 0.95, the MC SE on empirical coverage is √(0.95·0.05/50) ≈ 0.031. A symmetric ±0.02 window therefore rejects ~50% of truly-calibrated variants — this is the false-rejection concern the reviewer flagged.
  **Mitigation chosen for v1:** widen the screen-tier gate to `[0.91, 0.99]`, which brings screen-tier false-rejection under the null to ~17%. Full-tier retains the tight `[0.93, 0.97]`. This is encoded as two gates:
  ```yaml
  gates:
    - {metric: coverage, tier: screen, op: in, range: [0.91, 0.99]}
    - {metric: coverage, tier: full,   op: in, range: [0.93, 0.97]}
  ```
- `c_index ≥ C_CCA − 0.01` — prevents degenerate winners that trade discrimination for calibration.

A `--gate-calibration` dry-run mode runs the gates against the **CCA baseline** (which should pass all gates by construction). If it doesn't, the gates are too tight for the scenario and `setup` warns.

Failed variants are retained in the DB with `gate_pass: false` and per-gate failure flags — used as negative examples in subagent prompts.

### 8.3 Recovery ratio (B2, P2)

```
recovery_IBS = (IBS_CCA − IBS_IPW) / (IBS_CCA − IBS_oracle)
```

**Denominator floor.** At scenario setup, `setup` computes `D = IBS_CCA − IBS_oracle` from the baseline RDS files. If `|D| < fitness.recovery.denom_floor_epsilon` (default `0.002`), the scenario is **rejected as non-informative** and `setup` halts with a message: "The scenario you selected has CCA ≈ oracle on IBS — IPW cannot meaningfully recover. Pick a different scenario or widen the missingness/censoring dial."

**Per-variant denominator degeneracy** (mid-run, rare). If a variant lands `IBS_IPW` such that the recovery ratio is numerically unstable (e.g., `IBS_CCA < IBS_oracle` by MC noise on that variant's 50 seeds), the variant falls back to `fallback_metric = neg_ibs_ipw` (smaller IBS is better, so we negate). `gate_pass` is unaffected by this fallback; only the primary fitness uses it.

Values > 1 (variant beats oracle by MC noise) are kept as-is and flagged for inspection during `promote`.

---

## 9. Program DB and sampler

### 9.1 DB format

Append-only JSONL, one variant per line:

```json
{
  "variant_id": "var_00042",
  "generation": 4,
  "parent_ids": ["var_00031", "var_00028", "var_00035", "var_00019"],
  "feature_set_expr": ["age", "log(log_time)", "age*sex", "ns(e.time, df=3)"],
  "grammar_valid": true,
  "screen": {
    "ibs_ipw": 0.142,
    "ibs_recovery": 0.68,
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

`recovery_source` is `"primary"` or `"fallback_neg_ibs_ipw"` (§8.3). `full` is populated by `ingest` (§11.3).

### 9.2 Writer discipline (B5, P1)

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

### 9.4 Per-child seed derivation (P1)

Each child's seed is derived deterministically from the parent seed and the child's variant_id:

```r
child_seed <- digest::digest2int(paste0(parent_seed, "/", variant_id))
set.seed(child_seed)
```

`seed_block` is recorded in the DB record (§9.1) so any variant can be re-run bit-exactly.

### 9.5 Sampler (parent selection)

Default: top-3 gate-passers by primary fitness + 1 random gate-passer (diversity).

**Zero-gate-passer fallback (P4).** If the pool of gate-passers is empty (common in gen 0 and gen 1), the sampler degrades in this order:

1. Top-3 variants by primary fitness regardless of gate-pass status, + 1 random variant, **plus** a prompt flag `gate_failure_mode: true` that tells the proposer: "none of these parents passed gates — your proposals should specifically address <list of gate failures seen so far>."
2. If even `PROGRAM_DB.jsonl` is empty (generation 0), the sampler returns no parents and the proposer is given a "seed generation" prompt variant that asks for diverse starting feature sets from the whitelist.

The sampler never deadlocks.

---

## 10. Subagent proposer

### 10.1 Prompt template

Filled from `config.yaml` at runtime:

```
[System — persona: "expert statistical methodologist"]
[Project context: slot kind + estimator + DGP summary (≤ 300 words)]
[Grammar specification:
   whitelist, transforms (as descriptors), interactions, forbidden patterns, max_terms]
[Parent variants (top-3 + 1 random, or sampler-fallback set):
   feature_set_expr + screen scores + gate status for each]
[Failed-variant negative examples:
   capped at 5, oldest-first eviction — most recent failures win]
[Task: propose BATCH_SIZE new feature sets as a JSON array.]
[Output contract (see §10.2): strict JSON schema, no prose, no code fences preferred]
```

`model: "opus"` is **always explicit** (per `.claude/rules/codex-fallback-protocol.md`).

Per §3, this prompt is specialized to `slot.kind = feature_set`. A different slot kind (v2) will require a different prompt template.

### 10.2 JSON parse contract (P7, P20)

Expected output shape:

```json
[
  {"feature_set_expr": ["age", "log(log_time)", "age*sex"],
   "rationale": "short free text"},
  {"feature_set_expr": [...], "rationale": "..."}
]
```

**Robust parse pipeline:**

1. Strip Markdown code fences if present (` ```json ... ``` `).
2. Trim whitespace.
3. Attempt `jsonlite::fromJSON(simplifyVector = FALSE)`; require the root to be an array of objects each with a `feature_set_expr` string array.
4. If parse fails or shape mismatches, **retry once** with a correction prompt that includes the original response and the parser's error, asking the subagent to output valid JSON only. Save both attempts under `generations/gen_NN/`.
5. If the retry also fails, record the generation's failure in `EVOLVE_STATE.json`, checkpoint, and exit cleanly. User re-runs `/method-evolve run` to advance.

### 10.3 Negative-example cap (P6)

`max_negative_examples: 5`. Oldest-first eviction — the prompt always surfaces the most recent 5 grammar rejections so the proposer learns the current edge of the whitelist rather than ancient bugs. Total prompt size is capped so context does not blow up across generations.

---

## 11. Runtime model

### 11.1 Where each tier runs

| Tier | Environment | Mechanism |
|------|-------------|-----------|
| Skill workflow (subagent, DB, validator, reports) | Local Mac (Claude Code) | native |
| Screen MC evals (B=50, N=500, hardest scenario) | Local Mac | parallel R subprocesses via `mclapply` across variants; single-threaded within each |
| Full MC evals (top-K × full scenario grid) | Longleaf | user-run `sbatch` via skill-generated promote wrapper |
| Program DB, logs, reports | Local (OneDrive-synced) | native |
| Variant RDS cache | Local, non-synced (`~/.method-evolve-cache/…`) | native |

### 11.2 Local parallelism and worker isolation (P10)

- Parent R process manages the generation loop, the DB handle, and the state file.
- Children spawned via `mclapply(mc.cores = n_workers, mc.preschedule = FALSE)` to isolate failures.
- Each child runs `Rscript target_script` as a **subprocess**, not an in-process `source()` — this guarantees a worker crash (e.g., segfault in a native package) cannot corrupt the parent's memory.
- `mc.cleanup = TRUE` and explicit `tools::pskill` on the parent's SIGINT handler so `Ctrl-C` reliably kills all children.
- Per-child working directory is the variants_cache so OneDrive never sees per-variant writes.

### 11.3 `promote` and `ingest` (B4, P11, P14)

**`promote`** generates a **wrapper script** `scripts/slurm/evolve_<name>_promote.sh`:

1. Takes the top-`promote_top_k` gate-passing variants from the DB.
2. Writes `${out_dir}/promote_manifest.json` listing each (variant_id, rank, scenario, SLURM array index, output path). Paths follow `compute.full.promote.output_namespace` (§7) so every (variant × scenario × seed-block) triple has a **unique, collision-free output directory**.
3. Emits, to stdout, the exact `rsync` + `ssh` + `sbatch --array=...` commands to run, parameterized by the manifest.

The wrapper itself, when executed on Longleaf via `sbatch`, computes `v = variant_rank`, `s = scenario_index` from `$SLURM_ARRAY_TASK_ID` via `compute.full.promote.array_index_formula` and exports `FEATURE_SET_FILE`, `SCENARIO_NAME`, `SEED_BLOCK`, `VARIANT_ID` before calling the project's existing `submit_missing_types_ipw.sh` body. `${SCENARIO_NAME}` alone never names an output; the full namespace is always used (P14).

**`ingest`** is the results-flow-back command:

1. User runs `rsync` (commands printed by `promote`) to pull `${compute.full.promote.output_namespace}` back into `<subproject>/results_missing_types/full/`.
2. `method-evolve ingest` reads `promote_manifest.json`, walks the expected output paths, loads each per-variant×scenario RDS, aggregates across scenarios per variant, computes full-tier metrics (IBS, recovery, gate metrics at the tight `[0.93, 0.97]` coverage gate), and **patches the `full` field** in the corresponding DB record (by rewriting `PROGRAM_DB.jsonl` atomically: write to `.tmp`, fsync, rename).
3. Missing output directories are reported but do not block ingest of the rest.
4. `ingest` is idempotent — re-running it overwrites the `full` field with the latest computation.

`report` then consumes the patched DB to build the leaderboard.

### 11.4 Failure modes (unchanged from R1, clarified)

- Subagent parse failure → one retry, then clean checkpoint + exit (§10.2).
- Grammar validator rejection → recorded, continue.
- Evaluator subprocess crash → record `screen.status: "eval_error"`, continue.
- Local package missing → surfaced in Phase 2 smoke test, not mid-run.
- Longleaf Full timeout → surfaced when `ingest` finds no output; re-submit and re-ingest.

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
    top_feature_frequencies.pdf
    gate_pass_rate_by_gen.pdf
```

The `-NN` suffix (e.g., `2026-04-21_ipw-feature-search-02`) is appended automatically when a same-day re-run of the same `name` would otherwise collide (P22, per `CLAUDE.md` Skill Output Storage).

---

## 13. Project conventions honored

- `here::here()` for all paths inside generated driver scripts.
- `set.seed(YYYYMMDD)` at top of driver.
- Okabe-Ito palette for plots (`.claude/rules/r-code-conventions.md`).
- Dated subfolder per run with sequence-number suffix on collision (§12).
- Session logging per `.claude/rules/session-logging.md`.

---

## 14. Reference example — Missing Types / IPW

Shipped at `.claude/skills/method-evolve/examples/missing-types-ipw/config.yaml`. Used by:

- The skill's Phase 2 smoke test (covers: zero-parent seed generation, checkpoint-resume mid-generation, `promote` dry-run without actually submitting, zero-gate-passer case synthesized by tightening gates).
- The inferred default when `scan` runs inside `Missing Types/`.

Smoke test (P9) verifies these specific paths, not just the happy path.

---

## 15. Resumability contract (NEW, P16)

### 15.1 `EVOLVE_STATE.json` schema

```json
{
  "schema_version": 1,
  "run_id": "2026-04-21_ipw-feature-search",
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

- Additional slot kinds: `formula`, `hyperparameters`, `augmentation_fn`, `model_config`. Each requires its own grammar validator and proposer-prompt template (§3, §6.4).
- IPCW-weighted Brier alongside pseudo-Brier.
- Multi-island / MAP-Elites samplers.
- Joint evolution across estimators.
- Direct Anthropic API proposer with prompt caching.
- Optional GPT reviewer on promoted winners.
- `comparisons/` sub-project config (Cox / RF feature sets).
- SSH-automated promotion (`compute.full.ssh_submit: true` opt-in).

---

## 17. Explicit decisions log

| # | Decision | Chosen |
|---|---|---|
| 1 | Unit of evolution (v1) | `feature_set` (propensity covariates) |
| 2 | Target estimator (v1) | IPW |
| 3 | Primary fitness | IBS recovery ratio (pseudo-Brier, pinned) |
| 4 | Screen-tier gates | `|bias|<0.02`, `coverage∈[0.91,0.99]`, `c_index ≥ C_CCA−0.01` |
| 5 | Full-tier gates | `|bias|<0.02`, `coverage∈[0.93,0.97]`, `c_index ≥ C_CCA−0.01` |
| 6 | Grammar scope | whitelist + 5 typed transform descriptors + pairwise interactions |
| 7 | Evaluator | reuse existing script via env var; IBS prerequisite via `prereq` |
| 8 | Screen scenario | hardest (50% MAR / 60% censoring), denom-floor checked at setup |
| 9 | Reviewer loop | none (MC is the critic) |
| 10 | Proposer backend | Claude Opus subagent via Task tool (explicit `model: "opus"`) |
| 11 | Runtime shape | in-session, gen-chunked, resumable, mid-generation safe |
| 12 | Parallelism | `n_workers = 5`; parent-only DB writer; atomic ID allocation; derived per-child seeds |
| 13 | Skill scope | configurable for any `feature_set` search; tighter claim replaces "fully domain-agnostic" |
| 14 | Promote results flow | `promote` prints commands + writes manifest; `ingest` patches `full.*` fields |
| 15 | Same-day re-run folders | `-NN` suffix on name collision |
| 16 | CLI vs config precedence | CLI `max_gens` overrides `budget.max_generations` |
| 17 | Brier variant | pseudo-Brier (IPCW deferred to v2) |
