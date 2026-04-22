# `method-evolve` Skill v3 — Implementation Plan (general skill)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a general-purpose Claude Code skill that runs an evolutionary code-search loop over R Monte Carlo evaluators, with three v1 slot kinds (`feature_set`, `hyperparameters`, `formula`), configurable compute backends (`local` / `slurm` / `custom`), a typed prerequisite system, named-baseline fitness templates, and a self-contained synthetic Cox toy as the smoke-test reference example. No specific sub-project, estimator, metric, or baseline is assumed.

**Architecture:** Two-layer split (skill in parent repo + per-run config under `<subproject>/quality_reports/evolve/<date>_<name>/`). Engine is slot-kind-agnostic at the dispatcher level; each slot kind contributes a validator + proposer template + toy example. v2 of this plan (`2026-04-21_method-evolve-skill-implementation.md`) implemented T0 + T1 against a Missing-Types-flavored v2 spec; this v3 plan generalizes that work and adds the remaining tasks.

**Tech Stack:** R 4.4.0, `rlang` (parser/AST walker), `jsonlite` (DB serialization), `digest` (per-child seeds), `parallel::mclapply` (local backend), `testthat` 3.x, `here` (paths). SLURM cluster (any) for `slurm` backend. Synthetic toy uses `survival` only.

**Spec:** `quality_reports/specs/2026-04-21_method-evolve-design-v3-general.md`

**Predecessor plan:** `quality_reports/plans/2026-04-21_method-evolve-skill-implementation.md` — preserved for code references in MIGRATE tasks.

---

## Status legend

- **DONE** — implemented and committed; this plan summarizes the result and lists any follow-up.
- **MIGRATE** — code from the v2 plan exists; this plan describes the *delta* needed to make it v3-spec compliant. The MIGRATE step references the v2 plan's task and step numbers.
- **NEW** — no v2 implementation; full TDD bite-sized steps with complete code provided.
- **DEFER** — relocated to a non-shipped example; no engine work.

---

## Migration map (v2 task → v3 task)

| v2 task | v3 task(s) | Status | Notes |
|---|---|---|---|
| T0 | T0 | DONE | Scaffold; survives unchanged. |
| T1 | T1 + T2 | DONE + NEW | T1 source-patch applicator survives; T2 relocates IBS-specific template to `examples/missing_types_ipw/`. |
| T2 (baseline meta sidecar) | T3 | NEW | Generalized as `sidecar-meta` prereq type; baselines are user-named (no `oracle`/`CCA`). |
| — | T4 | NEW | New prereq type: `column-presence`. |
| — | T5 | NEW | New prereq type: `custom` (shell-out escape hatch). |
| T3 (config schema) | T6 | MIGRATE | Adds `baselines` named map, fitness templates, slot-kind dispatch, configurable backends. |
| T4 (grammar validator) | T7 + T8 + T9 | MIGRATE + NEW + NEW | T7 refactors v2 walker as `validators/feature_set.R` + adds dispatcher; T8 adds `hyperparameters` validator; T9 adds `formula` validator. |
| — | T10 | NEW | Fitness named-template engine + raw-`expr` escape hatch. |
| T5 (DB + atomic ID) | T11 | MIGRATE | DB record gets `slot_kind` field; `proposal_payload` shape varies by slot kind. |
| T6 (sampler) | T12 | MIGRATE | Sampler is already slot-kind-agnostic; minor rename only. |
| T7 (proposer) | T13 + T14 + T15 + T16 | MIGRATE + NEW × 3 | T13 adds slot-kind dispatcher to proposer; T14/T15/T16 are the three prompt templates. |
| T8 (evaluator + fitness) | T17 | MIGRATE | Replaces IBS-specific recovery with T10's fitness engine; replaces `oracle`/`CCA` with named lookups. |
| T9 (local runner) | T18 | MIGRATE | Tiny rename only — runner already calls `target_script` via env vars. |
| T10 (state machine) | T19 | MIGRATE | Bumps `schema_version` to 2; validates v3 `config_sha`. |
| — | T20 | NEW | Compute backend dispatcher (`local` | `slurm` | `custom`). |
| T11 (CLI wiring) | T21 | MIGRATE | Adds `slot.kind`-aware dispatch through subcommands. |
| T12/T14/T15 (SKILL.md) | T22 | MIGRATE | Single consolidated SKILL.md rewrite for v3. |
| T13 (scaffold generator) | T23 | MIGRATE | Driver template parameterized by slot.kind. |
| T16 (promote) | T24 | MIGRATE | Routes through compute backend dispatcher. |
| T17 (ingest) | T25 | MIGRATE | Slot-kind-agnostic; reads scalars from RDS. |
| T18 (report) | T26 | MIGRATE | Slot-kind-aware leaderboard plots. |
| — | T27 | NEW | Synthetic Cox toy evaluator (~60 lines) + baseline pre-computation. |
| — | T28 | NEW | Synthetic Cox toy config + baselines + demo `emit_extra_metric.patch`. |
| — | T29 | NEW | Hyperparameters toy (minimal duplicate). |
| — | T30 | NEW | Formula toy (minimal duplicate). |
| T19 (Missing Types reference config) | DEFER | DEFER | Moved to `examples/missing_types_ipw/`; not shipped/smoke-tested. Folded into T2. |
| T20 (end-to-end smoke) | T31 | MIGRATE | Re-targeted at synthetic Cox toy. |

---

## File Structure

```text
.claude/skills/method-evolve/
  SKILL.md                                     # T22 (rewritten)
  cli.R                                        # T0 (done) + T21 (extended)
  prereq.R                                     # T1 (done) + T3, T4, T5 (new types)
  templates/                                   # T1 patch templates only
    (no IBS-specific templates here in v3 — they move to examples/)
  validators/
    feature_set.R                              # T7 (refactored from v2 T4)
    hyperparameters.R                          # T8 (new)
    formula.R                                  # T9 (new)
    dispatch.R                                 # T7 (new — picks validator by slot.kind)
  fitness/
    templates.R                                # T10 (new — direct_metric/recovery/weighted_sum/raw)
  proposer/
    dispatch.R                                 # T13 (refactored from v2 T7)
    templates/
      feature_set.md                           # T14 (extracted from v2 T7's hardcoded prompt)
      hyperparameters.md                       # T15 (new)
      formula.md                               # T16 (new)
  db.R                                         # T11 (migrated from v2 T5)
  sampler.R                                    # T12 (migrated from v2 T6)
  evaluator.R                                  # T17 (migrated from v2 T8)
  runner_local.R                               # T18 (migrated from v2 T9)
  runner_slurm.R                               # T20 (new)
  runner_custom.R                              # T20 (new)
  runner_dispatch.R                            # T20 (new)
  state.R                                      # T19 (migrated from v2 T10)
  scaffold.R                                   # T23 (migrated from v2 T13)
  promote.R                                    # T24 (migrated from v2 T16)
  ingest.R                                     # T25 (migrated from v2 T17)
  report.R                                     # T26 (migrated from v2 T18)
  examples/
    synthetic_cox/                             # T27, T28 (new, smoke-tested)
      config.yaml
      toy_evaluator.R
      baselines/{lower,upper}.{rds,meta.json}
      templates/emit_extra_metric.patch
      README.md
    hyperparameters_toy/                       # T29 (new, smoke-tested)
      config.yaml
      baselines/{lower,upper}.{rds,meta.json}
      README.md
    formula_toy/                               # T30 (new, smoke-tested)
      config.yaml
      baselines/{lower,upper}.{rds,meta.json}
      README.md
    missing_types_ipw/                         # T2 (relocated, not shipped/smoke-tested)
      README.md
      templates/prereq_ibs.R.patch
  tests/
    testthat.R
    testthat/
      test-cli.R                               # T0 (done)
      test-prereq-source-patch.R               # T1 (done; renamed from test-prereq-ibs.R)
      test-prereq-sidecar-meta.R               # T3 (new)
      test-prereq-column-presence.R            # T4 (new)
      test-prereq-custom.R                     # T5 (new)
      test-config-schema.R                     # T6 (new)
      test-validator-feature-set.R             # T7 (renamed from test-validator.R)
      test-validator-hyperparameters.R         # T8 (new)
      test-validator-formula.R                 # T9 (new)
      test-fitness-templates.R                 # T10 (new)
      test-db.R                                # T11 (new)
      test-sampler.R                           # T12 (new)
      test-proposer-dispatch.R                 # T13 (new)
      test-evaluator.R                         # T17 (new)
      test-runner-local.R                      # T18 (new)
      test-runner-dispatch.R                   # T20 (new)
      test-state.R                             # T19 (new)
      test-cli-extended.R                      # T21 (new)
      test-scaffold.R                          # T23 (new)
      test-promote.R                           # T24 (new)
      test-ingest.R                            # T25 (new)
      test-report.R                            # T26 (new)
      test-smoke-synthetic-cox.R               # T31 (new)
```

---

## Conventions used throughout this plan

- All R paths use `here::here()` (anchored at the parent repo root).
- Tests use `testthat` 3.x edition; run via `Rscript .claude/skills/method-evolve/tests/testthat.R`.
- Each task ends in a single commit on `feat/method-evolve-skill`.
- Commit message format: `<type>(method-evolve): <terse description>` followed by Co-Authored-By footer.
- For MIGRATE tasks: when re-using v2 plan code, paste the v2 code into the new file under the new path, then apply the listed deltas. Do not edit the v2 plan file.
- Parent repo's `set.seed(20260421)` convention is followed in any stochastic test code.
- Each task that creates files documents both the **file path** and the **smallest test that verifies the new behavior**. Tests must be written first (red) and then made green.

---

## Task 0: Scaffold + CLI dispatcher — DONE

**Status:** DONE. Committed at `4a6da0e` on `feat/method-evolve-skill`.

**What landed:** Skill directory at `.claude/skills/method-evolve/`, `cli.R` dispatcher with subcommand routing, stub `SKILL.md` with frontmatter, `tests/testthat.R` runner, `tests/testthat/test-cli.R` (2 tests passing).

**Follow-up for v3:** none direct; T22 will rewrite `SKILL.md` end-to-end.

**Reference:** v2 plan §Task 0 (lines 99–254).

---

## Task 1: Phase −1 source-patch applicator + version stamping — DONE

**Status:** DONE. Committed at `6a94453` and `35d4e4f` on `feat/method-evolve-skill`; submodule pointer bumped.

**What landed:** `prereq.R` with `apply_source_patch()` and `check_source_patch_version()`; `templates/prereq_ibs.R.patch` (Missing-Types-specific); `pseudo_brier.R` helper inside the Missing Types submodule; `test-prereq-ibs.R` (5 tests passing). The applicator detects via header stamp `# ibs-patch-version: 1`, applies patch_template once, and is idempotent on re-run.

**Follow-up for v3:** see T2 (relocate the IBS-specific patch template out of the skill's `templates/` and into `examples/missing_types_ipw/templates/`). The applicator code in `prereq.R` is generic and survives unchanged; only the *template file* moves.

**Reference:** v2 plan §Task 1 (lines 257–544).

---

## Task 2: Relocate IBS-specific patch template to examples — NEW

**Files:**
- Move: `.claude/skills/method-evolve/templates/prereq_ibs.R.patch` → `.claude/skills/method-evolve/examples/missing_types_ipw/templates/prereq_ibs.R.patch`
- Create: `.claude/skills/method-evolve/examples/missing_types_ipw/README.md`
- Modify: `.claude/skills/method-evolve/tests/testthat/test-prereq-ibs.R` → rename to `test-prereq-source-patch.R` and update the `patch_template` path used in tests.

**Goal:** Get IBS-specific content out of the skill's default `templates/` so the skill itself contains zero project-specific patches. The `examples/missing_types_ipw/` folder becomes a standalone illustrative example (not smoke-tested, not shipped as default).

- [ ] **Step 1: Create the new directory and move the patch file**

```bash
mkdir -p .claude/skills/method-evolve/examples/missing_types_ipw/templates
git mv .claude/skills/method-evolve/templates/prereq_ibs.R.patch \
       .claude/skills/method-evolve/examples/missing_types_ipw/templates/prereq_ibs.R.patch
```

- [ ] **Step 2: Write the example README**

Create `.claude/skills/method-evolve/examples/missing_types_ipw/README.md`:

```markdown
# Missing Types / IPW — illustrative example (NOT shipped, NOT smoke-tested)

This folder contains a project-flavored example config for using `method-evolve`
to search over IPW propensity feature sets in the Missing Types sub-project. It
is *not* exercised by the skill's smoke test and is not required for the skill
to run anywhere — it exists only to illustrate how a realistic, statistically
non-trivial config looks end-to-end.

The `templates/prereq_ibs.R.patch` patch adds an integrated pseudo-Brier (IBS)
column to a sub-project evaluator. Apply it via:

  /method-evolve prereq --config-path examples/missing_types_ipw/config.yaml

For the skill's actual smoke test (zero external dependencies), see
`examples/synthetic_cox/`.
```

- [ ] **Step 3: Update test paths**

```bash
git mv .claude/skills/method-evolve/tests/testthat/test-prereq-ibs.R \
       .claude/skills/method-evolve/tests/testthat/test-prereq-source-patch.R
```

In `test-prereq-source-patch.R`, replace the literal `templates/prereq_ibs.R.patch` path with `examples/missing_types_ipw/templates/prereq_ibs.R.patch`. Run the test from parent repo root and from the skill directory (both must pass).

- [ ] **Step 4: Run the renamed tests**

```bash
Rscript .claude/skills/method-evolve/tests/testthat.R
```

Expected: `FAIL 0 | WARN 0 | SKIP 0 | PASS 8` (cli×2 + prereq-source-patch×5 + 1 extra).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/method-evolve/
git commit -m "$(cat <<'EOF'
refactor(method-evolve): relocate IBS patch template to examples folder

Moves the Missing-Types-specific IBS patch out of the skill's default
templates/ and into examples/missing_types_ipw/ as an illustrative,
non-shipped example. Updates test paths to match. Source-patch
applicator code is unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Sidecar-meta prerequisite type — NEW

**Files:**
- Modify: `.claude/skills/method-evolve/prereq.R` (add `check_sidecar_meta()` and dispatcher entry)
- Create: `.claude/skills/method-evolve/tests/testthat/test-prereq-sidecar-meta.R`

**Goal:** Add a second prereq type that verifies named baseline RDS files have accompanying `.meta.json` sidecars whose hard keys match `config.yaml`. Per spec §5.1.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-prereq-sidecar-meta.R`:

```r
library(testthat)
library(here)
source(here("..", "..", "prereq.R"))

test_that("check_sidecar_meta passes when all required keys match", {
  tdir <- tempfile(); dir.create(tdir)
  rds_path  <- file.path(tdir, "lower.rds")
  meta_path <- file.path(tdir, "lower.meta.json")
  saveRDS(data.frame(x = 1), rds_path)
  jsonlite::write_json(list(
    scenario_name  = "smoke", n_subjects = 100, n_sims = 2,
    dgp_version    = "test-v1", evaluator_sha = "abc123def456"
  ), meta_path, auto_unbox = TRUE)

  cfg <- list(
    baselines = list(lower = list(results_file = rds_path, meta_file = meta_path)),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke",
                                     N_SUBJECTS = 100, N_SIMS = 2))
  )
  prereq <- list(id = "baseline-meta", type = "sidecar-meta",
                 required_for = "lower",
                 required_keys = c("scenario_name","n_subjects","n_sims"))
  expect_true(check_sidecar_meta(prereq, cfg)$pass)
})

