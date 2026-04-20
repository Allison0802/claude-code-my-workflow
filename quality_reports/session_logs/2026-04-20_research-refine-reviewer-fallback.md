# Session Log: research-refine Reviewer Fallback + USER_FOCUS

**Date:** 2026-04-20
**Branch:** main
**Spec:** `quality_reports/specs/2026-04-20_research-refine-reviewer-fallback/design.md`
**Plan:** `quality_reports/plans/2026-04-20_research-refine-reviewer-fallback.md`

## Goal

Mirror the reviewer-backend fallback and USER_FOCUS patterns from `.claude/skills/auto-paper-improvement-loop/SKILL.md` into `.claude/skills/research-refine/SKILL.md` so that Codex MCP outages degrade gracefully to a Claude subagent and user-specified focus directives persist across every review round.

## Key Context

- Pattern source: `.claude/skills/auto-paper-improvement-loop/SKILL.md`
- Shared protocol: `.claude/rules/codex-fallback-protocol.md`
- Prior failure in sibling skill (memory S329): USER_FOCUS was silently dropped mid-loop. Mitigated here by (a) a Key Rule pinning user_focus to every checkpoint write, (b) a defensive-read on resume, and (c) re-assertion of USER_FOCUS at the top of every round's reviewer prompt.

## Execution method

Subagent-driven development. Eight tasks, one implementer subagent per task, inline grep-based review after each. No HUMAN_CHECKPOINT between tasks; orchestrator reviewed each subagent's report and proceeded on PASS.

## Commit log (chronological)

- [17:11] `66606af` — `.claude/skills/research-refine/SKILL.md` — Task 1: add `mcp__notebooklm__notebook_query` to frontmatter `allowed-tools`.
- [17:13] `8d594d3` — `.claude/skills/research-refine/SKILL.md` — Task 2: add `REVIEWER_BACKEND` and `USER_FOCUS` constants; add "Reviewer fallback & NotebookLM" protocol-pointer paragraph; add h3 `Argument Parsing for USER_FOCUS and REVIEWER_BACKEND` subsection with 4-step parsing spec.
- [17:15] `5fa49b6` — `.claude/skills/research-refine/SKILL.md` — Task 3: add `reviewer_backend` and `user_focus` fields to REFINE_STATE.json example and field-definitions table; add defensive-read write rule (missing fields default to `""` and `"auto"`).
- [17:18] `55315a9` — `.claude/skills/research-refine/SKILL.md` — Task 4: refactor Phase 2 (Round 1 review) into codex / subagent backend branches with a shared REVIEWER_PROMPT and USER_FOCUS injection block (byte-identical to prior when USER_FOCUS is empty). Subagent branch requires `model: "opus"`.
- [17:20] `e59cee2` — `.claude/skills/research-refine/SKILL.md` — Task 5: insert Phase 3.1b "Ground CRITICAL Items in NotebookLM" step with domain gate (survival/ML/pseudo-obs/interpretability) and silent-skip fallback.
- [17:23] `c32d669` — `.claude/skills/research-refine/SKILL.md` — Task 6: refactor Phase 4 (Round N ≥ 2) into codex / subagent backend branches with shared ROUND_N_PROMPT and USER_FOCUS re-assertion block at the top of every round. Subagent branch embeds prior review verbatim plus summary block for N ≥ 3.
- [17:25] `1653df6` — `.claude/skills/research-refine/SKILL.md` — Task 7: add `## Configuration` block (Reviewer backend / NotebookLM / MAX_ROUNDS / SCORE_THRESHOLD / USER_FOCUS) to REFINEMENT_REPORT template; note backend in per-round raw-response summary; append four Key Rules (opus mandatory, user_focus/reviewer_backend must persist, USER_FOCUS re-injected every round, NotebookLM silent-skip); add one-line pointer under Output Structure.

Note: commit `42e8442` "docs(spec): add method-derive reviewer fallback + USER_FOCUS design" interleaves the sequence — separate parallel work, not part of this session.

## Verification

- Constants block holds `REVIEWER_BACKEND` and `USER_FOCUS` (lines 44–45).
- REFINE_STATE.json schema persists `reviewer_backend` and `user_focus` (lines 85–86).
- Phase 2 has `If backend = codex` / `If backend = subagent` branches around lines 342/354.
- Phase 3.1b NotebookLM grounding at line 479.
- Phase 4 has backend branches and shared ROUND_N_PROMPT at lines 573/586/621.
- REFINEMENT_REPORT template has Configuration block at line 734.
- Four new Key Rules at lines 847–850.
- 7-dimension reviewer rubric (Problem Fidelity, Method Specificity, Contribution Quality, Frontier Leverage, Feasibility, Validation Focus, Venue Readiness) preserved verbatim in both Phase 2 and the revised Phase 4 re-scoring ask.
- All Grep-based task verifications passed (two spec inconsistencies flagged by subagents were plan defects on the orchestrator's side, not implementation bugs).

## Open Questions / Follow-ups

None. Doc-only edit; no functional test run (a live test would require a real vague research direction + Codex and subagent rounds).

The plan contained two verification-count off-by-ones that subagents correctly flagged and worked through:
1. Task 5's Grep expected "exactly one" occurrence of notebook ID `0bf80af5...`, but the prescribed example block references it a second time by design — the subagent stuck with the literal spec content.
2. Task 6's Grep expected "exactly two" matches of the ROUND_N_PROMPT / USER_FOCUS pattern, but the re-assertion instruction paragraph contained a third reference as prose — same call (stick with the spec).

Both were corrected plan defects, not implementation bugs. Leaving as-is in the plan file.
