# Session Log: log_time in imputation models + per-run predictions

**Date:** 2026-04-21
**Scope:** Missing Types sub-project
**Plan:** `Missing Types/quality_reports/plans/2026-04-21_logtime-models-and-predictions.md`

## Goal

Extend RPM/RPM-RF/DR/DR-RF to include `log_time` (matching the morning MAR-T
DGP fix), and persist per-run predictions + per-seed summaries for downstream
interpretability work on median seeds.

## Approach

- **Track 1:** Inject `log_time` into five sites in `functions.R`
  (`prepare_rpm_data`, two `fit_*` fns, two `predict_*` fns) + DR round-trip
  regression test.
- **Track 2:** `SAVE_PREDICTIONS` env-var plumbing in `simulation_engine.R`,
  prediction collector in `simulation_runner.R`, per-seed summary writer,
  scenario manifest with git commit + sessionInfo.
- **Out of scope:** survival prediction models; persistence of full model
  objects in the primary batch (rerun-only via `SAVE_FULL_MODELS=true`).

## Changes

### Earlier commits (Tasks 1–9, pre-afternoon)

- `1664363` — test(mar): DR round-trip regression covering log_time (Task 6)
- `9d70a86` — fix(test): align DR round-trip assertion with clipping-without-renorm
- `010e1e2` — refactor(functions): hoist log-time floor to LOG_TIME_FLOOR constant (Tasks 1–5 consolidated)
- `35177cd` — feat(engine): SAVE_PREDICTIONS / SAVE_FULL_MODELS env-var plumbing (Task 7)
- `53ae8db` — feat(runner): per-run prediction collector (Task 8)
- `ff971c3` — feat(runner): per-seed model summary + optional full-model save (Task 9)

### Afternoon commits (Tasks 10–13, this pass)

- `d144871` — fix(engine): capture git HEAD via setwd when project path has spaces
  (bonus bugfix discovered at Task 10.5; see Blocker below)
- `03ce0d0` — docs(claude): document log_time RPM/DR extension and SAVE_PREDICTIONS (Task 11)
- `ce38325` — feat(slurm): enable SAVE_PREDICTIONS on all 7 method submit scripts (Task 12)

## Verification

- **Task 10.1 (IPW smoke):** TEST_RUN=true, N_SIMS=2, SAVE_PREDICTIONS=true.
  Wrote 2× prediction RDS + 2× summary RDS + 1 manifest. ✅
- **Task 10.2 (RPM smoke):** same. ✅
- **Task 10.3 (DR smoke):** same. ✅
- **Task 10.4 (schema verification on DR seed0001):** 10,918 rows × 14 cols.
  All required columns present (`seed`, `imputation_method`, `prediction_model`,
  `pid`, `checkin`, `type`, `split`, `pseudo_true`, `pseudo_pred`,
  `event_type_observed`, `X`, `Z`, `XX2`, `logT`). All 7 `prediction_model`
  values present (rf_stratified, rf_time, cox_history, merfranger_stratified,
  merfranger_typecov, grf_stratified, grf_typecov). No NAs in `pseudo_true`,
  `X`, `Z`, `XX2`, or `logT`. ✅
- **Task 10.5 (manifest verification):** initially FAILED — `git_commit` was
  `NA` because `system2("git", "-C", <space-containing-path>, ...)` returned
  `character(0)` and `[1]` indexed to `NA` silently (stderr suppressed).
  Patched via `d144871`, re-ran DR smoke, re-verified: `git_commit =
  c03b50c0e1977b2c72bc9f537a7de9b14535a58c`, session_info populated. ✅

## Blocker (resolved)

**Manifest `git_commit` returned `NA`** on paths containing spaces (OneDrive).
Root cause: `system2(..., stderr = FALSE)` does not throw on non-zero exit —
`character(0)[1]` silently yielded `NA` past the `tryCatch(error = ...)`
guard. Fixed in `simulation_engine.R:304-314` by switching to
`setwd(here::here())` + `on.exit(setwd(old_wd), add = TRUE)` plus explicit
length/nzchar validation. Falls back to `"unknown"` rather than `NA` if the
command still fails. Cluster runs on Longleaf (path without spaces) were not
affected, but local smoke tests and any OneDrive-synced checkout were.

## Next

- User green light for cluster sbatch across all 7 methods.
- Post-completion: run `analyze_missing_types_results.R` to identify median
  seeds per (scenario × method) for targeted `SAVE_FULL_MODELS=true SEED=<N>`
  re-runs feeding PDP/ALE/SHAP interpretability analyses.

## Quality score (self-assessment)

- **Simplicity:** 8 — ~150 lines of code total across 3 files; surrounding
  cluster-style `${VAR:-default}` pattern used for `SAVE_PREDICTIONS`.
- **Correctness:** 9 — test_mar_with_time.R covers all five edit sites + DR
  round-trip; smoke tests pass end-to-end for IPW/RPM/DR; schema and manifest
  verify green.
- **Traceability:** 9 — plan on disk, session log, per-task commits, regression
  tests, schema verification, manifest captures git SHA + sessionInfo per
  scenario.

## Files touched (afternoon pass)

- `Missing Types/simulation_engine.R` — git_commit capture hardening
- `Missing Types/CLAUDE.md` — env vars + critical-details (RPM/DR base_vars,
  predictions persistence, targeted re-run)
