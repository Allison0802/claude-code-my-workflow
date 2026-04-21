---
name: method-evolve
description: 'Evolutionary variant search for statistical estimators. Reads the current sub-project, generates a project-specific config.yaml, runs a generation-chunked FunSearch-style loop: Claude Opus subagent proposes feature_set variants, grammar validator + Monte Carlo evaluator score them against hard statistical gates (bias, dual-tier coverage, C-index floor) and an integrated pseudo-Brier recovery ratio. In-session resumable mid-generation. Longleaf Full via printed rsync+ssh+sbatch. Use when the user says "evolve the feature set", "search for better covariates", "run method-evolve", or wants to explore variant designs systematically under fixed correctness gates.'
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Agent, mcp__notebooklm__notebook_query
---

# method-evolve — STUB

Implementation in progress. Plan: [`quality_reports/plans/2026-04-21_method-evolve-skill-implementation.md`](../../../quality_reports/plans/2026-04-21_method-evolve-skill-implementation.md). Spec: [`quality_reports/specs/2026-04-21_method-evolve-design-v2.md`](../../../quality_reports/specs/2026-04-21_method-evolve-design-v2.md).

## Entry points (see SKILL.md body after Task 20)

- `/method-evolve scan    <subproject>`  — Phase 0   (T16)
- `/method-evolve prereq`                — Phase -1  (T1, T2)
- `/method-evolve setup   <name>`        — Phase 1+2 (T15)
- `/method-evolve run     [max_gens: N]` — Phase 3   (T13)
- `/method-evolve promote`               — Phase 4a  (T17)
- `/method-evolve ingest`                — Phase 4b  (T18)
- `/method-evolve report`                — Phase 4c  (T19)
