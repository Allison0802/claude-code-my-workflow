---
name: paper-stress-test
description: Upload a paper to NotebookLM, run an automated adversarial debate between an Opus Reviewer subagent and a Sonnet Author-surrogate subagent (with concurrent novelty-check sub-call), and produce a structured briefing with cite/build-on/flag/skip recommendation. Use when the user says "stress test this paper", "adversarial read of this paper", "brief me on this paper", "help me read this paper", "is this paper's claim real", or wants deep single-paper interrogation rather than surface-level summary. Not for reviewing the user's own manuscripts (use review-paper) or multi-paper synthesis (use lit-review).
argument-hint: "<paper-path-or-arxiv-id> [--depth N] [--type T] [--cross-check NB] [--skip-novelty] [--no-checkpoint] [--resume <slug>]"
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Agent, mcp__notebooklm__notebook_create, mcp__notebooklm__notebook_delete, mcp__notebooklm__notebook_list, mcp__notebooklm__source_add, mcp__notebooklm__notebook_query
---

# Paper Stress-Test (v2 — refactored 2026-04-23)

Adversarial single-paper interrogation: **$ARGUMENTS**

**This file is the orchestration skeleton.** Phase-level detail lives in `runbooks/phase-*.md`. Parsing patterns live in `parsing/transcript-patterns.md`. Canonical turn shape lives in `schema/state.schema.json` and `templates/transcript-slice.json`. Read this file for the what, load each runbook for the how.

---

## Arguments

**Positional (required):** `<paper-path-or-arxiv-id>` — absolute path, relative path, bare filename in `master_supporting_docs/supporting_papers/`, arXiv ID, or URL. Resolution rules in `runbooks/phase-0-input.md`.

**Optional flags:**

| Flag | Default | Effect |
|------|---------|--------|
| `--depth N` | `2` | Aggressiveness. Maps per-lens rounds via the weight matrix: `heavy→N`, `medium→max(1, N-1)`, `light→1`, `skip→0`. |
| `--type T` | auto-detected | Override Reviewer's classification. One of: `predictive-ML`, `new-estimator`, `applied-empirical`, `causal-inference`, `review-survey`. Re-shapes the lens plan. |
| `--cross-check NB` | auto-suggest | Pin the thematic cross-check notebook used by Lens 7. See "Known thematic notebooks" table below. |
| `--skip-novelty` | `false` | Skip the concurrent `novelty-check` sub-call. |
| `--no-checkpoint` | `false` | Auto-proceed past the Phase 2 plan confirmation (unattended runs). |
| `--resume <slug>` | — | Resume an aborted/interrupted run from its saved state.json. |

Parsed flag values persist under `state.invocation`. Runtime constants (below) are file-edit only.

---

## Five invariants (the skill's spine)

All runbooks enforce these. Validator gates catch violations. Never work around.

- **I-1 (no proxy).** Every Author turn is produced by a Sonnet Author-surrogate subagent. A failed spawn → lens marked `severity: "skipped"`, never proxied. Gate G-3d.
- **I-2 (one schema).** Every `turn_record` conforms to `schema/state.schema.json#/definitions/turn_record`. No legacy `turn`, `close_lens_mode`, `action`, or `novelty_seed` keys. Gate G-3c.
- **I-3 (assessments complete).** For each lens, `moderator_assessments` has one entry per round the moderator spoke, content non-empty. Gate G-3e.
- **I-4 (disposition resolved).** At end of run, `notebooks.disposable.disposition ∈ {deleted, kept, promoted}` — never `pending`. Gate G-3f.
- **I-5 (role-notebook isolation).** Reviewer has paper + thematic notebook (thematic only for Lens 7). Author has paper + disposable notebook only — never thematic. Moderator has neither. Gate G-3d-bis.

---

## Workflow

Seven phases. SKILL.md dispatches; runbooks execute.

| Phase | What it does | Runbook |
|-------|--------------|---------|
| 0 | Input resolution, slug generation, prior-test + resume detection | `runbooks/phase-0-input.md` |
| 1 | NotebookLM setup (disposable notebook + paper upload + thematic resolution); state.json init | `runbooks/phase-1-notebooklm.md` |
| 2 | One-shot Reviewer classification; fire background novelty-check; build + confirm lens plan | `runbooks/phase-2-classify-plan.md` |
| 3 | Flat sequential lens loop — Moderator dispatches Reviewer + Author directly per lens/round | `runbooks/phase-3-debate.md` |
| 3 (Lens 7) | Positioning lens — Reviewer owns the thematic notebook query | `runbooks/phase-3-lens7.md` |
| 3 (aux) | Transcript compaction + Moderator own-context budget | `runbooks/phase-3-compaction.md` |
| 4 | Synthesis (top-5 killer questions, sub-project relevance, recommendation) | `runbooks/phase-4-synthesis.md` |
| 5 | Write briefing + transcripts + finalize state | `runbooks/phase-5-artifacts.md` |
| 6 | Cleanup + optional promote-to-thematic + final disposition | `runbooks/phase-6-cleanup.md` |