test_that("check_sidecar_meta fails on hard-key mismatch", {
  tdir <- tempfile(); dir.create(tdir)
  meta_path <- file.path(tdir, "lower.meta.json")
  saveRDS(data.frame(x=1), file.path(tdir, "lower.rds"))
  jsonlite::write_json(list(scenario_name = "different",
                            n_subjects = 100, n_sims = 2),
                       meta_path, auto_unbox = TRUE)
  cfg <- list(
    baselines = list(lower = list(results_file = file.path(tdir,"lower.rds"),
                                  meta_file = meta_path)),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke",
                                     N_SUBJECTS = 100, N_SIMS = 2))
  )
  prereq <- list(id = "baseline-meta", type = "sidecar-meta",
                 required_for = "lower",
                 required_keys = c("scenario_name","n_subjects","n_sims"))
  res <- check_sidecar_meta(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "scenario_name")
})

test_that("check_sidecar_meta fails when meta file is missing", {
  tdir <- tempfile(); dir.create(tdir)
  saveRDS(data.frame(x=1), file.path(tdir, "lower.rds"))
  cfg <- list(
    baselines = list(lower = list(results_file = file.path(tdir,"lower.rds"),
                                  meta_file = file.path(tdir,"lower.meta.json"))),
    evaluator = list(env_vars = list())
  )
  prereq <- list(id = "baseline-meta", type = "sidecar-meta",
                 required_for = "lower", required_keys = c("scenario_name"))
  res <- check_sidecar_meta(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "meta file missing")
})
```

- [ ] **Step 2: Run to confirm RED**

```bash
Rscript .claude/skills/method-evolve/tests/testthat.R
```

Expected: 3 failures referencing `check_sidecar_meta` not found.

- [ ] **Step 3: Implement `check_sidecar_meta()` in `prereq.R`**

Append to `.claude/skills/method-evolve/prereq.R`:

```r
#' Verify that named baselines have accompanying .meta.json sidecars
#' whose hard keys match the configuration.
#'
#' @param prereq A prerequisite spec list with fields:
#'   id (str), type ("sidecar-meta"), required_for (chr vec of baseline names),
#'   required_keys (chr vec of JSON keys to compare; default below).
#' @param cfg The full parsed config.yaml (must contain $baselines and
#'   $evaluator$env_vars).
#' @return list(pass = logical, reason = character).
check_sidecar_meta <- function(prereq, cfg) {
  default_keys <- c("scenario_name", "n_subjects", "n_sims",
                    "dgp_version",  "evaluator_sha")
  keys <- prereq$required_keys %||% default_keys

  # config-side values (drawn from evaluator.env_vars where present)
  cfg_vals <- list(
    scenario_name = cfg$evaluator$env_vars$SCENARIO_NAME,
    n_subjects    = as.integer(cfg$evaluator$env_vars$N_SUBJECTS %||% NA),
    n_sims        = as.integer(cfg$evaluator$env_vars$N_SIMS %||% NA)
  )

  for (b in prereq$required_for) {
    bcfg <- cfg$baselines[[b]]
    if (is.null(bcfg) || is.null(bcfg$meta_file)) {
      return(list(pass = FALSE,
                  reason = sprintf("baseline '%s': meta_file not declared", b)))
    }
    if (!file.exists(bcfg$meta_file)) {
      return(list(pass = FALSE,
                  reason = sprintf("baseline '%s': meta file missing at %s",
                                   b, bcfg$meta_file)))
    }
    meta <- jsonlite::read_json(bcfg$meta_file, simplifyVector = TRUE)
    for (k in keys) {
      if (!k %in% names(cfg_vals)) next  # evaluator_sha & dgp_version: warn-only
      if (!identical(meta[[k]], cfg_vals[[k]])) {
        return(list(pass = FALSE,
                    reason = sprintf(
                      "baseline '%s': key %s mismatch (meta=%s, config=%s)",
                      b, k,
                      paste(meta[[k]], collapse = ","),
                      paste(cfg_vals[[k]], collapse = ","))))
      }
    }
  }
  list(pass = TRUE, reason = "all sidecar-meta keys match")
}

# Helper used above (idempotent if defined elsewhere).
`%||%` <- function(a, b) if (is.null(a)) b else a
```

- [ ] **Step 4: Run to confirm GREEN**

```bash
Rscript .claude/skills/method-evolve/tests/testthat.R
```

Expected: `FAIL 0 | WARN 0 | SKIP 0 | PASS 11` (cli×2 + source-patch×5 + sidecar-meta×3 + 1 extra).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/method-evolve/prereq.R \
        .claude/skills/method-evolve/tests/testthat/test-prereq-sidecar-meta.R
git commit -m "feat(method-evolve): add sidecar-meta prereq type (T3)

Implements check_sidecar_meta() verifying named baselines have .meta.json
sidecars whose scenario_name/n_subjects/n_sims match the config.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Column-presence prerequisite type — NEW

**Files:**
- Modify: `.claude/skills/method-evolve/prereq.R` (add `check_column_presence()`)
- Create: `.claude/skills/method-evolve/tests/testthat/test-prereq-column-presence.R`

**Goal:** Add a third prereq type that runs the evaluator script in a smoke-mode (overridden env vars for a tiny run) and verifies the named columns appear in the result data frame and are numeric with no `NA`. Per spec §5.1.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-prereq-column-presence.R`:

```r
library(testthat)
library(here)
source(here("..", "..", "prereq.R"))

write_dummy_eval <- function(tdir, cols = c("a","b"), with_na = FALSE) {
  script <- file.path(tdir, "dummy.R")
  writeLines(sprintf(
    "df <- data.frame(%s)\nsaveRDS(df, '%s')",
    paste(sprintf("%s = %s", cols,
                  if (with_na) "c(1, NA)" else "1:2"),
          collapse = ", "),
    file.path(tdir, "out.rds")), script)
  script
}

test_that("check_column_presence passes when all named columns appear", {
  tdir <- tempfile(); dir.create(tdir)
  script <- write_dummy_eval(tdir, cols = c("metric","c_index"))
  cfg <- list(
    target_script = script,
    evaluator = list(
      env_vars = list(),
      results_file_pattern = file.path(tdir, "out.rds")
    )
  )
  prereq <- list(id = "cols", type = "column-presence",
                 smoke_env_vars = list(),
                 required_columns = c("metric","c_index"))
  expect_true(check_column_presence(prereq, cfg)$pass)
})

test_that("check_column_presence fails on missing column", {
  tdir <- tempfile(); dir.create(tdir)
  script <- write_dummy_eval(tdir, cols = c("metric"))
  cfg <- list(
    target_script = script,
    evaluator = list(env_vars = list(),
                     results_file_pattern = file.path(tdir, "out.rds"))
  )
  prereq <- list(id = "cols", type = "column-presence",
                 smoke_env_vars = list(),
                 required_columns = c("metric","c_index"))
  res <- check_column_presence(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "c_index")
})

test_that("check_column_presence fails on NA in required column", {
  tdir <- tempfile(); dir.create(tdir)
  script <- write_dummy_eval(tdir, cols = c("metric"), with_na = TRUE)
  cfg <- list(
    target_script = script,
    evaluator = list(env_vars = list(),
                     results_file_pattern = file.path(tdir, "out.rds"))
  )
  prereq <- list(id = "cols", type = "column-presence",
                 smoke_env_vars = list(), required_columns = c("metric"))
  res <- check_column_presence(prereq, cfg)
  expect_false(res$pass)
  expect_match(res$reason, "NA")
})
```

- [ ] **Step 2: Run to confirm RED**

```bash
Rscript .claude/skills/method-evolve/tests/testthat.R
```

Expected: 3 failures naming `check_column_presence`.

- [ ] **Step 3: Implement `check_column_presence()` in `prereq.R`**

Append to `prereq.R`:

```r
#' Run the evaluator in smoke mode and verify named columns are present.
#'
#' @param prereq list with: id, type ("column-presence"), smoke_env_vars (named list),
#'   required_columns (chr vec).
#' @param cfg full config; uses cfg$target_script and cfg$evaluator$results_file_pattern.
check_column_presence <- function(prereq, cfg) {
  env_kvs <- c(prereq$smoke_env_vars, cfg$evaluator$env_vars)
  env_str <- vapply(seq_along(env_kvs), function(i)
                    sprintf("%s=%s", names(env_kvs)[i], env_kvs[[i]]),
                    character(1))

  status <- system2("Rscript", c("--vanilla", shQuote(cfg$target_script)),
                    env = env_str, stdout = NULL, stderr = NULL)
  if (status != 0) {
    return(list(pass = FALSE,
                reason = sprintf("evaluator exited non-zero (status=%d)", status)))
  }
  out_path <- cfg$evaluator$results_file_pattern
  if (!file.exists(out_path)) {
    return(list(pass = FALSE,
                reason = sprintf("results file not found at %s", out_path)))
  }
  df <- readRDS(out_path)
  missing <- setdiff(prereq$required_columns, names(df))
  if (length(missing) > 0) {
    return(list(pass = FALSE,
                reason = sprintf("missing columns: %s",
                                 paste(missing, collapse = ", "))))
  }
  for (col in prereq$required_columns) {
    if (!is.numeric(df[[col]])) {
      return(list(pass = FALSE,
                  reason = sprintf("column %s is not numeric", col)))
    }
    if (anyNA(df[[col]])) {
      return(list(pass = FALSE,
                  reason = sprintf("column %s contains NA", col)))
    }
  }
  list(pass = TRUE, reason = "all required columns present and numeric")
}
```

- [ ] **Step 4: Run to confirm GREEN**

Expected: `PASS 14` (prior 11 + 3 column-presence).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/method-evolve/prereq.R \
        .claude/skills/method-evolve/tests/testthat/test-prereq-column-presence.R
git commit -m "feat(method-evolve): add column-presence prereq type (T4)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Custom (shell-out) prerequisite type — NEW

**Files:**
- Modify: `.claude/skills/method-evolve/prereq.R` (add `check_custom()`)
- Create: `.claude/skills/method-evolve/tests/testthat/test-prereq-custom.R`

**Goal:** Final prereq type. User declares `type: custom` with a `check_command:` shell string; non-zero exit ⇒ fail. Per spec §5.3.

- [ ] **Step 1: Write the failing test**

```r
library(testthat)
library(here)
source(here("..", "..", "prereq.R"))

test_that("check_custom passes on zero exit", {
  prereq <- list(id = "ok", type = "custom", check_command = "true")
  expect_true(check_custom(prereq, list())$pass)
})

test_that("check_custom fails on non-zero exit", {
  prereq <- list(id = "fail", type = "custom", check_command = "false")
  res <- check_custom(prereq, list())
  expect_false(res$pass)
  expect_match(res$reason, "non-zero exit")
})
```

- [ ] **Step 2: Run to confirm RED**

Expected: 2 failures naming `check_custom`.

- [ ] **Step 3: Implement**

