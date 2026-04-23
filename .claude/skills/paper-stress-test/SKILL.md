---
name: paper-stress-test
description: Upload a paper to NotebookLM, run an automated adversarial debate between an Opus Reviewer subagent and a Sonnet Author-surrogate subagent (with concurrent novelty-check sub-call), and produce a structured briefing with cite/build-on/flag/skip recommendation. Use when the user says "stress test this paper", "adversarial read of this paper", "brief me on this paper", "help me read this paper", "is this paper's claim real", or wants deep single-paper interrogation rather than surface-level summary. Not for reviewing the user's own manuscripts (use review-paper) or multi-paper synthesis (use lit-review).
argument-hint: "<paper-path-or-arxiv-id> [--depth N] [--type T] [--cross-check NB] [--skip-novelty] [--resume <slug>]"
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Agent, mcp__notebooklm__notebook_create, mcp__notebooklm__notebook_delete, mcp__notebooklm__notebook_list, mcp__notebooklm__source_add, mcp__notebooklm__notebook_query
---

# Paper Stress-Test

Adversarial single-paper interrogation: **$ARGUMENTS**

## Overview

This skill uploads a paper to a disposable NotebookLM notebook, then runs a structured adversarial debate across nine lenses weighted by detected paper type. Each round of each lens spawns a fresh Opus Reviewer (hostile Biostatistics referee) and a fresh Sonnet Author-surrogate (defends the paper using only paper-internal evidence retrieved via NotebookLM); the Moderator holds the running transcript and writes a read-reasoning-and-decision entry after every (Reviewer, Author) exchange, which steers the next round. A concurrent sub-call to the `novelty-check` skill provides external novelty verification. The output is a structured briefing with per-lens severity, top-5 killer questions, sub-project relevance, and a cite/build-on/flag/skip recommendation.

Spec reference: `quality_reports/specs/2026-04-22_paper-stress-test-design.md`.

## Workflow

Seven phases (0–6):

| Phase | Purpose |
|-------|---------|
| 0 | Input resolution + prior-test detection + output dir setup |
| 1 | NotebookLM setup (disposable notebook + paper upload + thematic resolution) |
| 2 | Paper-type detection (one-shot Reviewer classification spawn), novelty-check sub-call, plan confirmation |
| 3 | Per-lens adversarial debate — fresh Reviewer + Author spawns per round, with Moderator read-reasoning-decision entries between rounds (Lens 7 triangulates three sources) |
| 4 | Synthesis (top-5 questions, sub-project relevance, recommendation) |
| 5 | Write briefing + transcripts + state files |
| 6 | Cleanup with optional promote-to-thematic |

## Constants

- DISPOSABLE_NOTEBOOK_NAME_PREFIX = `stress-test-`
- COMPACTION_THRESHOLD_CHARS = 80000
- NOVELTY_CHECK_TIMEOUT_SECONDS = 300
- REVIEWER_MODEL = `claude-opus-4-7`
- AUTHOR_MODEL = `claude-sonnet-4-6`
- OUTPUT_DIR = `master_supporting_docs/supporting_papers/stress_tests`

## Defer-tool preamble

Before Phase 0, the Moderator must load two deferred tools via ToolSearch:

```
ToolSearch(query="select:Agent,TodoWrite", max_results=2)
```

These are required: `Agent` spawns fresh Reviewer and Author subagents synchronously at every round of every lens (no `SendMessage` continuity is used — see §Architecture Amendment); `TodoWrite` tracks lens progress.

## Known thematic notebooks (auto-suggest table)

| Notebook name | ID | Keywords that trigger auto-suggest |
|---|---|---|
| ML for Recurrent Events | `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` | survival, recurrent event, competing risk, hazard, censoring, pseudo-observation, landmark, time-to-event, frailty, counting process |
| Interpretable AI | `fea2207b-7ec1-463c-b73f-58c0c4febb41` | interpretability, explainability, feature importance, SHAP, LIME, partial dependence, counterfactual explanation |
| Machine Learning Fundamentals | `c3aab8e1-5c4b-43ec-bafc-ae3745a7c493` | neural network, deep learning, supervised learning, regularization, cross-validation, boosting, bagging |
| Survival Analysis Fundamentals | `3faa5656-280d-4ffc-ae2d-5487075bc94e` | Cox proportional hazards, Kaplan-Meier, log-rank, Nelson-Aalen, accelerated failure time, Weibull, exponential |

## Instructions

Follow the phase-by-phase instructions below. Phases 2 through 6 depend on state persisted after each lens, so Phase 3 must be resumable from `state.json`.

<!-- Phase 0 instructions added in Task 2 -->
<!-- Phase 1 instructions added in Task 3 -->
<!-- Phase 2 instructions added in Tasks 4, 5, 6 -->
<!-- Phase 3 instructions added in Tasks 7, 8, 9, 10, 11 -->
<!-- Phase 4 instructions added in Task 12 -->
<!-- Phase 5 instructions added in Task 13 -->
<!-- Phase 6 instructions added in Task 14 -->
<!-- Error handling + resumability added in Task 18 -->