**Architectural note (2026-04-24 flat-dispatch refactor):** all Reviewer and Author subagents are spawned from the top-level Moderator (this skill's execution context). **Nested subagents are impossible in Claude Code** — a subagent spawned via `Agent` cannot itself call `Agent`; the tool is stripped at runtime regardless of `tools:` frontmatter. The Apr-23 parallel 3×3 group-moderator architecture was retired on this basis. See `runbooks/phase-3-debate.md` §Architecture for the full justification.

**Hollow-run protection.** Phase 3 enforces gates G-3a..G-3-mod-content after every lens closes; Phase 6 enforces G-5a at finalization. A gate failure → partial-mode briefing + abort. See `scripts/validate_state.py` for mechanical details.

**Anti-rationalization table** (read this before starting Phase 3): see `runbooks/phase-3-debate.md` §Anti-rationalization. Hollow-run patterns are spec violations, not alternative paths.

---

## Constants

```
DISPOSABLE_NOTEBOOK_NAME_PREFIX   = "stress-test-"
COMPACTION_THRESHOLD_TOKENS       = 6000
DIGEST_MAX_CHARS                  = 2000
NOVELTY_CHECK_TIMEOUT_SECONDS     = 300
MODERATOR_CONTEXT_SOFT_LIMIT_CHARS  = 180_000
MODERATOR_CONTEXT_ABORT_LIMIT_CHARS = 220_000
REVIEWER_MODEL                    = "opus"    # full model-string suffix resolved at spawn time
AUTHOR_MODEL                      = "sonnet"
OUTPUT_DIR                        = "master_supporting_docs/supporting_papers/stress_tests"
SPAWN_BUDGET_DEFAULT              = 80
WALL_CLOCK_BUDGET_DEFAULT_S       = 1800
```

---

## Defer-tool preamble

Before Phase 0, load deferred tools via ToolSearch:

```
ToolSearch(query="select:Agent,TodoWrite", max_results=2)
```

`Agent` spawns Reviewer/Author/group-moderator subagents. `TodoWrite` tracks per-phase progress.

---

## Known thematic notebooks (auto-suggest table)

| Notebook name | ID | Keywords |
|---|---|---|
| ML for Recurrent Events | `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` | survival, recurrent event, competing risk, hazard, censoring, pseudo-observation, landmark, time-to-event, frailty, counting process |
| Interpretable AI | `fea2207b-7ec1-463c-b73f-58c0c4febb41` | interpretability, explainability, feature importance, SHAP, LIME, partial dependence, counterfactual explanation |
| Machine Learning Fundamentals | `c3aab8e1-5c4b-43ec-bafc-ae3745a7c493` | neural network, deep learning, supervised learning, regularization, cross-validation, boosting, bagging |
| Survival Analysis Fundamentals | `3faa5656-280d-4ffc-ae2d-5487075bc94e` | Cox proportional hazards, Kaplan-Meier, log-rank, Nelson-Aalen, accelerated failure time, Weibull, exponential |

---

## Nine lenses

Hard-coded list. Weights per paper-type live in `runbooks/phase-2-classify-plan.md` §2.9.

| # | name | description |
|---|------|-------------|
| 0 | data | Data structure & characteristics |
| 1 | estimand | Estimand clarity |
| 2 | identification | Identification assumptions |
| 3 | methodology | Statistical methodology |
| 4 | overclaims | Overclaims vs. evidence |
| 5 | alternatives | Alternative explanations |
| 6 | generalizability | Generalizability |
| 7 | positioning | Positioning vs. prior work (triangulation) — **Lens 7 uses a special runbook** |
| 8 | reproducibility | Reproducibility |

---

## Entry sequence

On invocation:

1. **Load deferred tools** (Defer-tool preamble above).
2. **Parse `$ARGUMENTS`** per the Arguments table.
3. **Load `runbooks/phase-0-input.md`** and execute.
4. **Load `runbooks/phase-1-notebooklm.md`** and execute.
5. **Load `runbooks/phase-2-classify-plan.md`** and execute.
6. **Load `runbooks/phase-3-debate.md`** and execute the flat lens loop. When the loop reaches lens 7, also load `runbooks/phase-3-lens7.md` for that lens only. Compaction thresholds from `runbooks/phase-3-compaction.md` apply throughout. After each lens closes, aggregate gates run via `scripts/validate_state.py`; failure → abort to partial briefing.
7. **Load `runbooks/phase-4-synthesis.md`** and execute.
8. **Load `runbooks/phase-5-artifacts.md`** and execute.
9. **Load `runbooks/phase-6-cleanup.md`** and execute. Gate G-5a checked here — last chance to catch `disposition: pending`.

Each runbook file states its own preconditions (what state.json fields it expects) and postconditions (what it must set). Load the runbook into context only when its phase starts; do not keep earlier runbooks resident.

---

## Error handling

| Error class | Response |
|-------------|----------|
| Tool call error (MCP, Agent) | Retry once after 5s. Second failure → phase-specific recovery in the runbook. |
| Parse failure on subagent output | Run Reparse protocol once (`parsing/transcript-patterns.md` §Reparse). Second failure → phase-specific recovery. |
| Gate failure (G-3a..G-3e) | `abort_run(reason, detail)` → write partial-mode briefing via Phase 5, run Phase 6 cleanup, persist state, exit. |
| Wall-clock / spawn budget exhausted | `abort_run("wall_clock_budget_exhausted" \| "spawn_budget_exhausted")`; same recovery as above. |
| Moderator context overflow | `abort_run("moderator_context_overflow")`; same recovery. |

All `abort_run` paths go through phase-5 (partial briefing) AND phase-6 (cleanup). Invariant I-4 (disposition resolved) is enforced even on abort.

---

## Resumability

Resume flow is triggered when `--resume <slug>` is passed OR when `${OUT_ROOT}/state/${FULL_SLUG}_state.json` exists at Phase 0.

On resume:

- Load the existing state.json. `wall_clock_start` is NOT reset.
- Skip Phases 0.5 through 2 (input, NotebookLM setup, plan). Reuse persisted notebook IDs, lens plan, novelty-check status.
- Jump to Phase 3. At Step 3.4 (dispatch), glob `${OUT_ROOT}/state/${FULL_SLUG}_group_*.json` — for each existing partial where `aborted==false` AND `len(lens_records)==len(lens_ids_assigned)`, skip that group. Dispatch only the missing groups in a single assistant turn.
- Proceed through Phases 4–6 normally.

Resume must be idempotent: running `--resume` on a completed state.json prints "already completed" and exits without mutating anything.

---

## Self-check (post-hoc validator)

After any completed run (manual or automated), the validator can be re-run:

```bash
python3 scripts/validate_state.py ${OUT_ROOT}/state/${FULL_SLUG}_state.json
python3 scripts/enforce_schema.py ${OUT_ROOT}/state/${FULL_SLUG}_state.json
```

The first checks the content invariants (G-3a..G-3f). The second runs strict JSON Schema validation against `schema/state.schema.json`. A healthy state.json passes both with zero output.

---

## What moved where (refactor note, 2026-04-23)

v1 SKILL.md was 2,012 lines. v2 is ~300 lines because the following content moved:

| Moved content | Now lives at |
|---|---|
| Parsing contract (regex patterns + reparse) | `parsing/transcript-patterns.md` |
| Phase 0 (input resolution) | `runbooks/phase-0-input.md` |
| Phase 1 (NotebookLM) | `runbooks/phase-1-notebooklm.md` |
| Phase 2 (classification + plan) | `runbooks/phase-2-classify-plan.md` |
| Phase 3 flat lens loop, anti-rationalization, per-lens debate function, budget gates | `runbooks/phase-3-debate.md` |
| Phase 3 Lens 7 triangulation (Reviewer owns thematic) | `runbooks/phase-3-lens7.md` |
| Phase 3 compaction + own-context budget | `runbooks/phase-3-compaction.md` |
| ~~Phase 3 merge + partial state files~~ (deleted 2026-04-24 — flat dispatch has no partials to merge) | — |
| ~~agents/group_moderator.md~~ (deleted 2026-04-24 — nested subagents impossible in Claude Code) | — |
| Phase 4 synthesis | `runbooks/phase-4-synthesis.md` |
| Phase 5 artifacts | `runbooks/phase-5-artifacts.md` |
| Phase 6 cleanup | `runbooks/phase-6-cleanup.md` |
| Canonical turn shape | `schema/state.schema.json` + `templates/transcript-slice.json` |

**Behavior-changing delta** (not a pure split):

- Lens 7 no longer uses `moderator_notebook_proxy` as an Author. Reviewer performs thematic query directly; Author only sees the paper. If either subagent spawn fails, the lens is marked `skipped`, never proxied.
- Canonical turn_record enforced: keys `turn`, `action`, `close_lens_mode`, `novelty_seed`, `notebook_id`, `query`, `result_summary` are rejected at the record level. Findings from notebook queries go inside the `content` field of a normal role turn.
- `schema_version` bumped from `"1"` to `"2"`. Old state files are grandfathered by the audit script.

Rationale and full motivation: `quality_reports/plans/2026-04-23_paper-stress-test-skill-refactor.md`.