Append to `prereq.R`:

```r
check_custom <- function(prereq, cfg) {
  status <- system(prereq$check_command, intern = FALSE,
                   ignore.stdout = TRUE, ignore.stderr = TRUE)
  if (status == 0) {
    list(pass = TRUE, reason = "custom check returned zero")
  } else {
    list(pass = FALSE,
         reason = sprintf("custom check returned non-zero exit (status=%d)", status))
  }
}
```

Also: add the dispatcher that picks the right `check_*` by `prereq$type`:

```r
run_prereq_check <- function(prereq, cfg) {
  switch(prereq$type,
    `source-patch`     = check_source_patch_version(prereq, cfg),
    `sidecar-meta`     = check_sidecar_meta(prereq, cfg),
    `column-presence`  = check_column_presence(prereq, cfg),
    `custom`           = check_custom(prereq, cfg),
    stop(sprintf("unknown prereq type: %s", prereq$type))
  )
}
```

- [ ] **Step 4: GREEN**

Expected: `PASS 16` (prior 14 + 2 custom).

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): add custom prereq type + dispatcher (T5)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Generalized config schema — MIGRATE (from v2 T3)

**Files:**
- Create: `.claude/skills/method-evolve/config_schema.R` (validator + parser)
- Create: `.claude/skills/method-evolve/tests/testthat/test-config-schema.R`

**Goal:** Replace v2's IPW-flavored config schema with the v3 schema (spec §7). Key differences from v2 T3:

| v2 field | v3 field | Change |
|---|---|---|
| `baselines.oracle`, `baselines.CCA` | `baselines.<user-named>` (named map) | named map |
| `fitness.primary = recovery_IBS` (string literal) | `fitness.primary` is a `template:` block or `expr:` string | structured |
| `fitness.brier_variant: pseudo_brier` | (deleted; no Brier-specific field) | removed |
| (no slot-kind field) | `slot.kind` ∈ {`feature_set`, `hyperparameters`, `formula`} | new |
| `compute.full.existing_submit` (string) | `compute.full.backend` ∈ {`local`, `slurm`, `custom`} + per-backend fields | restructured |

- [ ] **Step 1: Write the failing test**

Create `test-config-schema.R`:

```r
library(testthat)
library(here)
source(here("..", "..", "config_schema.R"))

minimal_cfg <- function(slot_kind = "feature_set") {
  cfg <- list(
    name = "t",
    target_script = "scripts/R/eval.R",
    prerequisites = list(),
    evaluator = list(env_vars = list(SCENARIO_NAME = "smoke", N_SIMS = 2L,
                                     N_SUBJECTS = 50L),
                     results_file_pattern = "out.rds"),
    substitutions = list(freeze_on_setup = c("run_date","name"),
                         per_variant = c("VARIANT_PATH","VARIANT_ID","SEED_BLOCK"),
                         refreeze_behavior = "error"),
    slot = list(kind = slot_kind, max_terms = 5,
                whitelist = c("x1","x2"), transforms = list(),
                interactions = "pairwise", forbidden_patterns = character()),
    baselines = list(lower = list(results_file = "lower.rds",
                                  meta_file = "lower.meta.json"),
                     upper = list(results_file = "upper.rds",
                                  meta_file = "upper.meta.json")),
    fitness = list(primary = list(template = "recovery_ratio",
                                  target = "m", lower = "lower.m",
                                  upper = "upper.m",
                                  direction = "higher_is_better"),
                   recovery = list(denom_floor_epsilon = 0.002,
                                   degenerate_scenario_action = "reject_and_halt",
                                   degenerate_variant_fallback = list(
                                     fallback_metric = "neg:m", cap = 0))),
    gates = list(list(metric = "abs_bias", tier = "both",
                      op = "<", threshold = 0.02)),
    budget = list(max_variants = 10, batch_size = 2,
                  max_generations = 3, promote_top_k = 2,
                  early_stop_after = 5),
    compute = list(screen = list(backend = "local", n_workers = 2),
                   full = list(backend = "local")),
    paths = list(out_dir = "out", variants_dir = "out/variants",
                 program_db = "out/db.jsonl",
                 state_file  = "out/state.json")
  )
  cfg
}

test_that("validate_config accepts a minimal feature_set config", {
  expect_silent(validate_config(minimal_cfg("feature_set")))
})

test_that("validate_config rejects unknown slot.kind", {
  cfg <- minimal_cfg(); cfg$slot$kind <- "weird_thing"
  expect_error(validate_config(cfg), "unknown slot.kind")
})

test_that("validate_config rejects baselines lacking required_for entries", {
  cfg <- minimal_cfg()
  cfg$prerequisites <- list(list(id = "x", type = "sidecar-meta",
                                 required_for = "missing_baseline"))
  expect_error(validate_config(cfg), "missing_baseline")
})

test_that("validate_config rejects fitness.primary referencing unknown column", {
  cfg <- minimal_cfg()
  # 'unknown_col' is not declared as a baseline accessor or known scalar;
  # validator should warn but not error in v1 (column-presence prereq is
  # the canonical guard). Tighten to error if no column-presence prereq.
  cfg$fitness$primary$target <- "unknown_col"
  cfg$prerequisites <- list()  # no column-presence prereq
  expect_warning(validate_config(cfg), "unknown_col")
})

test_that("validate_config rejects unknown compute backend", {
  cfg <- minimal_cfg()
  cfg$compute$full$backend <- "bogus"
  expect_error(validate_config(cfg), "backend.*bogus")
})
```

- [ ] **Step 2: RED**

Expected: errors about `validate_config` not found.

- [ ] **Step 3: Implement `config_schema.R`**

```r
# config_schema.R — v3 config validator
SLOT_KINDS <- c("feature_set", "hyperparameters", "formula")
BACKENDS   <- c("local", "slurm", "custom")
PREREQ_TYPES <- c("source-patch","sidecar-meta","column-presence","custom")

validate_config <- function(cfg) {
  required_top <- c("name","target_script","evaluator","substitutions",
                    "slot","baselines","fitness","gates","budget",
                    "compute","paths")
  miss <- setdiff(required_top, names(cfg))
  if (length(miss)) stop(sprintf("config missing top-level keys: %s",
                                 paste(miss, collapse = ", ")))

  if (!cfg$slot$kind %in% SLOT_KINDS)
    stop(sprintf("unknown slot.kind: %s (allowed: %s)",
                 cfg$slot$kind, paste(SLOT_KINDS, collapse = ", ")))

  for (tier in c("screen","full")) {
    b <- cfg$compute[[tier]]$backend
    if (!b %in% BACKENDS)
      stop(sprintf("compute.%s.backend invalid: %s (allowed: %s)",
                   tier, b, paste(BACKENDS, collapse = ", ")))
  }

  for (p in cfg$prerequisites %||% list()) {
    if (!p$type %in% PREREQ_TYPES)
      stop(sprintf("prerequisite '%s': unknown type %s", p$id, p$type))
    if (p$type == "sidecar-meta") {
      miss_b <- setdiff(p$required_for, names(cfg$baselines))
      if (length(miss_b))
        stop(sprintf("prereq '%s' references undeclared baselines: %s",
                     p$id, paste(miss_b, collapse = ", ")))
    }
  }

  fp <- cfg$fitness$primary
  if (!is.null(fp$expr)) {
    # raw expression — light syntactic check only
    rlang::parse_expr(fp$expr)
  } else if (!is.null(fp$template)) {
    if (!fp$template %in% c("direct_metric","recovery_ratio","weighted_sum"))
      stop(sprintf("fitness.primary.template invalid: %s", fp$template))
    if (fp$template %in% c("direct_metric","recovery_ratio")) {
      tgt <- fp$target
      has_colpres <- any(vapply(cfg$prerequisites %||% list(),
                                function(p) p$type == "column-presence" &&
                                            tgt %in% p$required_columns,
                                logical(1)))
      if (!has_colpres) warning(sprintf(
        "fitness.primary.target '%s' is not declared in any column-presence prereq",
        tgt))
    }
  } else stop("fitness.primary must have either 'template' or 'expr'")

  invisible(TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
```

- [ ] **Step 4: GREEN**

Expected: `PASS 21` (prior 16 + 5 schema tests).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/method-evolve/config_schema.R \
        .claude/skills/method-evolve/tests/testthat/test-config-schema.R
git commit -m "feat(method-evolve): add v3 config schema validator (T6)

Replaces v2's IPW-flavored schema with named-baseline map, slot.kind
dispatch, fitness templates/expr, and configurable backends.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Slot-kind dispatcher + feature_set validator refactor — MIGRATE (from v2 T4)

**Files:**
- Create: `.claude/skills/method-evolve/validators/dispatch.R`
- Create: `.claude/skills/method-evolve/validators/feature_set.R` (extracted from v2 T4 step 3 code, lines 1104–1185)
- Move: `.claude/skills/method-evolve/tests/testthat/test-validator.R` → `test-validator-feature-set.R`

**Goal:** Refactor v2's monolithic validator into a slot-kind dispatcher + a per-kind validator file.

- [ ] **Step 1: Move v2's walker code into `validators/feature_set.R`**

Copy the v2 plan's T4 step 3 walker (`walk_term`, `check_base`, `check_transform`, `check_interaction`, `validate_feature_set`) verbatim into the new file. Wrap exports in:

```r
# validators/feature_set.R
validate_feature_set <- function(payload, slot_cfg) {
  # …v2 T4 step 3 body…
  # returns list(grammar_valid = logical, failure_reason = character or NULL)
}
```

- [ ] **Step 2: Write the dispatcher**

Create `validators/dispatch.R`:

```r
source(here::here(".claude/skills/method-evolve/validators/feature_set.R"))
source(here::here(".claude/skills/method-evolve/validators/hyperparameters.R"))
source(here::here(".claude/skills/method-evolve/validators/formula.R"))

validate_proposal <- function(payload, slot_cfg) {
  switch(slot_cfg$kind,
    feature_set     = validate_feature_set(payload, slot_cfg),
    hyperparameters = validate_hyperparameters(payload, slot_cfg),
    formula         = validate_formula(payload, slot_cfg),
    stop(sprintf("unknown slot.kind: %s", slot_cfg$kind))
  )
}
```

- [ ] **Step 3: Move the test file and update sourcing**

```bash
git mv .claude/skills/method-evolve/tests/testthat/test-validator.R \
       .claude/skills/method-evolve/tests/testthat/test-validator-feature-set.R
```

In the renamed test, change `source("validator.R")` to `source(here::here(".claude/skills/method-evolve/validators/feature_set.R"))`.

- [ ] **Step 4: Run; will fail because hyperparameters.R / formula.R don't exist yet**

Expected: dispatcher source error. Stub-create empty `validators/hyperparameters.R` and `validators/formula.R` containing only:

```r
validate_hyperparameters <- function(payload, slot_cfg)
  stop("validate_hyperparameters not yet implemented (T8)")
validate_formula <- function(payload, slot_cfg)
  stop("validate_formula not yet implemented (T9)")
```

