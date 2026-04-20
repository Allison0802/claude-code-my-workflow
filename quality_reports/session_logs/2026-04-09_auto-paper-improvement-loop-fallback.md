# Session Log: Codex MCP Fallback & NotebookLM Consultation (All Skills)

**Date:** 2026-04-09
**Goal:** Add Claude subagent fallback when Codex MCP is unavailable + NotebookLM consultation during fix implementation, across all 24 Codex-using skills

## Changes Made

### File Modified
- `.claude/skills/auto-paper-improvement-loop/SKILL.md`

### What Changed and Why

1. **Frontmatter**: Updated `description` and `allowed-tools` to reflect new capabilities (added `mcp__notebooklm__notebook_query`)

2. **Constants**: Added `REVIEWER_BACKEND` (auto/codex/subagent) and `NOTEBOOKLM_NOTEBOOKS` (two notebook IDs for domain accuracy checking)

3. **New section: "Reviewer Backend: Detection & Fallback"**: Auto-detection logic probes Codex MCP at init; if unavailable, falls back to Claude Opus subagent with identical associate-editor persona

4. **New section: "NotebookLM Consultation"**: Before implementing CRITICAL/MAJOR fixes, query both notebooks (ML for Recurrent Events + Interpretable AI) to ground fixes in established theory

5. **Step 2 (Round 1 Review)**: Refactored into backend-branched structure with shared `REVIEWER_PROMPT`. Codex uses `mcp__codex__codex`; subagent uses `Agent` tool with `model: "opus"`

6. **Step 3 (Round 1 Fixes)**: Added NotebookLM consultation sub-step before each CRITICAL/MAJOR fix

7. **Step 5 (Round 2 Review)**: Refactored into backend-branched structure with shared `ROUND_2_PROMPT`. Subagent path embeds full Round 1 review text for context continuity

8. **Step 6 (Round 2 Fixes)**: Added reference to NotebookLM consultation (same as Step 3)

9. **State persistence JSON**: Added `reviewer_backend` field; noted `threadId` is null for subagent backend

10. **Log template**: Added Configuration header (backend + NotebookLM status); fix entries now include NotebookLM grounding notes

11. **Key Rules**: Added rules for NotebookLM-before-fixes, logging the reviewer backend, and updated codex-reply rule to cover subagent alternative

## Design Decisions
- Subagent uses `model: "opus"` for maximum review quality
- NotebookLM is non-blocking: if unavailable, skip silently
- Override via argument: `— reviewer: subagent` to force backend
- Round 2 subagent gets full Round 1 review embedded in prompt (no thread persistence)

---

## Phase 2: Shared Protocol + Batch Update (23 additional skills)

### New File Created

- `.claude/rules/codex-fallback-protocol.md` — shared protocol covering detection, single-shot fallback, multi-round fallback, NotebookLM consultation, and logging conventions

### Why Shared Protocol

23 skills use Codex MCP. Inlining the full fallback logic into each would be massive and unmaintainable. Instead, a shared rules file defines the protocol once, and each skill references it with a one-liner.

### Skills Updated (23 files)

Each received two edits: (1) added `mcp__notebooklm__notebook_query` (and `Agent` where missing) to `allowed-tools`, (2) added fallback reference line pointing to the protocol.

- **Multi-round review skills:** research-refine, auto-review-loop, research-review, method-derive, rebuttal
- **Single-shot review skills:** idea-creator, novelty-check, result-to-claim, ablation-planner, training-check, paper-plan, paper-write, paper-figure, paper-slides, paper-poster, paper-illustration, grant-proposal
- **Orchestrator skills:** idea-discovery, idea-discovery-robot, research-refine-pipeline, research-pipeline, paper-writing, experiment-bridge

### Total Files Modified This Session

- 1 new file: `.claude/rules/codex-fallback-protocol.md`
- 24 skill files updated (1 inline + 23 via shared reference)
