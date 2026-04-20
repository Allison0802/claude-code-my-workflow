# research-refine: Reviewer Subagent Fallback + USER_FOCUS

**Status:** DRAFT (awaiting user review)
**Date:** 2026-04-20
**Scope:** Modify `.claude/skills/research-refine/SKILL.md` only
**Pattern source:** `.claude/skills/auto-paper-improvement-loop/SKILL.md`
**Shared protocol:** `.claude/rules/codex-fallback-protocol.md`

## Goal

Mirror the reviewer-backend fallback and USER_FOCUS patterns from
`auto-paper-improvement-loop` into `research-refine` so that:

1. When Codex MCP is unavailable, review rounds degrade to a Claude subagent
   (same reviewer persona) instead of failing.
2. The user can bias every review round toward a specific focus
   (e.g., "focus on frontier leverage"), and that focus never silently drops
   across rounds or across context compaction.
3. CRITICAL reviewer fixes can be grounded in NotebookLM before they are
   applied to the proposal.

## Non-goals

- No flow pre-pass subagent (research-refine operates on a short proposal, not
  a multi-section paper).
- No HUMAN_CHECKPOINT flag.
- No changes to scoring dimensions, score threshold, MAX_ROUNDS, or output
  filenames.
- No changes to phases 0, 1, or 5 beyond adding config/logging fields.

## Changes to SKILL.md

### A. Frontmatter

Add `mcp__notebooklm__notebook_query` to `allowed-tools`. `Agent` is already
listed.

### B. Constants (new)

Append two entries to the Constants block:

- `REVIEWER_BACKEND = "auto"` — values: `auto` (detect Codex MCP, fall back to
  subagent), `codex` (force Codex), `subagent` (force Claude subagent).
- `USER_FOCUS = ""` — free-text priority lens. When non-empty, injected
  verbatim into every review round prompt (Round 1 and every Round N).

Update the override hint line to include both:

```
/research-refine "problem | approach" -- max rounds: 3, threshold: 9,
  reviewer: subagent, focus: "prioritize frontier leverage over novelty"
```

### C. Argument parsing (new subsection after Constants)

`$ARGUMENTS` may contain recognized parameters (`max rounds:`, `threshold:`,
`reviewer:`, `focus:`) and free-text. Parse as follows:

1. Extract recognized parameters by their `key:` prefix.
2. Anything left over — including free-text directives like "focus on the
   representation design" — is treated as `USER_FOCUS`. Concatenate and trim.
3. Explicit `focus: "..."` beats free-text leftovers.
4. Log the parsed `USER_FOCUS` (or `(none)`) to `REFINEMENT_REPORT.md` under
   Configuration so the user can verify capture.

### D. Shared protocol pointer (one-liner)

Near the top (after Principles block), insert:

> **Reviewer fallback & NotebookLM:** When Codex MCP is unavailable, this
> skill falls back to a Claude subagent reviewer (same top-venue ML reviewer
> persona). Before implementing CRITICAL reviewer action items, consult
> NotebookLM for domain accuracy when the criticism maps to
> survival / ML / pseudo-observation theory. See
> `.claude/rules/codex-fallback-protocol.md`.

### E. REFINE_STATE.json schema update

Add two fields to the documented schema and to every checkpoint write:

```json
{
  "phase": "review",
  "round": 1,
  "threadId": "019cd392-...",
  "reviewer_backend": "codex",
  "user_focus": "focus on frontier leverage",
  "last_score": 6.5,
  "last_verdict": "REVISE",
  "status": "in_progress",
  "timestamp": "2026-04-20T20:00:00"
}
```

Field definitions additions:

| Field | Values | Meaning |
|-------|--------|---------|
| `reviewer_backend` | `"codex"` / `"subagent"` | Backend used for Phase 2 and all Phase 4 calls |
| `user_focus` | string (possibly empty) | Verbatim focus directive; re-injected into every round prompt |

`threadId` is `null` when `reviewer_backend == "subagent"`.

On resume, if `user_focus` is absent from state JSON, treat as `""` (defensive
read).

### F. Phase 2 (Round 1 external review) — branch by backend

Replace the single `mcp__codex__codex` call with a backend branch.

#### Shared REVIEWER_PROMPT

Lift the existing prompt body (the 7-dimension ML reviewer prompt) into a
single reusable block.

**USER_FOCUS injection rule:** If `USER_FOCUS` is non-empty, insert this block
immediately before `=== PROPOSAL ===`:

```
## User Focus (priority)
<USER_FOCUS verbatim>

Treat this focus as the highest-priority review lens for this round. Score
the proposal primarily on how well it satisfies this focus, while still
flagging any CRITICAL drift, mechanism weakness, or contribution sprawl.
```

If `USER_FOCUS` is empty, omit the entire block — prompt is byte-identical
to current behavior.

#### If backend = `codex`

Existing call, unchanged except using the shared REVIEWER_PROMPT. Save
`threadId`.

#### If backend = `subagent`

```
Agent:
  description: "research-refine review round 1"
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    [REVIEWER_PROMPT above, verbatim]
```

`model: "opus"` is REQUIRED. Agent inherits Sonnet if omitted.

Save the full review response text verbatim (for Round 2+ embedding). Set
`threadId` to `null`.

### G. Phase 3 (revise) — add NotebookLM consultation step

Insert a new Step 3.1b between Step 3.1 (Parse Review) and Step 3.2
(Anchor/Simplicity check):

