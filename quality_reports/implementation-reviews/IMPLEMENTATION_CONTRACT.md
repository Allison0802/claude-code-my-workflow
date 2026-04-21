# Implementation Contract: flow-prepass plan → SKILL.md

## Goal
Verify that all changes specified in `docs/superpowers/plans/2026-04-18-flow-prepass.md` have been correctly implemented in `.claude/skills/auto-paper-improvement-loop/SKILL.md`.

## Artifact under review
`.claude/skills/auto-paper-improvement-loop/SKILL.md`

## Source of truth
`docs/superpowers/plans/2026-04-18-flow-prepass.md` (Tasks 2–7)

## Required changes (from plan)

### Task 2 — FLOW_PREPASS constant
- `FLOW_PREPASS = true` constant present after `HUMAN_CHECKPOINT`, before `NOTEBOOKLM_NOTEBOOKS`
- Override example updated to include "flow prepass: false"
- Exactly 2 lines match `FLOW_PREPASS|flow prepass` in the constants/override area

### Task 3 — Step 1.5 (logic flow pre-pass, generalized)
- Step 1.5 inserted between Step 1 bash block and Step 2
- "Round N" language (not hardcoded to rounds 1/2)
- `FLOW_PREPASS_OUTPUT_RN` runtime variable defined
- Pre-pass agent uses `model: "opus"`
- Injection rules for all 4 paths (Round 1 Codex, Round 1 subagent, Round N≥2 Codex, Round N≥2 subagent)
- Failure policy: log + set empty + continue (no abort)

### Task 4 — Step R.0 (re-collect paper text, generalized)
- Step R.0 inserted between Step 4 recompile and Step 5 Round 2 Review
- Explicitly `FLOW_PREPASS`-independent
- Failure policy present

### Task 5 — Round 2 step generalized
- "Before this step" note references Step R.0 and Step 1.5
- `ROUND_2_PROMPT` renamed to `ROUND_N_PROMPT` (0 stale references)

### Task 6 — Log template + HUMAN_CHECKPOINT
- `### Logic Flow Pre-Analysis (Round 1)` in log template
- `### Logic Flow Pre-Analysis (Round 2)` in log template
- MAX_ROUNDS > 2 note before `## PDFs`
- HUMAN_CHECKPOINT prompt reads "Round N review complete." (not "Round 1")

## Verification method
grep commands (plan's own verification suite) — this is a Markdown skill file, not executable code

## Non-goals
- Evaluating overall skill quality or completeness beyond plan scope
- Checking runtime behavior (skill is a Markdown instruction document)