- `Missing Types/submit_missing_types_{cca,ipw,ipw_rf,rpm,rpm_rf,dr,dr_rf}.sh`
  — 7× `export SAVE_PREDICTIONS="${SAVE_PREDICTIONS:-true}"` after
  `SAVE_INTERVAL` line

## Cluster launch

- [~14:35] User uploaded scripts to Longleaf and submitted all 7 methods
  manually via `sbatch submit_missing_types_<method>.sh`. Task 14 complete.
- Wall-time budget per method: `--time=240:00:00`, 8-job array, 64 CPUs,
  200 GB RAM. Expect full completion in roughly 4–5 days worst-case.

## Next (when jobs finish)

1. `analyze_missing_types_results.R` → aggregate cindex tables + figures.
2. Identify median seed per (scenario × method) from the new predictions
   dataframes.
3. Targeted re-run with `SAVE_FULL_MODELS=true SEED=<median>` to pickle
   fitted model objects for PDP/ALE/SHAP interpretability work.

---

## 2026-04-24 — Cluster run 44879214 postmortem + OOM fix

## What happened

User checked progress ~60h after submission. Actual state was much worse
than "some scenarios finished":

| Array | Scenario | Final | Elapsed | Seeds | Notes |
|---|---|---|---|---|---|
| _0 | MCAR_10pct | **OOM** | 31h | 46/500 | MaxRSS 209 GB / 200 GB limit |
| _1 | MCAR_20pct | **OOM** | 38h | 46/500 | same |
| _2 | MCAR_30pct | CANCELLED | 45h | 3/500 | stuck, workers dying off |
| _3 | MCAR_50pct | **OOM** | 35h | 55/500 | same |
| _4 | MAR_10pct | CANCELLED | 31h | 3/500 | stuck |
| _5 | MAR_20pct | CANCELLED | 30h | 1/500 | stuck |
| _6, _7 | MAR_30/50pct | CANCELLED | — | — | never ran |

All three OOM tasks terminated at MaxRSS ≈ 209 GB within chunk 1/8.
No chunk checkpoint (temp_*/) ever saved. Other 6 methods
(44879215–44879220) were cancelled from queue before starting.
~12,400 CPU-hours of wasted compute. 196 partial prediction RDS + 196
summaries + 6 manifests survive on `/work/users/y/u/yumeiy/missing types/`.

## Root-cause analysis

Applied `/systematic-debugging` skill.

**Not a rep-to-rep leak.** Each PSOCK worker does exactly ONE rep per
chunk (chunk_size=64 × 1 rep each = 64 seeds per chunk). Cluster is
destroyed + recreated between chunks (`stopCluster(cl); rm(cl);
aggressive_gc()` at [simulation_engine.R:427]). No seed-to-seed
accumulation path exists.

**Not a parent leak.** `[MEMORY PRE-SIMULATION] 0.03 GB`, result list
contains only scalars.

**Actual cause: memory oversubscription.** Each worker, fitting all 7
prediction models at n=500, holds simultaneously:
- landmark-expanded transformed_data (O(n²) rows)
- RF ×2, Cox ×1, MERFranger ×3, GRF ×3 — forest objects stay referenced
  until `run_comprehensive_simulation` returns (no intra-fn `rm()`s)
- pred_entries + pred_long from SAVE_PREDICTIONS (~10-20 MB)

Rough per-worker peak: 3-4 GB. × 64 workers = **192-256 GB aggregate**,
right at/over the 200 GB cgroup limit. SAVE_PREDICTIONS (Tasks 7-9)
added ~20-40 MB per worker — small but enough to tip an already-edge
simulation over. Stuck tasks _2/_4/_5 didn't fully OOM-terminate; cgroup
killed individual workers and survivors crawled forward at 1-3
seeds/30-45h.

## Fix (commit b05093e)

Halved both parameters across all 7 submit scripts:
- `#SBATCH --cpus-per-task=64` → `32`
- `export CHUNK_SIZE="${CHUNK_SIZE:-64}"` → `${CHUNK_SIZE:-32}`

Keeps `CHUNK_SIZE == --cpus-per-task` (CLAUDE.md rule). Expected
aggregate peak: ~100-130 GB (70+ GB headroom). Wall time per scenario
~105h → ~210h (inside 240h limit).

Also applied bonus fix `d144871` from earlier today to
`simulation_engine.R` — git_commit capture via setwd() rather than
`system2("git", "-C", <path-with-space>)`. This was a prerequisite to
the stricter Task 10.5 manifest checks and was needed anyway for the
cluster where the workdir is `/work/users/y/u/yumeiy/missing types/`.

## Verification plan

Test job: `sbatch --array=6 submit_missing_types_cca.sh` → job
**45542874_6** (`missing_MAR_30pct_complete_case`, zero prior output,
clean signal).

Success criteria:
- No `oom_kill` events in SLURM stderr
- First chunk (32 seeds) completes in ~13-15h
- `sacct MaxRSS` stays under ~140 GB
- 32 prediction RDS written to `results_missing_types/predictions/`

If test passes → rsync + resubmit remaining 7 CCA scenarios + other 6
methods. If test fails → hypothesis H1 is wrong, hunt for real leak
(surgical `rm()` + `gc()` calls inside `run_comprehensive_simulation`).

## Files touched this pass

- `Missing Types/submit_missing_types_*.sh` (×7) — chunk size 64 → 32
- Rsync to `/work/users/y/u/yumeiy/missing types/` on Longleaf