#### Step 3.1b: Ground CRITICAL Items in NotebookLM (optional)

For each reviewer action item tagged CRITICAL that touches survival analysis,
pseudo-observation theory, competing risks, C-index, ML model assumptions,
or interpretability claims:

1. Pick the matching notebook:
   - `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` — ML for Recurrent Events
   - `fea2207b-7ec1-463c-b73f-58c0c4febb41` — Interpretable AI
2. Call `mcp__notebooklm__notebook_query` with a targeted question derived
   from the criticism.
3. Use the response to verify theoretical soundness before applying the fix.
4. Log `Fix grounded in NotebookLM: [notebook name] — [key finding]` under
   that fix in the round refinement file.

If NotebookLM tool errors or is unavailable: log
`"NotebookLM unavailable — changes applied without notebook consultation"`
once per round and continue. Do not retry, do not abort.

### H. Phase 4 (Round N ≥ 2) — branch by backend

#### ROUND_N_PROMPT

Lift the existing round-N prompt body into a reusable block.

**USER_FOCUS re-assertion rule:** If `USER_FOCUS` is non-empty, prepend this
block at the very top of `ROUND_N_PROMPT`, before `[Round N re-evaluation]`:

```
## User Focus (priority — persistent across rounds)
<USER_FOCUS verbatim>

This focus was specified at the start of the loop and applies to every
round. Continue scoring the proposal primarily on how well it satisfies
this focus.
```

If `USER_FOCUS` is empty, omit the block.

This re-assertion is redundant-by-design: codex threads carry context and
subagent prompts already embed prior reviews, but re-asserting guarantees
the focus never silently decays — guard against memory S329-class failure
("USER_FOCUS was silently dropped").

#### If backend = `codex`

`mcp__codex__codex-reply` with saved `threadId`, using ROUND_N_PROMPT.
Unchanged except for the USER_FOCUS prefix.

#### If backend = `subagent`

For Round N ≥ 2, spawn a new Agent with prior review context embedded:

```
Agent:
  description: "research-refine review round N"
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    You are a senior ML reviewer for a top venue (NeurIPS/ICML/ICLR).

    ## Context: You have reviewed this proposal across N-1 previous rounds.

    ### Summaries of Rounds 1 through N-2:
    [Omit this block when N = 2. For N >= 3, for each round k from 1 to N-2,
     read round-k-review.md and score-history.md to produce:]
    **Round k (Score: X/10):** [3-sentence summary: key weaknesses + fixes]

    ### Your Most Recent Review (Round N-1, verbatim):
    [paste full Round N-1 review text]

    ### Changes Implemented Since Round N-1:
    1. [method change 1]
    2. [method change 2]
    ...

    [ROUND_N_PROMPT here, including USER_FOCUS block if non-empty]
```

Save the full review response text for Round N+1 embedding.

### I. Phase 5 — Configuration block in REFINEMENT_REPORT.md

Add to the top of REFINEMENT_REPORT.md (after Date / Rounds / Score lines):

```
## Configuration
- Reviewer backend: codex | subagent
- NotebookLM: available | unavailable
- MAX_ROUNDS: N
- USER_FOCUS: "<verbatim>" or (none)
```

Per-round entries in the "Raw Reviewer Responses" section note the backend
used for that round.

### J. Key Rules — append four entries

- Subagent Agent calls MUST pass `model: "opus"` explicitly. The Agent tool
  inherits Sonnet from the parent when `model` is omitted, which silently
  degrades review quality.
- `user_focus` and `reviewer_backend` MUST be written on every
  `REFINE_STATE.json` checkpoint. Post-compact resume MUST read both before
  entering Phase 3 or Phase 4; missing `user_focus` defaults to empty.
- USER_FOCUS is re-injected into every round's reviewer prompt, even when
  thread context (Codex) or embedded summary (subagent) already carries it.
- If NotebookLM query errors, skip silently — never abort the fix.

## Implementation order

1. Add NotebookLM tool to frontmatter.
2. Add new constants + override hint line.
3. Add Argument parsing subsection.
4. Add shared-protocol pointer paragraph.
5. Update REFINE_STATE.json schema + field table + defensive-read note.
6. Refactor Phase 2 into shared REVIEWER_PROMPT + backend branch, with
   USER_FOCUS injection.
7. Insert Step 3.1b NotebookLM grounding.
8. Refactor Phase 4 into shared ROUND_N_PROMPT + backend branch, with
   USER_FOCUS re-assertion and subagent context-embedding logic.
9. Add Configuration block to REFINEMENT_REPORT template.
10. Append four entries to Key Rules.

All edits are to a single file. No new files, no changes to callers
(`research-refine-pipeline`, etc.) since the skill's external contract
(arguments, output files, output format) is backward-compatible.

## Testing / verification

- Render-only: after edits, read the file and confirm frontmatter parses and
  section structure is coherent.
- Self-review diff: verify the ten implementation-order items are each
  present in the new file.
- No functional test (this is doc-only); an end-to-end run would require
  a real vague research direction and several minutes of Codex+subagent
  calls — tracked as a follow-up, not a gate.

## Risk notes

- The "silently dropped USER_FOCUS" failure mode recorded in memory S329
  happened in auto-paper-improvement-loop. Mitigation here: Key-Rules entry
  + defensive-read on resume + re-assertion in every round prompt.
- Subagent fallback cost: an Opus review call vs a Codex call. Accepted.
- NotebookLM availability is not guaranteed on all machines — silent-skip
  policy keeps the loop robust.