Re-run. Tests should pass (dispatcher is sourced but `feature_set` tests don't exercise the stubs).

Expected: `PASS 21` retained (no new tests yet for the dispatcher itself; just refactor).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/method-evolve/validators/ \
        .claude/skills/method-evolve/tests/testthat/test-validator-feature-set.R
git commit -m "refactor(method-evolve): extract feature_set validator + add dispatcher (T7)

Splits v2's monolithic validator into validators/feature_set.R and
validators/dispatch.R. Stubs for hyperparameters and formula validators
(implemented in T8/T9) emit clear 'not yet implemented' errors.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Hyperparameters slot validator — NEW

**Files:**
- Modify: `.claude/skills/method-evolve/validators/hyperparameters.R` (replace T7's stub with real impl)
- Create: `.claude/skills/method-evolve/tests/testthat/test-validator-hyperparameters.R`

**Goal:** JSON-schema-style validator. Per spec §6.2.

- [ ] **Step 1: Write the failing tests**

```r
library(testthat)
library(here)
source(here(".claude/skills/method-evolve/validators/hyperparameters.R"))

slot_cfg <- list(
  kind = "hyperparameters",
  params = list(
    mtry      = list(type = "integer",     range = c(1, 20)),
    ntree     = list(type = "integer",     range = c(100, 2000), log_scale = TRUE),
    splitrule = list(type = "categorical", enum  = c("gini","extratrees"))
  )
)

test_that("validate_hyperparameters accepts valid in-range values", {
  payload <- list(hyperparameters = list(mtry = 5, ntree = 500,
                                         splitrule = "gini"))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_true(res$grammar_valid); expect_null(res$failure_reason)
})

test_that("validate_hyperparameters rejects unknown parameter key", {
  payload <- list(hyperparameters = list(mtry = 5, ntree = 500,
                                         splitrule = "gini", extra = 99))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "unknown parameter")
})

test_that("validate_hyperparameters rejects out-of-range integer", {
  payload <- list(hyperparameters = list(mtry = 999, ntree = 500,
                                         splitrule = "gini"))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "mtry.*range")
})

test_that("validate_hyperparameters rejects categorical not in enum", {
  payload <- list(hyperparameters = list(mtry = 5, ntree = 500,
                                         splitrule = "weird"))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "splitrule.*enum")
})

test_that("validate_hyperparameters rejects type mismatch", {
  payload <- list(hyperparameters = list(mtry = "five", ntree = 500,
                                         splitrule = "gini"))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "mtry.*integer")
})

test_that("validate_hyperparameters rejects missing required key", {
  payload <- list(hyperparameters = list(mtry = 5, ntree = 500))
  res <- validate_hyperparameters(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "missing.*splitrule")
})
```

- [ ] **Step 2: RED**

Expected: 6 failures (the stub errors out).

- [ ] **Step 3: Implement**

Replace `validators/hyperparameters.R`:

```r
validate_hyperparameters <- function(payload, slot_cfg) {
  hp <- payload$hyperparameters
  if (is.null(hp) || !is.list(hp))
    return(list(grammar_valid = FALSE,
                failure_reason = "missing payload.hyperparameters"))

  declared <- names(slot_cfg$params)
  given    <- names(hp)
  unknown  <- setdiff(given, declared)
  if (length(unknown))
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("unknown parameter key(s): %s",
                                         paste(unknown, collapse = ","))))
  missing  <- setdiff(declared, given)
  if (length(missing))
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("missing required key(s): %s",
                                         paste(missing, collapse = ","))))

  for (k in declared) {
    spec <- slot_cfg$params[[k]]; v <- hp[[k]]
    if (spec$type == "integer") {
      if (!is.numeric(v) || v != as.integer(v))
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: not integer", k)))
      if (v < spec$range[1] || v > spec$range[2])
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: out of range [%s,%s]",
                                             k, spec$range[1], spec$range[2])))
    } else if (spec$type == "numeric") {
      if (!is.numeric(v))
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: not numeric", k)))
      if (v < spec$range[1] || v > spec$range[2])
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: out of range", k)))
    } else if (spec$type == "categorical") {
      if (!v %in% spec$enum)
        return(list(grammar_valid = FALSE,
                    failure_reason = sprintf("%s: not in enum (%s)",
                                             k, paste(spec$enum, collapse = ","))))
    } else {
      return(list(grammar_valid = FALSE,
                  failure_reason = sprintf("%s: unknown spec type %s",
                                           k, spec$type)))
    }
  }
  list(grammar_valid = TRUE, failure_reason = NULL)
}
```

- [ ] **Step 4: GREEN**

Expected: `PASS 27` (prior 21 + 6).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/method-evolve/validators/hyperparameters.R \
        .claude/skills/method-evolve/tests/testthat/test-validator-hyperparameters.R
git commit -m "feat(method-evolve): add hyperparameters slot validator (T8)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Formula slot validator — NEW

**Files:**
- Modify: `.claude/skills/method-evolve/validators/formula.R` (replace stub)
- Create: `.claude/skills/method-evolve/tests/testthat/test-validator-formula.R`

**Goal:** Parse with `stats::as.formula`, verify LHS matches `slot_cfg$lhs`, walk RHS using the `feature_set` walker. Per spec §6.3.

- [ ] **Step 1: Write the failing tests**

```r
library(testthat)
library(here)
source(here(".claude/skills/method-evolve/validators/feature_set.R"))
source(here(".claude/skills/method-evolve/validators/formula.R"))

slot_cfg <- list(
  kind = "formula",
  lhs  = "Surv(time, event)",
  whitelist = c("x1","x2","x3"),
  transforms = list(
    list(name = "log", head = "log", arity = 1L)
  ),
  interactions = "pairwise",
  forbidden_patterns = character(),
  max_terms = 5
)

test_that("validate_formula accepts a valid formula", {
  payload <- list(formula_str = "Surv(time, event) ~ x1 + log(x2) + x1*x3")
  res <- validate_formula(payload, slot_cfg)
  expect_true(res$grammar_valid)
})

test_that("validate_formula rejects mismatched LHS", {
  payload <- list(formula_str = "y ~ x1 + x2")
  res <- validate_formula(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "lhs.*mismatch")
})

test_that("validate_formula rejects unparseable strings", {
  payload <- list(formula_str = "not a formula at all")
  res <- validate_formula(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "parse_error")
})

test_that("validate_formula rejects RHS with non-whitelisted base", {
  payload <- list(formula_str = "Surv(time, event) ~ x1 + bogus_var")
  res <- validate_formula(payload, slot_cfg)
  expect_false(res$grammar_valid)
  expect_match(res$failure_reason, "bogus_var")
})
```

- [ ] **Step 2: RED**

- [ ] **Step 3: Implement**

```r
# validators/formula.R
validate_formula <- function(payload, slot_cfg) {
  s <- payload$formula_str
  if (is.null(s) || !is.character(s) || length(s) != 1L)
    return(list(grammar_valid = FALSE,
                failure_reason = "missing payload.formula_str"))

  f <- tryCatch(stats::as.formula(s), error = function(e) e)
  if (inherits(f, "error"))
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("parse_error: %s", conditionMessage(f))))

  lhs_observed <- deparse(f[[2]])
  if (!identical(lhs_observed, slot_cfg$lhs))
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("lhs mismatch: expected '%s', got '%s'",
                                         slot_cfg$lhs, lhs_observed)))

  # Walk RHS terms by reusing the feature_set walker. Convert RHS to a
  # character vector of terms using stats::terms().
  rhs_terms <- attr(stats::terms(f), "term.labels")
  fake_payload <- list(feature_set_expr = rhs_terms)
  res <- validate_feature_set(fake_payload, slot_cfg)  # reuses walker
  if (!res$grammar_valid)
    return(list(grammar_valid = FALSE,
                failure_reason = sprintf("rhs invalid: %s", res$failure_reason)))

  list(grammar_valid = TRUE, failure_reason = NULL)
}
```

- [ ] **Step 4: GREEN**

Expected: `PASS 31` (prior 27 + 4).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/method-evolve/validators/formula.R \
        .claude/skills/method-evolve/tests/testthat/test-validator-formula.R
git commit -m "feat(method-evolve): add formula slot validator (T9)

Reuses the feature_set walker for RHS validation; LHS is fixed by
slot.lhs config.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Fitness named-template engine — NEW

**Files:**
- Create: `.claude/skills/method-evolve/fitness/templates.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-fitness-templates.R`

**Goal:** Engine that takes `fitness.primary` (template or raw expr) + a per-variant scalar map + a baseline scalar map, and returns the primary fitness scalar. Per spec §8.1.

- [ ] **Step 1: Write the failing tests**

```r
library(testthat)
library(here)
source(here(".claude/skills/method-evolve/fitness/templates.R"))

# Fixtures
scalars <- list(my_metric = 0.4, c_index = 0.7,
                abs_bias = 0.01, coverage = 0.95)
baselines_map <- list(
  baseline_lower = list(my_metric = 0.2, c_index = 0.6),
  baseline_upper = list(my_metric = 0.8, c_index = 0.9)
)

test_that("direct_metric template returns target as-is when higher_is_better", {
  cfg <- list(template = "direct_metric", target = "my_metric",
              direction = "higher_is_better")
  expect_equal(compute_fitness(cfg, scalars, baselines_map), 0.4)
})

test_that("direct_metric template negates when lower_is_better", {
  cfg <- list(template = "direct_metric", target = "abs_bias",
              direction = "lower_is_better")
  expect_equal(compute_fitness(cfg, scalars, baselines_map), -0.01)
})

test_that("recovery_ratio = 1 when target equals upper, higher_is_better", {
  cfg <- list(template = "recovery_ratio", target = "my_metric",
              lower = "baseline_lower.my_metric",
              upper = "baseline_upper.my_metric",
              direction = "higher_is_better")
  s <- scalars; s$my_metric <- 0.8
  expect_equal(compute_fitness(cfg, s, baselines_map), 1)
})

test_that("recovery_ratio = 0 when target equals lower, higher_is_better", {
  cfg <- list(template = "recovery_ratio", target = "my_metric",
              lower = "baseline_lower.my_metric",
              upper = "baseline_upper.my_metric",
              direction = "higher_is_better")
  s <- scalars; s$my_metric <- 0.2
  expect_equal(compute_fitness(cfg, s, baselines_map), 0)
})

test_that("recovery_ratio interpolates linearly", {
  cfg <- list(template = "recovery_ratio", target = "my_metric",
              lower = "baseline_lower.my_metric",
              upper = "baseline_upper.my_metric",
              direction = "higher_is_better")
  s <- scalars; s$my_metric <- 0.5  # halfway between 0.2 and 0.8
  expect_equal(compute_fitness(cfg, s, baselines_map), 0.5)
})

test_that("recovery_ratio inverts under lower_is_better", {
  cfg <- list(template = "recovery_ratio", target = "abs_bias",
              lower = "baseline_lower.my_metric",  # use my_metric as proxy
              upper = "baseline_upper.my_metric",
              direction = "lower_is_better")
  # lower_is_better: lower=worse=larger value, upper=better=smaller value
  # but our fixture has lower=0.2, upper=0.8 — meaningless under lower_is_better
  # so use a fixture where lower>upper:
  bm <- list(baseline_lower = list(m = 0.8), baseline_upper = list(m = 0.2))
  cfg <- list(template = "recovery_ratio", target = "m",
              lower = "baseline_lower.m", upper = "baseline_upper.m",
              direction = "lower_is_better")
  s <- list(m = 0.2)
  expect_equal(compute_fitness(cfg, s, bm), 1)  # variant matches better
})

test_that("weighted_sum aggregates correctly", {
  cfg <- list(template = "weighted_sum",
              terms = list(list(metric = "my_metric", weight = 1.0),
                           list(metric = "c_index",   weight = 0.5)))
  expect_equal(compute_fitness(cfg, scalars, baselines_map),
               1.0 * 0.4 + 0.5 * 0.7)
})

test_that("raw expr uses rlang against the bindings", {
  cfg <- list(expr = "(baseline_lower.my_metric - my_metric) / (baseline_lower.my_metric - baseline_upper.my_metric)")
  s <- scalars; s$my_metric <- 0.5
  expect_equal(compute_fitness(cfg, s, baselines_map),
               (0.2 - 0.5) / (0.2 - 0.8))
})

test_that("raw expr fails on undefined identifier", {
  cfg <- list(expr = "nonexistent + my_metric")
  expect_error(compute_fitness(cfg, scalars, baselines_map),
               "object 'nonexistent' not found")
})
```

- [ ] **Step 2: RED**

- [ ] **Step 3: Implement**

```r
# fitness/templates.R
#' Compute primary fitness from per-variant scalars + named baseline scalars.
#'
#' @param fp     fitness.primary block from config (has $template + fields,
#'               OR $expr).
#' @param scalars named numeric vector or list — per-variant scalars.
#' @param baselines_map named list of named lists — baselines_map$<name>$<col>.
compute_fitness <- function(fp, scalars, baselines_map) {
  bindings <- build_bindings(scalars, baselines_map)
  if (!is.null(fp$expr)) {
    expr <- rlang::parse_expr(fp$expr)
    return(rlang::eval_tidy(expr, data = bindings))
  }
  if (is.null(fp$template))
    stop("fitness.primary missing both $template and $expr")
  switch(fp$template,
    direct_metric  = direct_metric_value(fp, bindings),
    recovery_ratio = recovery_ratio_value(fp, bindings),
    weighted_sum   = weighted_sum_value(fp, bindings),
    stop(sprintf("unknown fitness template: %s", fp$template))
  )
}

build_bindings <- function(scalars, baselines_map) {
  out <- as.list(scalars)
  for (bn in names(baselines_map)) {
    for (cn in names(baselines_map[[bn]])) {
      out[[paste0(bn, ".", cn)]] <- baselines_map[[bn]][[cn]]
    }
  }
  out
}

direct_metric_value <- function(fp, b) {
  v <- b[[fp$target]]
  if (identical(fp$direction, "lower_is_better")) -v else v
}

recovery_ratio_value <- function(fp, b) {
  tgt   <- b[[fp$target]]
  lower <- b[[fp$lower]]
  upper <- b[[fp$upper]]
  if (identical(fp$direction, "lower_is_better")) {
    (lower - tgt) / (lower - upper)
  } else {
    (tgt - lower) / (upper - lower)
  }
}

weighted_sum_value <- function(fp, b) {
  sum(vapply(fp$terms, function(t) t$weight * b[[t$metric]], numeric(1)))
}
```

- [ ] **Step 4: GREEN**

Expected: `PASS 40` (prior 31 + 9).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/method-evolve/fitness/ \
        .claude/skills/method-evolve/tests/testthat/test-fitness-templates.R
git commit -m "feat(method-evolve): add fitness named-template engine + raw expr (T10)

Implements direct_metric, recovery_ratio (both directions), weighted_sum,
and raw rlang expression evaluation against per-variant scalars + named
baseline scalars.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Generalized Program DB — MIGRATE (from v2 T5)

**Files:**
- Create: `.claude/skills/method-evolve/db.R` (paste v2 T5 step 3 code, then apply deltas below)
- Create: `.claude/skills/method-evolve/tests/testthat/test-db.R`

**Delta from v2 T5:**

1. The DB record (`make_db_record()`) gains a `slot_kind` field.
2. The `feature_set_expr` field is replaced by a polymorphic `proposal_payload` field that contains whichever payload the slot kind produced (one of: `{feature_set_expr: [...]}`, `{hyperparameters: {...}}`, `{formula_str: "..."}`).
3. The `screen` block's `ibs_ipw`/`ibs_recovery` field names become `<target_metric>` (the literal column name from config) and `primary_fitness` (the value computed by T10's engine).
4. Atomic ID allocation, parent-only writer discipline, flock guard — unchanged from v2 T5.

- [ ] **Step 1: Copy v2 T5 step 3 into `db.R`** (the `append_record`, `allocate_variant_ids`, `write_record_atomic` functions). Apply the field renames above by replacing `feature_set_expr` with `proposal_payload` and adding the `slot_kind` argument to `make_db_record()`.

- [ ] **Step 2: Write tests covering the polymorphic payload** (`test-db.R`):

```r
library(testthat)
library(here)
source(here(".claude/skills/method-evolve/db.R"))

test_that("make_db_record stores polymorphic payload by slot_kind", {
  r1 <- make_db_record(variant_id = "var_00001", generation = 0,
                       slot_kind = "feature_set",
                       proposal_payload = list(feature_set_expr = c("x1","log(x2)")),
                       parent_ids = character(), seed_block = 1L)
  expect_equal(r1$slot_kind, "feature_set")
  expect_equal(r1$proposal_payload$feature_set_expr, c("x1","log(x2)"))

  r2 <- make_db_record(variant_id = "var_00002", generation = 0,
                       slot_kind = "hyperparameters",
                       proposal_payload = list(hyperparameters = list(mtry = 5)),
                       parent_ids = character(), seed_block = 2L)
  expect_equal(r2$proposal_payload$hyperparameters$mtry, 5)
})

test_that("atomic variant_id allocation increments correctly under flock", {
  tdir <- tempfile(); dir.create(tdir)
  state_path <- file.path(tdir, "state.json")
  jsonlite::write_json(list(last_variant_id = 0L), state_path, auto_unbox = TRUE)
  ids <- allocate_variant_ids(state_path, gen_size = 5L)
  expect_equal(ids, sprintf("var_%05d", 1:5))
  ids2 <- allocate_variant_ids(state_path, gen_size = 3L)
  expect_equal(ids2, sprintf("var_%05d", 6:8))
})
```

- [ ] **Step 3: RED → GREEN.** Run; expected `PASS 42`.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(method-evolve): generalize program DB for polymorphic payload (T11)

Adds slot_kind field; replaces hardcoded feature_set_expr with
polymorphic proposal_payload (varies by slot kind). Atomic ID
allocation and parent-only writer discipline unchanged from v2 T5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Sampler — MIGRATE (from v2 T6, minimal change)

**Files:**
- Create: `.claude/skills/method-evolve/sampler.R` (paste v2 T6 code unchanged)
- Create: `.claude/skills/method-evolve/tests/testthat/test-sampler.R` (paste v2 T6 test code; no changes needed because the sampler reads `screen.primary_fitness` and `gate_pass` only — both already slot-kind-agnostic).

**Delta from v2 T6:** the sampler reads `screen$primary_fitness` instead of `screen$ibs_recovery`. That's a one-line rename.

- [ ] **Step 1: Copy v2 T6 code; apply rename.**
- [ ] **Step 2–4: Run tests** (expected `PASS 45`, +3 from sampler).
- [ ] **Step 5: Commit** with message `refactor(method-evolve): sampler reads screen.primary_fitness (T12)`.

---

## Task 13: Proposer dispatcher — MIGRATE (from v2 T7)

**Files:**
- Create: `.claude/skills/method-evolve/proposer/dispatch.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-proposer-dispatch.R`

**Delta from v2 T7:** the proposer prompt is no longer a single hardcoded block. It loads the slot-kind-specific template from `proposer/templates/<kind>.md` and substitutes runtime values. JSON parse contract is generalized: per-slot-kind expected shape (see spec §10.2).

- [ ] **Step 1: Implement `propose_batch(slot_cfg, parents, neg_examples, batch_size)` in `dispatch.R`.**

```r
# proposer/dispatch.R
SKILL_DIR <- here::here(".claude/skills/method-evolve")

load_proposer_template <- function(slot_kind) {
  path <- file.path(SKILL_DIR, "proposer/templates",
                    paste0(slot_kind, ".md"))
  if (!file.exists(path))
    stop(sprintf("proposer template not found for slot.kind=%s at %s",
                 slot_kind, path))
  paste(readLines(path), collapse = "\n")
}

# Build the system prompt by substituting fields from slot_cfg, parents,
# neg_examples into the template's {{placeholder}} markers.
render_proposer_prompt <- function(slot_cfg, parents, neg_examples, batch_size) {
  tmpl <- load_proposer_template(slot_cfg$kind)
  subs <- list(
    SLOT_KIND      = slot_cfg$kind,
    BATCH_SIZE     = as.character(batch_size),
    GRAMMAR_SPEC   = format_grammar(slot_cfg),
    PARENTS_BLOCK  = format_parents(parents, slot_cfg$kind),
    NEG_EXAMPLES   = format_neg_examples(neg_examples, slot_cfg$kind)
  )
  for (k in names(subs)) {
    tmpl <- gsub(paste0("{{", k, "}}"), subs[[k]], tmpl, fixed = TRUE)
  }
  tmpl
}

# Per-slot-kind formatters.
format_grammar <- function(slot_cfg) UseMethod("format_grammar", slot_cfg)
# (define methods .feature_set, .hyperparameters, .formula — see steps below)

# JSON parse contract: dispatch on slot_kind for shape check.
parse_proposer_response <- function(raw_text, slot_kind) {
  text <- gsub("^```(json)?|```$", "", trimws(raw_text))
  parsed <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE),
                     error = function(e) e)
  if (inherits(parsed, "error"))
    return(list(ok = FALSE, error = sprintf("parse_error: %s",
                                            conditionMessage(parsed))))
  if (!is.list(parsed) || length(parsed) == 0)
    return(list(ok = FALSE, error = "expected non-empty JSON array"))
  required_field <- switch(slot_kind,
    feature_set     = "feature_set_expr",
    hyperparameters = "hyperparameters",
    formula         = "formula_str",
    stop(sprintf("parse_proposer_response: unknown slot_kind %s", slot_kind))
  )
  for (i in seq_along(parsed)) {
    if (is.null(parsed[[i]][[required_field]]))
      return(list(ok = FALSE,
                  error = sprintf("item %d missing %s", i, required_field)))
  }
  list(ok = TRUE, proposals = parsed)
}
```

- [ ] **Step 2: Write tests** (`test-proposer-dispatch.R`). Cover: template loaded for each kind, JSON parse with code-fence stripping, JSON parse rejects wrong shape per slot kind, prompt rendering substitutes placeholders.

```r
library(testthat); library(here)
source(here(".claude/skills/method-evolve/proposer/dispatch.R"))

test_that("parse_proposer_response strips ```json fences", {
  raw <- "```json\n[{\"feature_set_expr\": [\"x1\"], \"rationale\": \"\"}]\n```"
  res <- parse_proposer_response(raw, "feature_set")
  expect_true(res$ok)
  expect_length(res$proposals, 1)
})

