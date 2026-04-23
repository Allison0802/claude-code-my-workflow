# 2026-04-23 — paper-stress-test: close hollow-run loopholes

**Branch:** `fix/paper-stress-test-hollow-run-gates` (branched from `main`)
**Plan:** `~/.claude/plans/yes-writing-skills-rustling-lobster.md`
**Approved:** user, 14:40 EDT

## Goal

Post-hoc fix: the Lin 2021 stress-test run produced a **hollow run** (9 lenses marked complete, `state.transcript=[]`, `spawn_count=0`, invalid `recommendation="build-on-with-flags"`, `disposition="pending"` on completed run). The skill already specified correct behavior in prose; Moderator still bypassed it. This is REFACTOR-phase writing-skills work — convert prose obligations into boolean gates that make the bypasses impossible.

## Changes applied

### `.claude/skills/paper-stress-test/SKILL.md` (1795 → 1888 lines, +93)

| Edit | Location | What |
|---|---|---|
| 1 | after Overview (line ~17) | ⚠ Hollow-run red-flags callout (top-of-document, 7 invariants) |
| 2 | Phase 3 intro (line ~720) | Anti-rationalization table (4 rationalizations Lin run used) |
| 3 | Step 3.4 pseudocode + new Step 3.4.5 | GATE G-3a: pre-lens hollow-run invariants |
| 4 | Step 3.8 step 3 + new step 6 | ⚠ MANDATORY FIELDS callout + GATE G-3b per-lens validation |
| 5 | end of Phase 3 (line ~1418) | GATE G-3c: end-of-Phase-3 integrity (4 invariants) |
| 6 | Step 4.4 (before synthesis write) | GATE G-4a: enum + `verdict` field + required synthesis keys |
| 7 | end of Phase 5 (line ~1608) | GATE G-5a: no-early-return gate to Phase 6 |
| 8 | Step 3.8.5 before spawn_agent | **MANDATE** callout — `spawn_agent` is only sanctioned Agent path |
| 9 | global | Renamed `{{TLDR_VERDICT}}` → `{{VERDICT}}` in SKILL.md + `templates/briefing.md` |
| 10 | after error-handling table | New "Self-check (post-hoc validator)" section + `scripts/validate_state.py` |
| 11 | after Workflow table (line ~30) | `T<N>` convention note (co-refer to phase.step) |

### New file `.claude/skills/paper-stress-test/scripts/validate_state.py` (≈220 lines)

Python stdlib only. Loads `<slug>_state.json`; evaluates G-3a/G-3b/G-3c/G-4a/G-5a. Exits 0 on clean, 1 on violations (one line per violation), 2 on I/O/JSON error.

### `.claude/skills/paper-stress-test/templates/briefing.md`

Rename `{{TLDR_VERDICT}}` → `{{VERDICT}}` (Edit 9, schema consistency).

## Regression tests

| Fixture | Expected | Result |
|---|---|---|
| `lin_2021_..._state.json` (hollow run) | exit 1, all gates fire | **exit 1, 120 violations** across G-3a (37), G-3b (72), G-3c (2), G-4a (6), G-5a (2) ✓ |
| `loe_2025_..._state.json` (partial hollow) | exit 1, ≥G-3a + G-4a fire | **exit 1, 8 violations** — 3 lenses with empty slices (partial hollow), `recommendation='BUILD-ON'` uppercase bug, missing `verdict`/`top_killer_questions` ✓ |
| Synthetic well-formed state | exit 0, "OK" | **exit 0, OK** ✓ |
| Sabotage (blank `author_best_defense`) | exit 1, G-3a fires | **exit 1, 1 violation** — G-3a catches it ✓ (proves validator not tautological) |

## Issues surfaced, not fixed here

- **Loe 2025 `recommendation='BUILD-ON'`** (uppercase) — caught by G-4a. Separate data-cleanup task to normalize.
- **Leaked Lin 2021 disposable NotebookLM notebook** (`disposition='pending'`) — post-fix operational task: `mcp__notebooklm__notebook_list` → locate `stress-test-lin-2021-*` → `notebook_delete` → update state.json. Flagged in plan, not done in this session.

## Working-tree state at session start

Stashed `stash@{0}: On main: WIP: method-evolve + novelty-check deviation note (2026-04-23 paper-stress-test detour)` — covers `.claude/skills/novelty-check/SKILL.md`, `quality_reports/session_logs/2026-04-21_method-evolve-execution.md`, plus submodule pointers for `Missing Types/` and `comparisons/`. Restore on return to `feat/method-evolve-skill`.

## Time log

- 14:22 session start — user bug report on Lin 2021 hollow run
- 14:30 brainstorming done, parallel Explore agents dispatched
- 14:38 plan drafted via Plan agent, final plan written to `~/.claude/plans/yes-writing-skills-rustling-lobster.md`
- 14:40 user approved plan with "a" (option A — branch from main)
- 14:45 branched to `fix/paper-stress-test-hollow-run-gates`
- 14:45–14:55 applied Edits 1–11 sequentially to SKILL.md + briefing.md
- 14:55 wrote `scripts/validate_state.py`
- 14:55–14:58 regression-tested (Lin, Loe, synthetic, sabotage); all 4 tests pass
- 14:58 session log

## Files modified

| File | Change |
|---|---|
| `.claude/skills/paper-stress-test/SKILL.md` | +93 lines (11 edits) |
| `.claude/skills/paper-stress-test/templates/briefing.md` | 1 placeholder rename |
| `.claude/skills/paper-stress-test/scripts/validate_state.py` | NEW (220 lines, stdlib-only) |
| `quality_reports/session_logs/2026-04-23_paper-stress-test-hollow-run-gates.md` | NEW (this file) |

## Current test status

- validate_state.py exits 1 on both known-failing fixtures (Lin, Loe) with gate-level specificity ✓
- validate_state.py exits 0 on synthetic well-formed state ✓
- validate_state.py exits 1 when a required field is blanked (sabotage) ✓
- No end-to-end run yet — requires a fresh `/paper-stress-test` invocation on a small paper (user-selected) to confirm gates don't false-positive on a healthy run.