test_that("parse_proposer_response rejects shape mismatch", {
  raw <- '[{"hyperparameters": {"mtry": 5}}]'
  res <- parse_proposer_response(raw, "feature_set")
  expect_false(res$ok)
  expect_match(res$error, "feature_set_expr")
})

test_that("parse_proposer_response accepts hyperparameters shape", {
  raw <- '[{"hyperparameters": {"mtry": 5}, "rationale": "x"}]'
  res <- parse_proposer_response(raw, "hyperparameters")
  expect_true(res$ok)
})

test_that("parse_proposer_response accepts formula shape", {
  raw <- '[{"formula_str": "y ~ x1+x2", "rationale": "x"}]'
  res <- parse_proposer_response(raw, "formula")
  expect_true(res$ok)
})
```

- [ ] **Step 3: RED → GREEN.** Stub-create `proposer/templates/{feature_set,hyperparameters,formula}.md` with one-line placeholders so `load_proposer_template()` doesn't error. Real templates land in T14–T16.

Expected: `PASS 49` (+4).

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(method-evolve): add proposer dispatcher with per-slot-kind JSON contract (T13)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: feature_set proposer prompt template — NEW

**File:** `.claude/skills/method-evolve/proposer/templates/feature_set.md`

**Goal:** Markdown template with `{{PLACEHOLDER}}` substitution slots that the dispatcher fills. Full content extracted and generalized from v2 T7's hardcoded prompt.

- [ ] **Step 1: Write the template**

Replace the `feature_set.md` stub with:

```markdown
You are an expert statistical methodologist. Your task is to propose
{{BATCH_SIZE}} new feature-set variants for a Monte Carlo evaluation of an
R-based statistical estimator.

## Slot kind

`{{SLOT_KIND}}` — each variant is an ordered list of R model-formula terms.

## Grammar specification

{{GRAMMAR_SPEC}}

## Parent variants (top-3 by primary fitness + 1 random)

{{PARENTS_BLOCK}}

## Recently rejected proposals (negative examples — avoid these patterns)

{{NEG_EXAMPLES}}

## Task

Propose exactly {{BATCH_SIZE}} new feature_set variants. Each variant must:

1. Be a JSON array of strings (term expressions in R syntax).
2. Use only bases from the whitelist.
3. Use only transforms from the typed transform descriptors.
4. Respect the interaction arity allowed by the grammar.
5. Stay within `max_terms`.

Aim for variants that explore underused bases / transforms / interactions
relative to the parents, while addressing any gate failures shown above.

## Output contract

Output a single JSON array. No prose, no Markdown code fences, no comments.

```
[
  {"feature_set_expr": ["x1", "log(x2)", "x1*x3"], "rationale": "short text"},
  {"feature_set_expr": [...], "rationale": "..."}
]
```

If you cannot produce a valid proposal, output an empty array `[]`.
```

- [ ] **Step 2: Implement `format_grammar.feature_set()`** in `proposer/dispatch.R` so `{{GRAMMAR_SPEC}}` substitution works:

```r
format_grammar.feature_set <- function(slot_cfg) {
  paste(c(
    sprintf("- whitelist: %s", paste(slot_cfg$whitelist, collapse = ", ")),
    sprintf("- transforms: %s",
            paste(vapply(slot_cfg$transforms, function(t) t$name, character(1)),
                  collapse = ", ")),
    sprintf("- interactions: %s", slot_cfg$interactions),
    sprintf("- max_terms: %d", slot_cfg$max_terms),
    if (length(slot_cfg$forbidden_patterns))
      sprintf("- forbidden_patterns: %s",
              paste(slot_cfg$forbidden_patterns, collapse = ", "))
  ), collapse = "\n")
}
```

- [ ] **Step 3: Add a unit test** to `test-proposer-dispatch.R`:

```r
test_that("render_proposer_prompt fills feature_set template", {
  slot_cfg <- list(kind = "feature_set", whitelist = c("a","b"),
                   transforms = list(list(name = "log")),
                   interactions = "pairwise", max_terms = 5,
                   forbidden_patterns = character())
  class(slot_cfg) <- c("feature_set", "list")
  out <- render_proposer_prompt(slot_cfg, parents = list(),
                                neg_examples = list(), batch_size = 3)
  expect_match(out, "BATCH_SIZE", negate = TRUE)
  expect_match(out, "whitelist: a, b")
  expect_match(out, "feature_set_expr")
})
```

(The `class(slot_cfg) <- c("feature_set", "list")` line lets `UseMethod` dispatch to `format_grammar.feature_set`.)

- [ ] **Step 4: GREEN.** Expected `PASS 50`.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): add feature_set proposer prompt template (T14)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: hyperparameters proposer prompt template — NEW

**File:** `.claude/skills/method-evolve/proposer/templates/hyperparameters.md`

- [ ] **Step 1: Write the template** (same skeleton as T14, customized for hyperparameter sets):

```markdown
You are an expert statistical methodologist. Propose {{BATCH_SIZE}} new
hyperparameter configurations for a Monte Carlo evaluation.

## Slot kind: `{{SLOT_KIND}}`

Each variant is a JSON object mapping parameter name → value.

## Parameter schema

{{GRAMMAR_SPEC}}

For parameters with `log_scale: true`, prefer geometric spacing (e.g.,
100, 200, 500, 1000) over arithmetic spacing.

## Parent variants (top-3 by primary fitness + 1 random)

{{PARENTS_BLOCK}}

## Recently rejected proposals (avoid these)

{{NEG_EXAMPLES}}

## Task

Propose exactly {{BATCH_SIZE}} hyperparameter variants. Each variant must:

1. Set every declared parameter (no missing keys, no extra keys).
2. Respect `range` for numeric parameters (closed interval).
3. Respect `enum` for categorical parameters (exact match).
4. Aim for diversity across the parameter space; avoid clustering near a
   single parent.

## Output contract

```
[
  {"hyperparameters": {"mtry": 5, "ntree": 500, "splitrule": "gini"}, "rationale": "short"},
  {"hyperparameters": {...}, "rationale": "..."}
]
```

No prose, no fences. Output `[]` if you cannot produce a valid proposal.
```

- [ ] **Step 2: Implement `format_grammar.hyperparameters()`** in `proposer/dispatch.R`:

```r
format_grammar.hyperparameters <- function(slot_cfg) {
  paste(vapply(names(slot_cfg$params), function(k) {
    spec <- slot_cfg$params[[k]]
    sprintf("- %s: type=%s%s%s",
            k, spec$type,
            if (!is.null(spec$range))
              sprintf(", range=[%s,%s]", spec$range[1], spec$range[2]) else "",
            if (!is.null(spec$enum))
              sprintf(", enum=[%s]", paste(spec$enum, collapse = ",")) else "")
  }, character(1)), collapse = "\n")
}
```

- [ ] **Step 3: Add a unit test** following the T14 pattern.
- [ ] **Step 4: GREEN.** Expected `PASS 51`.
- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): add hyperparameters proposer prompt template (T15)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: formula proposer prompt template — NEW

**File:** `.claude/skills/method-evolve/proposer/templates/formula.md`

- [ ] **Step 1: Write the template:**

```markdown
You are an expert statistical methodologist. Propose {{BATCH_SIZE}} new
R-formula variants for a Monte Carlo evaluation.

## Slot kind: `{{SLOT_KIND}}`

Each variant is a single R formula string `lhs ~ rhs`. The LHS is fixed by
the grammar; the RHS is the part you mutate.

## Grammar specification

{{GRAMMAR_SPEC}}

## Parent variants (top-3 by primary fitness + 1 random)

{{PARENTS_BLOCK}}

## Recently rejected proposals (avoid)

{{NEG_EXAMPLES}}

## Task

Propose exactly {{BATCH_SIZE}} formulas. Each:

1. MUST start with the exact LHS shown above (e.g., `Surv(time, event) ~`).
2. RHS uses only whitelisted bases + declared transforms + permitted
   interactions, separated by `+`.
3. Stay within max_terms (count of `+`-separated RHS terms).

## Output contract

```
[
  {"formula_str": "Surv(time, event) ~ x1 + log(x2) + x1*x3", "rationale": "short"},
  {"formula_str": "...", "rationale": "..."}
]
```

No prose, no fences. Output `[]` if you cannot produce a valid proposal.
```

- [ ] **Step 2: Implement `format_grammar.formula()`** as a thin wrapper around `format_grammar.feature_set()` plus the LHS:

```r
format_grammar.formula <- function(slot_cfg) {
  paste(c(sprintf("- lhs (fixed): %s", slot_cfg$lhs),
          format_grammar.feature_set(slot_cfg)),
        collapse = "\n")
}
```

- [ ] **Step 3: Add a unit test** as in T14.
- [ ] **Step 4: GREEN.** Expected `PASS 52`.
- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): add formula proposer prompt template (T16)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 17: Generalized evaluator — MIGRATE (from v2 T8)

**Files:**
- Create: `.claude/skills/method-evolve/evaluator.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-evaluator.R`

**Delta from v2 T8:**

1. Drop the IBS-specific `compute_recovery_ratio()` body. Replace its call site with `compute_fitness(cfg$fitness$primary, scalars, baselines_map)` from T10.
2. Replace `oracle.ibs` / `cca.ibs` baseline-column lookups with the named-baselines-map lookup driven by `cfg$baselines`.
3. Tier-aware gates: read `cfg$gates`, filter by `tier ∈ {screen, full, both}` and apply per-gate `op` against the per-variant scalar. Per spec §8.2.
4. Denominator-floor + per-variant fallback semantics retained, but the fallback metric is read from `cfg$fitness$recovery$degenerate_variant_fallback$fallback_metric` and supports the `neg:` prefix syntax (T10's binding builder handles plain names; the evaluator strips `neg:` and negates).

- [ ] **Step 1: Copy v2 T8 step 3 code into `evaluator.R`; apply the four deltas.**

Key code to add for tier-aware gates:

```r
apply_gates <- function(scalars, baselines_map, cfg, tier) {
  failures <- character(0)
  bindings <- build_bindings(scalars, baselines_map)
  for (g in cfg$gates) {
    if (!(g$tier %in% c(tier, "both"))) next
    val <- bindings[[g$metric]]
    if (is.null(val)) {
      failures <- c(failures, sprintf("%s: not in scalars", g$metric)); next
    }
    pass <- switch(g$op,
      "<"  = val <  g$threshold,
      ">"  = val >  g$threshold,
      "<=" = val <= g$threshold,
      ">=" = if (!is.null(g$expr))
               val >= rlang::eval_tidy(rlang::parse_expr(g$expr), data = bindings)
             else val >= g$threshold,
      "in" = val >= g$range[1] && val <= g$range[2],
      stop(sprintf("unknown gate op: %s", g$op))
    )
    if (!pass) failures <- c(failures, sprintf("%s %s", g$metric, g$op))
  }
  list(gate_pass = length(failures) == 0, gate_failures = failures)
}
```

- [ ] **Step 2: Write tests** covering: (a) recovery falls back when denominator inverts, (b) gates correctly tier-filter, (c) `neg:` prefix on fallback metric negates the underlying scalar, (d) primary fitness pulled correctly from `compute_fitness()`.

- [ ] **Step 3: RED → GREEN.** Expected `PASS 56` (+4).

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(method-evolve): generalize evaluator with fitness engine + tier gates (T17)

Replaces hardcoded IBS-recovery logic with calls into the fitness engine
(T10) and named-baseline lookups. Tier-aware gates filter by
{screen,full,both}. Per-variant denominator fallback supports neg: prefix.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 18: Local runner — MIGRATE (from v2 T9, no functional change)

**Files:**
- Create: `.claude/skills/method-evolve/runner_local.R` (paste v2 T9 code unchanged; rename `run_screen_tier` → `run_screen_local` for clarity since T20 will introduce sibling functions for slurm/custom)
- Create: `.claude/skills/method-evolve/tests/testthat/test-runner-local.R`

- [ ] **Step 1: Copy v2 T9 step 3 code; rename function as above.** Per-child `Rscript` subprocess + `mclapply` parent-only writer + `digest`-derived seeds — all unchanged.
- [ ] **Step 2–4: Run tests.** Expected `PASS 58` (+2).
- [ ] **Step 5: Commit** with message `refactor(method-evolve): rename screen runner to run_screen_local (T18)`.

---

## Task 19: State machine — MIGRATE (from v2 T10)

**Files:**
- Create: `.claude/skills/method-evolve/state.R` (paste v2 T10 code)
- Create: `.claude/skills/method-evolve/tests/testthat/test-state.R`

**Delta from v2 T10:** bump `schema_version` from 1 to 2 to reflect the v3 config_sha schema. Resumability semantics unchanged.

- [ ] **Step 1: Copy + bump version constant.**
- [ ] **Step 2: Add a test** that loading a `schema_version: 1` state file with the new code triggers a clear "schema mismatch — start a new run folder" error.
- [ ] **Step 3–4: Run tests.** Expected `PASS 62` (+4).
- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): bump EVOLVE_STATE schema_version to 2 (T19)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 20: Compute backend dispatcher — NEW

**Files:**
- Create: `.claude/skills/method-evolve/runner_dispatch.R`
- Create: `.claude/skills/method-evolve/runner_slurm.R`
- Create: `.claude/skills/method-evolve/runner_custom.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-runner-dispatch.R`

**Goal:** Picks the right runner based on `compute.<tier>.backend`. Per spec §11.

- [ ] **Step 1: Write `runner_dispatch.R`:**

```r
source(here::here(".claude/skills/method-evolve/runner_local.R"))
source(here::here(".claude/skills/method-evolve/runner_slurm.R"))
source(here::here(".claude/skills/method-evolve/runner_custom.R"))

run_tier <- function(tier, variants, cfg, state) {
  backend <- cfg$compute[[tier]]$backend
  switch(backend,
    local  = run_screen_local(variants, cfg, state),  # for tier=screen
    slurm  = run_tier_slurm(variants, cfg, state, tier = tier),
    custom = run_tier_custom(variants, cfg, state, tier = tier),
    stop(sprintf("unknown backend: %s", backend))
  )
}
```

- [ ] **Step 2: Write `runner_slurm.R`** — generates a SLURM array submission that calls `cfg$compute[[tier]]$submit_script` once per `(variant × scenario × seed-block)`. For `tier == "screen"`, this is rare but supported. For `tier == "full"`, this is the typical path; `promote` (T24) wraps it.

```r
run_tier_slurm <- function(variants, cfg, state, tier) {
  submit_script <- cfg$compute[[tier]]$submit_script
  if (is.null(submit_script) || !file.exists(submit_script))
    stop(sprintf("compute.%s.submit_script not found: %s", tier, submit_script))
  # Build one sbatch invocation per variant; emit commands rather than running
  # them so the user can review (consistent with the no-auto-submit design).
  cmds <- lapply(variants, function(v) {
    env_str <- build_env_str(v, cfg)
    sprintf("env %s sbatch --array=0 %s", env_str, shQuote(submit_script))
  })
  message("SLURM ", tier, "-tier submission commands:")
  for (cmd in cmds) message("  ", cmd)
  list(deferred = TRUE, commands = cmds)
}

build_env_str <- function(variant, cfg) {
  kvs <- c(
    list(VARIANT_PATH = variant$path,
         VARIANT_ID   = variant$id,
         SEED_BLOCK   = variant$seed_block,
         SCENARIO_NAME = cfg$evaluator$env_vars$SCENARIO_NAME),
    cfg$evaluator$env_vars
  )
  paste(vapply(seq_along(kvs), function(i)
                sprintf("%s=%s", names(kvs)[i], shQuote(kvs[[i]])),
                character(1)),
        collapse = " ")
}
```

- [ ] **Step 3: Write `runner_custom.R`:**

```r
run_tier_custom <- function(variants, cfg, state, tier) {
  cmd_tmpl <- cfg$compute[[tier]]$submit_cmd
  if (is.null(cmd_tmpl)) stop("compute.<tier>.submit_cmd required for custom backend")
  for (v in variants) {
    cmd <- gsub("\\$\\{VARIANT_PATH\\}", v$path, cmd_tmpl)
    cmd <- gsub("\\$\\{VARIANT_ID\\}",   v$id,   cmd, fixed = FALSE)
    cmd <- gsub("\\$\\{SEED_BLOCK\\}",   v$seed_block, cmd, fixed = FALSE)
    cmd <- gsub("\\$\\{SCENARIO_NAME\\}",
                cfg$evaluator$env_vars$SCENARIO_NAME, cmd, fixed = FALSE)
    status <- system(cmd, intern = FALSE)
    if (status != 0)
      message(sprintf("custom submit_cmd returned %d for %s", status, v$id))
  }
  list(deferred = TRUE,
       message = "custom backend: results retrieval is via pull_cmd at ingest time")
}
```

- [ ] **Step 4: Write tests** (`test-runner-dispatch.R`):

```r
library(testthat); library(here)
source(here(".claude/skills/method-evolve/runner_dispatch.R"))

test_that("run_tier dispatches to local runner", {
  cfg <- list(compute = list(screen = list(backend = "local", n_workers = 1)))
  expect_silent(suppressMessages(
    # pass empty variants list; the local runner returns immediately
    run_tier("screen", variants = list(), cfg = cfg, state = list())
  ))
})

test_that("run_tier errors on unknown backend", {
  cfg <- list(compute = list(screen = list(backend = "weird")))
  expect_error(run_tier("screen", list(), cfg, list()), "unknown backend")
})

test_that("run_tier_slurm emits sbatch commands without submitting", {
  tdir <- tempfile(); dir.create(tdir)
  ss <- file.path(tdir, "submit.sh"); file.create(ss)
  cfg <- list(compute = list(full = list(backend = "slurm",
                                         submit_script = ss)),
              evaluator = list(env_vars = list(SCENARIO_NAME = "smoke")))
  variants <- list(list(id = "var_00001", path = "v1.rds", seed_block = 1L))
  res <- suppressMessages(run_tier_slurm(variants, cfg, list(), tier = "full"))
  expect_true(res$deferred)
  expect_match(res$commands[[1]], "sbatch")
})
```

- [ ] **Step 5: GREEN.** Expected `PASS 65` (+3).
- [ ] **Step 6: Commit**

```bash
git add .claude/skills/method-evolve/runner_*.R \
        .claude/skills/method-evolve/tests/testthat/test-runner-dispatch.R
git commit -m "feat(method-evolve): add compute backend dispatcher (local/slurm/custom) (T20)

slurm and custom backends emit commands rather than auto-submitting
(consistent with the no-automated-submission design).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 21: CLI wiring (extended) — MIGRATE (from v2 T11)

**Files:**
- Modify: `.claude/skills/method-evolve/cli.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-cli-extended.R`

**Delta from v2 T11:** wire in (a) all four prereq types via `prereq.R::run_prereq_check()`, (b) `runner_dispatch.R::run_tier()` for `run`, (c) slot-kind dispatcher routing through `validators/dispatch.R` and `proposer/dispatch.R`, (d) the new `--refreeze` flag on `setup`.

- [ ] **Step 1: Add subcommand handlers** for `prereq`, `setup`, `run`, `promote`, `ingest`, `report`. Each handler does the dispatcher hookup. Reuse v2 T11 step 3 code where applicable; replace the `oracle/CCA` reference assertions with calls into `validate_config()` from T6.

- [ ] **Step 2: Write tests** covering: each subcommand routes correctly; `--refreeze` requires `setup`; unknown subcommand produces a 1-line usage hint.

- [ ] **Step 3–4: GREEN.** Expected `PASS 70` (+5).

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): extend CLI with all subcommands + slot-kind dispatch (T21)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 22: SKILL.md (consolidated rewrite) — MIGRATE (from v2 T12/T14/T15)

**File:** `.claude/skills/method-evolve/SKILL.md`

**Delta from v2:** v2 had three SKILL.md tasks because the document grew incrementally. v3 consolidates into one full rewrite. Sections required:

1. Frontmatter (`name`, `description`, `auto-trigger phrases`).
2. Quick reference: 7 entry points (`scan`, `prereq`, `setup`, `run`, `promote`, `ingest`, `report`).
3. v3 design link: `quality_reports/specs/2026-04-21_method-evolve-design-v3-general.md`.
4. Slot kinds shipped: brief descriptions of `feature_set`, `hyperparameters`, `formula` with example config snippets.
5. Prereq types: brief descriptions of `source-patch`, `sidecar-meta`, `column-presence`, `custom`.
6. Fitness templates: `direct_metric`, `recovery_ratio`, `weighted_sum`, raw `expr`.
7. Compute backends: `local`, `slurm`, `custom`.
8. Reference example pointer: `examples/synthetic_cox/`.
9. Codex/Subagent fallback note (per `.claude/rules/codex-fallback-protocol.md`): proposer always uses Claude subagent with `model: "opus"`.
10. Reproducibility checklist: `here::here()`, `set.seed(YYYYMMDD)`, frozen `config_sha`, parent-only DB writer.

- [ ] **Step 1: Write the SKILL.md.**
- [ ] **Step 2: Verify the document renders cleanly** by opening in the IDE and running `Rscript .claude/skills/method-evolve/cli.R --help` (which should reference §2 of the SKILL.md).
- [ ] **Step 3: No new tests needed** (documentation file).
- [ ] **Step 4: Commit**

```bash
git commit -am "docs(method-evolve): rewrite SKILL.md for v3 general skill (T22)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 23: Scaffold generator + driver template — MIGRATE (from v2 T13)

**Files:**
- Create: `.claude/skills/method-evolve/scaffold.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-scaffold.R`

**Delta from v2 T13:** the generated driver script (`<subproject>/scripts/R/evolve_<name>_driver.R`) is parameterized by `slot.kind`. For `feature_set`, the driver writes `var_NNNNN.rds` containing `list(feature_set_expr = ...)`; for `hyperparameters`, `list(hyperparameters = ...)`; for `formula`, `list(formula_str = ...)`.

- [ ] **Step 1: Copy v2 T13 step 3 driver template; add slot-kind branching** in the `serialize_variant()` helper that the driver calls.

- [ ] **Step 2: Write tests** that call `scaffold_run(cfg)` for each slot kind and verify the generated driver script contains the right serialization branch.

- [ ] **Step 3–4: GREEN.** Expected `PASS 73` (+3).

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): generalize scaffold generator across slot kinds (T23)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 24: Promote — MIGRATE (from v2 T16)

**Files:**
- Create: `.claude/skills/method-evolve/promote.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-promote.R`

**Delta from v2 T16:** instead of hardcoding `submit_missing_types_ipw.sh`, promote reads `cfg$compute$full$submit_script` and `cfg$compute$full$promote.wrapper_script`. The wrapper-generation logic uses backend-aware path templates from `compute.full.promote.output_namespace`.

- [ ] **Step 1: Copy v2 T16 step 3 code; replace project-specific names with config lookups.**
- [ ] **Step 2: Write tests** for: manifest correctness (one entry per `variant × scenario × seed_block`), output_namespace substitution, sbatch command shape.
- [ ] **Step 3–4: GREEN.** Expected `PASS 77` (+4).
- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): generalize promote for configurable backend (T24)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 25: Ingest — MIGRATE (from v2 T17)

**Files:**
- Create: `.claude/skills/method-evolve/ingest.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-ingest.R`

**Delta from v2 T17:** the per-variant aggregation loop reads scalar columns by name from each result RDS. Column names come from `cfg$fitness` and `cfg$gates` (no hardcoded `ibs`). Uses the fitness engine (T10) to compute primary fitness for the `full` tier.

- [ ] **Step 1: Copy v2 T17 step 3; replace IBS-named lookups with name-driven lookups via T10's `compute_fitness()`.**
- [ ] **Step 2: Write tests** covering: missing remote outputs reported but don't block; idempotent re-ingest overwrites `full.*`; full-tier gate evaluation is tier-aware.
- [ ] **Step 3–4: GREEN.** Expected `PASS 80` (+3).
- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): generalize ingest using fitness engine (T25)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 26: Report — MIGRATE (from v2 T18)

**Files:**
- Create: `.claude/skills/method-evolve/report.R`
- Create: `.claude/skills/method-evolve/tests/testthat/test-report.R`

**Delta from v2 T18:** leaderboard plot generation branches on `slot.kind` — `top_feature_frequencies.pdf` for `feature_set`, `top_hyperparameter_density.pdf` for `hyperparameters`, `top_formula_term_frequencies.pdf` for `formula`. Color palette and axis conventions follow `.claude/rules/r-code-conventions.md` (Okabe-Ito, white background, 300 DPI).

- [ ] **Step 1: Copy v2 T18 step 3; add the slot-kind branch in `make_plots()`.**
- [ ] **Step 2: Write tests** that exercise each branch with a tiny in-memory DB and assert the expected PDF files are produced.
- [ ] **Step 3–4: GREEN.** Expected `PASS 84` (+4).
- [ ] **Step 5: Commit**

```bash
git commit -am "feat(method-evolve): slot-kind-aware leaderboard plots (T26)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 27: Synthetic Cox toy evaluator + baseline pre-computation — NEW

**Files:**
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/toy_evaluator.R`
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/precompute_baselines.R`
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/baselines/lower.rds`
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/baselines/upper.rds`
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/baselines/lower.meta.json`
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/baselines/upper.meta.json`

**Goal:** A self-contained ~60-line R script that simulates Cox data, fits with the proposed `feature_set_expr`, returns a results data frame with named scalars. Plus a one-shot pre-computation script for the two baselines (lower = intercept-only model; upper = oracle model with the true linear predictor).

- [ ] **Step 1: Write `toy_evaluator.R`:**

```r
# examples/synthetic_cox/toy_evaluator.R
# Tiny Cox-survival evaluator for method-evolve smoke tests.
# Reads VARIANT_FILE (RDS containing feature_set_expr) and writes a
# results.rds with columns: my_metric, c_index, abs_bias, coverage.

suppressPackageStartupMessages(library(survival))

env <- function(k, default = NULL, type = "character") {
  v <- Sys.getenv(k, unset = NA)
  if (is.na(v)) return(default)
  switch(type, integer = as.integer(v), numeric = as.numeric(v),
                        character = v)
}

set.seed(env("SEED_BLOCK", default = 1L, type = "integer") + 20260421L)
n         <- env("N_SUBJECTS", 200L, "integer")
n_sims    <- env("N_SIMS", 50L, "integer")
scenario  <- env("SCENARIO_NAME", "smoke")
variant_f <- env("VARIANT_FILE")
out_path  <- env("RESULTS_PATH",
                 sprintf("/tmp/synth_cox_%s_%s.rds",
                         scenario, env("VARIANT_ID","var")))
fexpr     <- if (!is.null(variant_f) && file.exists(variant_f))
                readRDS(variant_f)$feature_set_expr
             else c("x1","x2","x3")  # default for direct invocation

simulate_one <- function() {
  X <- matrix(rnorm(n * 6), n, 6); colnames(X) <- paste0("x", 1:6)
  lp <- 0.5*X[,1] - 0.3*X[,2] + 0.2*X[,1]*X[,3]
  T <- rexp(n, rate = exp(lp - max(lp)))
  C <- rexp(n, rate = exp(-max(lp)))
  time <- pmin(T, C); event <- as.integer(T <= C)
  data.frame(time = time, event = event, X)
}

scores <- replicate(n_sims, {
  d <- simulate_one()
  rhs <- paste(fexpr, collapse = " + ")
  fml <- as.formula(sprintf("Surv(time, event) ~ %s", rhs))
  fit <- tryCatch(coxph(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) return(c(my_metric = NA, c_index = NA,
                             abs_bias = NA, coverage = NA))
  cidx <- summary(fit)$concordance[1]
  beta <- coef(fit)
  truth <- c(x1 = 0.5, x2 = -0.3); truth_aligned <- truth[names(beta)]
  bias  <- mean(abs(beta - truth_aligned), na.rm = TRUE)
  cov_lo <- beta - 1.96 * sqrt(diag(vcov(fit)))
  cov_hi <- beta + 1.96 * sqrt(diag(vcov(fit)))
  cov_ok <- mean(truth_aligned >= cov_lo & truth_aligned <= cov_hi, na.rm = TRUE)
  c(my_metric = cidx, c_index = cidx, abs_bias = bias, coverage = cov_ok)
}, simplify = TRUE)

out <- data.frame(t(scores))
saveRDS(out, out_path)
message("Wrote ", out_path, " (", nrow(out), " rows)")
```

- [ ] **Step 2: Write `precompute_baselines.R`:**

```r
# examples/synthetic_cox/precompute_baselines.R
# Generates baselines/lower.rds and baselines/upper.rds plus their meta.json.

source(here::here(".claude/skills/method-evolve/examples/synthetic_cox/toy_evaluator.R"))

# (Already ran one batch above with default fexpr=c("x1","x2","x3"))
# Save as upper baseline (the "oracle" formula).
file.copy(out_path,
          here::here(".claude/skills/method-evolve/examples/synthetic_cox/baselines/upper.rds"),
          overwrite = TRUE)
jsonlite::write_json(list(scenario_name = scenario, n_subjects = n,
                          n_sims = n_sims, dgp_version = "synth-cox-v1",
                          evaluator_sha = "toy-001",
                          ibs_patch_version = NA,
                          created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")),
                     here::here(".claude/skills/method-evolve/examples/synthetic_cox/baselines/upper.meta.json"),
                     auto_unbox = TRUE)

# Now re-run with intercept-only-ish model (single weak feature) → lower baseline.
Sys.setenv(VARIANT_FILE = "")
fexpr <- "x1"   # tiny model — clearly worse C-index
# (Re-source not needed; just regenerate scores in-place.)
scores2 <- replicate(n_sims, {
  d <- simulate_one()
  fit <- coxph(Surv(time, event) ~ x1, data = d)
  cidx <- summary(fit)$concordance[1]
  c(my_metric = cidx, c_index = cidx, abs_bias = NA_real_, coverage = NA_real_)
}, simplify = TRUE)
saveRDS(data.frame(t(scores2)),
        here::here(".claude/skills/method-evolve/examples/synthetic_cox/baselines/lower.rds"))
jsonlite::write_json(list(scenario_name = scenario, n_subjects = n,
                          n_sims = n_sims, dgp_version = "synth-cox-v1",
                          evaluator_sha = "toy-001",
                          ibs_patch_version = NA,
                          created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")),
                     here::here(".claude/skills/method-evolve/examples/synthetic_cox/baselines/lower.meta.json"),
                     auto_unbox = TRUE)
```

- [ ] **Step 3: Run the precompute script once** to generate the baseline files:

```bash
SCENARIO_NAME=smoke N_SIMS=50 N_SUBJECTS=200 \
  Rscript .claude/skills/method-evolve/examples/synthetic_cox/precompute_baselines.R
```

- [ ] **Step 4: Commit baseline RDS + meta.json**

```bash
git add .claude/skills/method-evolve/examples/synthetic_cox/toy_evaluator.R \
        .claude/skills/method-evolve/examples/synthetic_cox/precompute_baselines.R \
        .claude/skills/method-evolve/examples/synthetic_cox/baselines/
git commit -m "feat(method-evolve): synthetic Cox toy evaluator + baselines (T27)

Self-contained ~60-line evaluator that simulates Cox data, fits a
proposed feature set, emits scalars (my_metric, c_index, abs_bias,
coverage). Two pre-computed baselines: lower (single-feature) and
upper (oracle formula).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 28: Synthetic Cox toy config + demo prereq patch — NEW

**Files:**
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/config.yaml`
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/templates/emit_extra_metric.patch`
- Create: `.claude/skills/method-evolve/examples/synthetic_cox/README.md`

- [ ] **Step 1: Write `config.yaml`** that uses every v3 feature:

```yaml
name: synthetic-cox-smoke

target_script: .claude/skills/method-evolve/examples/synthetic_cox/toy_evaluator.R

prerequisites:
  - id: emit-extra-metric
    type: source-patch
    target: .claude/skills/method-evolve/examples/synthetic_cox/toy_evaluator.R
    required_version: 1
    patch_template: .claude/skills/method-evolve/examples/synthetic_cox/templates/emit_extra_metric.patch
  - id: baseline-meta
    type: sidecar-meta
    required_for: [baseline_lower, baseline_upper]
  - id: required-columns
    type: column-presence
    smoke_env_vars: { SCENARIO_NAME: smoke, N_SIMS: 2, N_SUBJECTS: 50 }
    required_columns: [my_metric, c_index, abs_bias, coverage]

evaluator:
  env_vars: { SCENARIO_NAME: smoke, N_SIMS: 50, N_SUBJECTS: 200 }
  results_file_pattern: "/tmp/synth_cox_${SCENARIO_NAME}_${VARIANT_ID}.rds"

substitutions:
  freeze_on_setup: [run_date, name]
  per_variant: [VARIANT_PATH, VARIANT_ID, SEED_BLOCK, SCENARIO_NAME]
  refreeze_behavior: error

slot:
  kind: feature_set
  max_terms: 6
  whitelist: [x1, x2, x3, x4, x5, x6]
  transforms:
    - {name: log,    head: log,  arity: 1}
    - {name: square, head: I,    arity: 1, shape: "I(<base>^2)"}
  interactions: pairwise
  forbidden_patterns: []

baselines:
  scenario_match_required: true
  baseline_lower:
    results_file: .claude/skills/method-evolve/examples/synthetic_cox/baselines/lower.rds
    meta_file:    .claude/skills/method-evolve/examples/synthetic_cox/baselines/lower.meta.json
  baseline_upper:
    results_file: .claude/skills/method-evolve/examples/synthetic_cox/baselines/upper.rds
    meta_file:    .claude/skills/method-evolve/examples/synthetic_cox/baselines/upper.meta.json

fitness:
  primary:
    template: recovery_ratio
    target: my_metric
    lower:  baseline_lower.my_metric
    upper:  baseline_upper.my_metric
    direction: higher_is_better
  recovery:
    denom_floor_epsilon: 0.002
    degenerate_scenario_action: reject_and_halt
    degenerate_variant_fallback:
      fallback_metric: c_index
      cap: 0

gates:
  - {metric: abs_bias, tier: both,   op: "<",  threshold: 0.5}
  - {metric: coverage, tier: screen, op: in,   range: [0.85, 1.00]}
  - {metric: c_index,  tier: both,   op: ">=", threshold: 0.55}

budget: { max_variants: 20, batch_size: 4, max_generations: 3,
          promote_top_k: 3, early_stop_after: 2 }

compute:
  screen: { backend: local, n_workers: 2 }
  full:   { backend: local }

paths:
  out_dir: "quality_reports/evolve/${run_date}_synthetic-cox-smoke"
  variants_dir: "${out_dir}/variants"
  program_db: "${out_dir}/PROGRAM_DB.jsonl"
  state_file: "${out_dir}/EVOLVE_STATE.json"
```

- [ ] **Step 2: Write `templates/emit_extra_metric.patch`** — a minimal demo patch that adds a comment header `# emit-extra-metric-patch-version: 1` to `toy_evaluator.R`. This is the version-stamp marker; the patch itself doesn't need to do real work (the demo is the prereq machinery).

```diff
--- a/toy_evaluator.R
+++ b/toy_evaluator.R
@@ -1,3 +1,5 @@
 # examples/synthetic_cox/toy_evaluator.R
+# emit-extra-metric-patch-version: 1
+# (no-op patch — demonstrates prereq applicator + version stamping)
 # Tiny Cox-survival evaluator for method-evolve smoke tests.
```

- [ ] **Step 3: Write the README** (1-page walkthrough showing how to run `prereq → setup → run → promote → ingest → report` against this toy).

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(method-evolve): synthetic Cox toy config + demo prereq patch (T28)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 29: Hyperparameters toy — NEW

**Files:**
- Create: `.claude/skills/method-evolve/examples/hyperparameters_toy/config.yaml`
- Create: `.claude/skills/method-evolve/examples/hyperparameters_toy/baselines/{lower,upper}.{rds,meta.json}`
- Create: `.claude/skills/method-evolve/examples/hyperparameters_toy/README.md`

**Goal:** Reuse `synthetic_cox/toy_evaluator.R` but provide a `slot.kind = hyperparameters` config. Evaluator interprets `hyperparameters$ridge_lambda` (a numeric knob) to vary regularization. (For simplicity, the toy can just use `coxph`'s `iter.max` as the searched hyperparameter.)

- [ ] **Step 1: Extend `toy_evaluator.R` minimally** so that when `VARIANT_FILE` contains `$hyperparameters`, those keys are substituted into the model fit:

```r
# Add near the top of simulate_one() body, after readRDS:
hp <- if (!is.null(variant_f) && file.exists(variant_f))
        readRDS(variant_f)$hyperparameters
      else NULL
# Use hp$iter_max in the coxph call if present.
```

- [ ] **Step 2: Write `config.yaml`** with `slot.kind: hyperparameters`, `slot.params = {iter_max: {type: integer, range: [5, 200]}}`. Same baselines structure as T28 (use the same RDS files; only the slot config differs).

- [ ] **Step 3: Pre-compute baselines** specifically for the hyperparameter search context (lower = `iter_max = 5` → poorly-converged fit; upper = `iter_max = 200` → fully-converged fit).

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(method-evolve): hyperparameters toy example (T29)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 30: Formula toy — NEW

**Files:**
- Create: `.claude/skills/method-evolve/examples/formula_toy/config.yaml`
- Create: `.claude/skills/method-evolve/examples/formula_toy/baselines/{lower,upper}.{rds,meta.json}`
- Create: `.claude/skills/method-evolve/examples/formula_toy/README.md`

**Goal:** Reuse `toy_evaluator.R` (it already builds an R formula from `feature_set_expr`; for `formula` slot it reads `formula_str` directly). `slot.lhs = "Surv(time, event)"`.

- [ ] **Step 1: Extend `toy_evaluator.R`** to handle either `feature_set_expr` (build formula via paste) or `formula_str` (use directly).
- [ ] **Step 2: Write `config.yaml`** with `slot.kind: formula`, `slot.lhs: "Surv(time, event)"`, RHS grammar identical to T28.
- [ ] **Step 3: Pre-compute baselines** (lower = single-term RHS, upper = full oracle formula).
- [ ] **Step 4: Commit**

```bash
git commit -am "feat(method-evolve): formula toy example (T30)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 31: End-to-end smoke test against synthetic Cox toy — NEW

**Files:**
- Create: `.claude/skills/method-evolve/tests/testthat/test-smoke-synthetic-cox.R`

**Goal:** Per spec §14, the smoke test must exercise: zero-parent seed gen, grammar reject + neg-example recording, eval → DB write → checkpoint, crash-during-eval resume, `promote` dry-run, synthetic zero-gate-passer mode (via temporarily tightened gates), `ingest` of locally-produced "full" results.

- [ ] **Step 1: Write the smoke test** as a single `testthat::test_that()` block driving `cli.R` invocations against the `examples/synthetic_cox/config.yaml`:

```r
library(testthat)
library(here)

run_cli <- function(args) {
  status <- system2("Rscript",
                    c(shQuote(here(".claude/skills/method-evolve/cli.R")), args))
  status
}

test_that("end-to-end smoke against synthetic Cox toy", {
  cfg_path <- here(".claude/skills/method-evolve/examples/synthetic_cox/config.yaml")
  out_dir  <- tempfile("evolve_smoke_"); dir.create(out_dir)

  # Phase -1
  expect_equal(run_cli(c("prereq", "--config-path", cfg_path)), 0)

  # Setup
  expect_equal(run_cli(c("setup", "--config-path", cfg_path,
                         "--out-dir", out_dir)), 0)

  # Run 2 generations
  expect_equal(run_cli(c("run", "--out-dir", out_dir, "--max-gens", "2")), 0)

  # Verify DB has rows
  db <- readLines(file.path(out_dir, "PROGRAM_DB.jsonl"))
  expect_gte(length(db), 4)

  # Promote dry-run
  expect_equal(run_cli(c("promote", "--out-dir", out_dir, "--dry-run")), 0)
  expect_true(file.exists(file.path(out_dir, "promote_manifest.json")))

  # Ingest (results are local; the dispatcher ran them already in the local-backend full tier)
  expect_equal(run_cli(c("ingest", "--out-dir", out_dir)), 0)
  db2 <- readLines(file.path(out_dir, "PROGRAM_DB.jsonl"))
  expect_true(any(grepl("\"full\":\\s*\\{", db2)))  # at least one full.* patched

  # Report
  expect_equal(run_cli(c("report", "--out-dir", out_dir)), 0)
  expect_true(file.exists(file.path(out_dir, "leaderboard.md")))
})
```

- [ ] **Step 2: Run.** Expected `PASS 85` (+1, but this single test exercises many branches end-to-end so failures will be detailed).

- [ ] **Step 3: If smoke fails, iterate** by reading the failed CLI subcommand's stderr, fixing in the relevant task's file, and re-running. Do not weaken the smoke test to make it pass — fix the underlying code.

- [ ] **Step 4: Commit**

```bash
git commit -am "test(method-evolve): end-to-end smoke against synthetic Cox toy (T31)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-review notes (writer's eye)

### Spec coverage

Walking each spec section:

- **§1 Goal** — covered by overall plan goal statement and T0 (already done).
- **§2 Non-goals** — N/A (non-goals don't generate tasks).
- **§3 Architecture** — File Structure section locks in the two-layer split; T0/T11/T18/T20 implement the layers.
- **§4 Workflow entry points** — T0 (cli, scan), T1 (prereq), T21 (setup/run/promote/ingest/report wiring).
- **§5 Phase −1 prerequisites** — T1 (source-patch DONE), T3 (sidecar-meta), T4 (column-presence), T5 (custom).
- **§6.1 feature_set validator** — T7 (refactor from v2 T4).
- **§6.2 hyperparameters validator** — T8.
- **§6.3 formula validator** — T9.
- **§6.4 transform descriptors** — T7 (carried forward from v2 T4 unchanged).
- **§6.5 slot-kind contract** — implicit in T7+T8+T9 file structure (validators/<kind>.R + templates/proposer/<kind>.md + examples/<kind>_toy/).
- **§7 Config schema** — T6 (validate_config).
- **§7.1, §7.2 Substitution semantics** — covered by T6's schema validator + T19's state machine (which writes back frozen values).
- **§8.1 Fitness templates** — T10.
- **§8.2 Gates + noise budget** — T17 (apply_gates) + T6 (validator emits noise-budget warning at setup).
- **§8.3 Recovery denominator handling** — T17 (per-variant fallback) + T6 (scenario rejection on D < epsilon).
- **§9 Program DB + sampler** — T11 (DB), T12 (sampler).
- **§10 Subagent proposer** — T13 (dispatcher), T14/T15/T16 (templates).
- **§11 Runtime model** — T18 (local), T20 (slurm/custom dispatcher), T24 (promote), T25 (ingest).
- **§12 Outputs** — T23 (scaffold writes the directory tree), T26 (report).
- **§13 Project conventions** — every R-creating task follows here::here, set.seed, Okabe-Ito.
- **§14 Reference example + smoke test** — T27/T28 (synthetic_cox), T29 (hyperparameters_toy), T30 (formula_toy), T31 (smoke).
- **§15 Resumability** — T19.
- **§16 Future extensions** — N/A (v2+ items, not in scope).
- **§17 Decisions log** — recorded in spec; this plan implements decisions 1–16.

No spec section is uncovered.

### Placeholder scan

Searched for "TBD", "TODO", "implement later", "fill in", "similar to". None present in plan body. Each MIGRATE task identifies the v2 task to copy from and the specific delta to apply, rather than handwaving.

### Type consistency

- Function names used across tasks: `make_db_record`, `allocate_variant_ids`, `compute_fitness`, `validate_proposal`, `apply_gates`, `run_tier`, `parse_proposer_response`, `render_proposer_prompt`, `validate_config`, `run_prereq_check` — each is defined in exactly one task and referenced consistently elsewhere.
- DB record schema uses `proposal_payload` (defined T11) referenced in T13, T17, T25, T26 — consistent.
- Config field names (`fitness.primary.template`, `fitness.primary.expr`, `compute.<tier>.backend`, `slot.kind`, `baselines.<name>.results_file`) match across spec, T6 validator, T10 fitness engine, T17 evaluator, T20 dispatcher, T24 promote, T25 ingest.

### Task granularity

Each task ends in a single commit. Tasks T2-T5 (prereq types) are bite-sized (~5 steps each). Larger tasks (T6, T17, T20) decompose into ~5 steps each with the actual code shown. MIGRATE tasks lean on v2 plan code (referenced by task and step number) rather than re-printing it; this is acceptable because the v2 plan is preserved in the repo.

### Estimated total scope

- 21 v2 tasks → 32 v3 tasks (T0..T31).
- 2 are already DONE (T0, T1).
- ~30 commits total to land the v3 skill.
- Test count growth: from current 8 → ~85 by T31.

### Open follow-ups (not blocking; recorded for v2 of the skill, per spec §16)

1. Mixed-slot-kind runs with Normal/Leap-Path anti-stagnation (AutoSOTA-inspired).
2. Failure-signature memory across runs.
3. `model_config` and `augmentation_fn` slot kinds.
4. Optional GPT/Codex reviewer on promoted winners.
5. SSH-automated promotion via `compute.full.ssh_submit: true`.
6. Richer `column-presence` checks (per-column dtype + range).
