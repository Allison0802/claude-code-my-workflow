# research-refine Reviewer Fallback + USER_FOCUS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mirror the reviewer-backend fallback and USER_FOCUS patterns from `.claude/skills/auto-paper-improvement-loop/SKILL.md` into `.claude/skills/research-refine/SKILL.md`, so that Codex MCP outages degrade to a Claude subagent and user-specified focus directives persist across every review round.

**Architecture:** Single-file doc edit. Add two new constants (REVIEWER_BACKEND, USER_FOCUS), an argument-parsing subsection, a shared-protocol pointer, two new state fields (`reviewer_backend`, `user_focus`), backend branches in Phase 2 (Round 1 review) and Phase 4 (Round N review) that share reusable prompt blocks with USER_FOCUS injection, a new Phase 3.1b NotebookLM grounding step, a Configuration block in the final report, and four new Key Rules entries. No caller changes; external contract stays backward-compatible.

**Tech Stack:** Markdown (skill definition file); edits via Claude Code Edit tool; verification via Grep and Read.

**Spec:** [quality_reports/specs/2026-04-20_research-refine-reviewer-fallback/design.md](../specs/2026-04-20_research-refine-reviewer-fallback/design.md)

**Target file:** `.claude/skills/research-refine/SKILL.md`

**Commit cadence:** One commit per task (7 total) rather than per step — this is prose, not code, and each task produces a coherent unit.

---

## Task 1: Add NotebookLM tool to frontmatter

**Files:**
- Modify: `.claude/skills/research-refine/SKILL.md:4`

- [ ] **Step 1: Update `allowed-tools` line**

Use Edit to change:

```
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch, Agent, mcp__codex__codex, mcp__codex__codex-reply
```

to:

```
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch, Agent, mcp__codex__codex, mcp__codex__codex-reply, mcp__notebooklm__notebook_query
```

- [ ] **Step 2: Verify**

Run Grep for `mcp__notebooklm__notebook_query` in the file, `output_mode: content`, `-n: true`. Expect exactly one match on line 4.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/research-refine/SKILL.md
git commit -m "feat(research-refine): permit mcp__notebooklm__notebook_query tool"
```

---

## Task 2: Add REVIEWER_BACKEND and USER_FOCUS constants

**Files:**
- Modify: `.claude/skills/research-refine/SKILL.md` (Constants section, around line 34-45)

- [ ] **Step 1: Append two constants to the Constants block**

Use Edit to change the `old_string`:

```
- **MAX_NEW_TRAINABLE_COMPONENTS = 2** — Soft cap for genuinely new trainable pieces. Exceed only if the paper breaks otherwise.

> Override via argument if needed, e.g. `/research-refine "problem | approach" -- max rounds: 3, threshold: 9`.
```

to `new_string`:

```
- **MAX_NEW_TRAINABLE_COMPONENTS = 2** — Soft cap for genuinely new trainable pieces. Exceed only if the paper breaks otherwise.
- **REVIEWER_BACKEND = `auto`** — Which reviewer to use. Values: `auto` (detect Codex MCP, fall back to subagent), `codex` (force Codex MCP), `subagent` (force Claude subagent). See **Reviewer Backend** branching in Phase 2 and Phase 4.
- **USER_FOCUS = `""`** — Free-text user directive that biases the reviewer's attention (e.g., `"focus on frontier leverage over novelty"`, `"prioritize simplification"`). When non-empty, injected verbatim into **every** round's reviewer prompt (Round 1 through Round MAX_ROUNDS). Set from arguments (see parsing below).

> Override via argument if needed, e.g. `/research-refine "problem | approach" -- max rounds: 3, threshold: 9, reviewer: subagent, focus: "prioritize simplification over added machinery"`.

**Reviewer fallback & NotebookLM:** When Codex MCP is unavailable, this skill falls back to a Claude subagent reviewer (same top-venue ML reviewer persona). Before implementing CRITICAL reviewer action items in Phase 3, consult NotebookLM for domain accuracy when the criticism maps to survival analysis, pseudo-observation theory, recurrent events, competing risks, C-index, ML model assumptions, or interpretability claims. See `.claude/rules/codex-fallback-protocol.md` for the full shared protocol.

### Argument Parsing for USER_FOCUS and REVIEWER_BACKEND

`$ARGUMENTS` may contain (a) the problem / approach block, (b) recognized parameters (`max rounds:`, `threshold:`, `reviewer:`, `focus:`), and (c) free-text directives. Parse as follows:

1. Extract recognized parameters by their `key:` prefix. Valid `reviewer:` values are `auto`, `codex`, `subagent` (anything else → log a warning and fall back to `auto`).
2. **Anything left over — including free-text directives like "focus on representation design" — is treated as `USER_FOCUS`.** Concatenate and trim whitespace.
3. If the user explicitly provides `focus: "..."`, that value takes precedence over any free-text leftovers.
4. Log the parsed `USER_FOCUS` value (or `(none)`) and `REVIEWER_BACKEND` to `refine-logs/REFINEMENT_REPORT.md` under a `## Configuration` block (added in Phase 5) so the user can verify capture.
```

- [ ] **Step 2: Verify both constants and the new subsection are present**

Run Grep for `REVIEWER_BACKEND|USER_FOCUS|Argument Parsing for USER_FOCUS|Reviewer fallback & NotebookLM` in the file. Expect 6+ matches across the Constants block, override example, protocol-pointer paragraph, and new subsection heading.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/research-refine/SKILL.md
git commit -m "feat(research-refine): add REVIEWER_BACKEND and USER_FOCUS constants + argument parsing"
```

---

## Task 3: Update REFINE_STATE.json schema

**Files:**
- Modify: `.claude/skills/research-refine/SKILL.md` (State Persistence section, around line 51-77)

- [ ] **Step 1: Update the example JSON block**

Use Edit to change the `old_string`:

```
```json
{
  "phase": "review",
  "round": 1,
  "threadId": "019cd392-...",
  "last_score": 6.5,
  "last_verdict": "REVISE",
  "status": "in_progress",
  "timestamp": "2026-03-22T20:00:00"
}
```
```

to `new_string`:

```
```json
{
  "phase": "review",
  "round": 1,
  "threadId": "019cd392-...",
  "reviewer_backend": "codex",
  "user_focus": "focus on frontier leverage over novelty",
  "last_score": 6.5,
  "last_verdict": "REVISE",
  "status": "in_progress",
  "timestamp": "2026-03-22T20:00:00"
}
```
```

- [ ] **Step 2: Add two rows to the field-definitions table**

Use Edit to change the `old_string`:

```
| `threadId` | string or null | Reviewer thread ID for `codex-reply` continuity |
| `last_score` | number or null | Most recent overall score from reviewer |
```

to `new_string`:

```
| `threadId` | string or null | Reviewer thread ID for `codex-reply` continuity (null when `reviewer_backend == "subagent"`) |
| `reviewer_backend` | `"codex"` or `"subagent"` | Backend used for Phase 2 and all Phase 4 review calls |
| `user_focus` | string (possibly empty) | Verbatim user focus directive; re-injected into every round prompt |
| `last_score` | number or null | Most recent overall score from reviewer |
```

- [ ] **Step 3: Add a defensive-read note to the Write rules**

Use Edit to change the `old_string`:

```
**Write rules:**
- **Write after each phase completes** (not before). Overwrite each time — only the latest state matters.
- **On completion** (Phase 5 finished), set `"status": "completed"`.
```

to `new_string`:

```
**Write rules:**
- **Write after each phase completes** (not before). Overwrite each time — only the latest state matters.
- **`user_focus` and `reviewer_backend` MUST be included on every checkpoint write.** Post-compact recovery reads both before resuming; missing `user_focus` defaults to `""` (defensive read), missing `reviewer_backend` defaults to `"auto"`.
- **On completion** (Phase 5 finished), set `"status": "completed"`.
```

- [ ] **Step 4: Verify**

Run Grep for `reviewer_backend|user_focus` in the file. Expect at least 5 matches (JSON example, two table rows, write rule, and argument-parsing reference from Task 2).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/research-refine/SKILL.md
git commit -m "feat(research-refine): persist reviewer_backend and user_focus in REFINE_STATE.json"
```

---

## Task 4: Refactor Phase 2 (Round 1 review) into backend branch + USER_FOCUS injection

**Files:**
- Modify: `.claude/skills/research-refine/SKILL.md` (Phase 2 section, lines 316–391)

- [ ] **Step 1: Replace the entire Phase 2 body**

Use Edit. The `old_string` is the full Phase 2 block starting at `### Phase 2: External Method Review (Round 1)` through (but not including) `### Phase 3: Parse Feedback and Revise the Method`. Replace with:

```
### Phase 2: External Method Review (Round 1)

Send the full proposal to an **elegance-first, frontier-aware, method-first** reviewer. The reviewer should spend most of the critique budget on the method itself, not on expanding the experiment menu.

**Branch by `REVIEWER_BACKEND`** (default `auto`: probe Codex MCP with a lightweight ping; use `codex` on success, `subagent` on error/timeout/not-found; log which backend was chosen):

#### If backend = `codex`

```
mcp__codex__codex:
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [REVIEWER_PROMPT below — verbatim]
```

**CRITICAL: Save the `threadId`** from this call for all Phase 4 rounds.

#### If backend = `subagent`

```
Agent:
  description: "research-refine review round 1"
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    [REVIEWER_PROMPT below — verbatim]
```

`model: "opus"` is **REQUIRED**. The Agent tool inherits Sonnet from the parent when `model` is omitted, which silently degrades review quality.

Save the **full review response text verbatim** for Round 2 context (subagents do not persist state between calls). Set `threadId` to `null` in state.

#### REVIEWER_PROMPT (shared by both backends)

**USER_FOCUS injection:** If `USER_FOCUS` is non-empty, insert the `## User Focus (priority)` block below immediately **before** `=== PROPOSAL ===`. If `USER_FOCUS` is empty, omit the entire block — the prompt is byte-identical to the pre-change default.

```
You are a senior ML reviewer for a top venue (NeurIPS/ICML/ICLR).
This is an early-stage, method-first research proposal.

Your job is NOT to reward extra modules, contribution sprawl, or a giant benchmark checklist.
Your job IS to stress-test whether the proposed method:
(1) still solves the original anchored problem,
(2) is concrete enough to implement,
(3) presents a focused, elegant contribution,
(4) uses foundation-model-era techniques appropriately when they are the natural fit.

Review principles:
- Prefer the smallest adequate mechanism over a larger system.
- Penalize parallel contributions that make the paper feel unfocused.
- If a modern LLM / VLM / Diffusion / RL route would clearly produce a better paper, say so concretely.
- If the proposal is already modern enough, do NOT force trendy components.
- Do not ask for extra experiments unless they are needed to prove the core claims.

Read the Problem Anchor first. If your suggested fix would change the problem being solved,
call that out explicitly as drift instead of treating it as a normal revision request.

## User Focus (priority)
[USER_FOCUS verbatim — omit this entire block if USER_FOCUS is empty]

Treat this focus as the highest-priority review lens for this round. Score the proposal
primarily on how well it satisfies this focus, while still flagging any CRITICAL drift,
mechanism weakness, or contribution sprawl you observe.

=== PROPOSAL ===
[Paste the FULL proposal from Phase 1]
=== END PROPOSAL ===

Score these 7 dimensions from 1-10:

1. **Problem Fidelity**: Does the method still attack the original bottleneck, or has it drifted into solving something easier or different?

2. **Method Specificity**: Are the interfaces, representations, losses, training stages, and inference path concrete enough that an engineer could start implementing?

3. **Contribution Quality**: Is there one dominant mechanism-level contribution with real novelty, good parsimony, and no obvious contribution sprawl?

4. **Frontier Leverage**: Does the proposal use current foundation-model-era primitives appropriately when they are the right tool, instead of defaulting to old-school module stacking?

5. **Feasibility**: Can this method be trained and integrated with the stated resources and data assumptions?

6. **Validation Focus**: Are the proposed experiments minimal but sufficient to validate the core claims? Is there unnecessary experimental bloat?

7. **Venue Readiness**: If executed well, would the contribution feel sharp and timely enough for a top venue?

**OVERALL SCORE** (1-10): Weighted toward Problem Fidelity, Method Specificity, Contribution Quality, and Frontier Leverage.
Use this weighting: Problem Fidelity 15%, Method Specificity 25%, Contribution Quality 25%, Frontier Leverage 15%, Feasibility 10%, Validation Focus 5%, Venue Readiness 5%.

For each dimension scoring < 7, provide:
- The specific weakness
- A concrete fix at the method level (interface / loss / training recipe / integration point / deletion of unnecessary parts)
- Priority: CRITICAL / IMPORTANT / MINOR

Then add:
- **Simplification Opportunities**: 1-3 concrete ways to delete, merge, or reuse components while preserving the main claim. Write "NONE" if already tight.
- **Modernization Opportunities**: 1-3 concrete ways to replace old-school pieces with more natural foundation-model-era primitives if genuinely better. Write "NONE" if already modern enough.
- **Drift Warning**: "NONE" if the proposal still solves the anchored problem; otherwise explain the drift clearly.
- **Verdict**: READY / REVISE / RETHINK

Verdict rule:
- READY: overall score >= 9, no meaningful drift, one focused dominant contribution, and no obvious complexity bloat remains
- REVISE: the direction is promising but not yet at READY bar
- RETHINK: the core mechanism or framing is still fundamentally off
```

**CRITICAL: Save the FULL raw response** verbatim (both backends).

Save review to `refine-logs/round-1-review.md` with the raw response in a `<details>` block. Include a header line `**Backend used:** codex | subagent`.

**Checkpoint:** Update `refine-logs/REFINE_STATE.json` with `{"phase": "review", "round": 1, "threadId": "<saved or null>", "reviewer_backend": "<codex|subagent>", "user_focus": "<verbatim>", "last_score": <parsed>, "last_verdict": "<parsed>", ...}`.

```

- [ ] **Step 2: Verify Phase 2 structure**

Run Grep for `If backend = .codex.|If backend = .subagent.|REVIEWER_PROMPT \(shared|## User Focus \(priority\)` in the file. Expect at least 4 matches from this task alone (more will be added in Task 6).

- [ ] **Step 3: Verify the 7-dimension rubric is preserved**

Run Grep for `Problem Fidelity|Method Specificity|Contribution Quality|Frontier Leverage|Feasibility|Validation Focus|Venue Readiness` with `output_mode: count`. Expect each to appear 2+ times (original count was exactly 2 each in Phase 2; we preserved those and added no new mentions).

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/research-refine/SKILL.md
git commit -m "feat(research-refine): Phase 2 backend branch + USER_FOCUS injection"
```

---

## Task 5: Insert Phase 3.1b NotebookLM grounding step

**Files:**
- Modify: `.claude/skills/research-refine/SKILL.md` (Phase 3 section, between Step 3.1 and Step 3.2)

- [ ] **Step 1: Insert Step 3.1b immediately after the Step 3.1 STOP CONDITION**

Use Edit to change the `old_string`:

```
**STOP CONDITION**: If overall score >= SCORE_THRESHOLD, verdict is READY, and there is no unresolved drift warning, skip to Phase 5.

#### Step 3.2: Revise With an Anchor Check and a Simplicity Check
```

to `new_string`:

```
**STOP CONDITION**: If overall score >= SCORE_THRESHOLD, verdict is READY, and there is no unresolved drift warning, skip to Phase 5.

#### Step 3.1b: Ground CRITICAL Items in NotebookLM (optional)

For each reviewer action item tagged **CRITICAL** whose subject touches survival analysis, pseudo-observation theory, recurrent events, competing risks, C-index, ML model assumptions, or interpretability claims:

1. Pick the matching notebook:
   - `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` — ML for Recurrent Events
   - `fea2207b-7ec1-463c-b73f-58c0c4febb41` — Interpretable AI
2. Call `mcp__notebooklm__notebook_query` with a **targeted question** derived from the criticism (not a generic prompt). Example:
   ```
   mcp__notebooklm__notebook_query:
     notebook_id: "0bf80af5-8b8d-423d-b7ef-94b13ad48f7b"
     query: "Under censoring, is the pseudo-observation estimator for CIF unbiased when the censoring distribution is conditional on covariates?"
   ```
3. Use the response to verify theoretical soundness of the planned revision **before** applying it.
4. Log `Fix grounded in NotebookLM: [notebook name] — [key finding]` next to that fix in the round refinement file (Step 3.2 output).

**Fallback:** If the NotebookLM tool errors, times out, or is unavailable, log `"NotebookLM unavailable — changes applied without notebook consultation"` once per round and continue. Do **not** retry; do **not** abort.

If no reviewer items match the domain gate above, skip this step silently.

#### Step 3.2: Revise With an Anchor Check and a Simplicity Check
```

- [ ] **Step 2: Verify**

Run Grep for `Step 3.1b: Ground CRITICAL Items in NotebookLM` in the file. Expect exactly one match.

Run Grep for `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b|fea2207b-7ec1-463c-b73f-58c0c4febb41`. Expect exactly one match each (both notebook IDs appear once in Step 3.1b).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/research-refine/SKILL.md
git commit -m "feat(research-refine): add Phase 3.1b NotebookLM grounding step"
```

---

## Task 6: Refactor Phase 4 (Round N re-evaluation) into backend branch + USER_FOCUS re-assertion

**Files:**
- Modify: `.claude/skills/research-refine/SKILL.md` (Phase 4 section)

- [ ] **Step 1: Replace the Phase 4 body**

Use Edit. The `old_string` is the entire Phase 4 block starting at `### Phase 4: Re-evaluation (Round 2+)` through the line immediately before `### Phase 5: Final Report and Logs`. Replace with:

```
### Phase 4: Re-evaluation (Round 2+)

**Branch by `REVIEWER_BACKEND`** (use whatever was chosen in Phase 2; do **not** re-probe — the backend is locked for the session):

#### If backend = `codex`

Send the revised proposal back to GPT-5.4 in the **same thread**:

```
mcp__codex__codex-reply:
  threadId: [saved from Phase 2]
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [ROUND_N_PROMPT below — verbatim]
```

#### If backend = `subagent`

Subagents do not persist state, so every Round N ≥ 2 call embeds prior review context. Spawn a new Agent:

```
Agent:
  description: "research-refine review round N"
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    You are a senior ML reviewer for a top venue (NeurIPS/ICML/ICLR).

    ## Context: You have reviewed this proposal across N-1 previous rounds.

    ### Summaries of Rounds 1 through N-2:
    [Omit this block entirely when N = 2. For N >= 3, read each round-k-review.md
     (k = 1..N-2) and refine-logs/score-history.md, then produce:]
    **Round k (Score: X/10, Verdict: REVISE|RETHINK|READY):** [3-sentence summary: the
    top weaknesses identified that round plus the fixes that were applied before Round k+1]

    ### Your Most Recent Review (Round N-1, verbatim):
    [paste full Round N-1 review text from refine-logs/round-(N-1)-review.md]

    ### Changes Implemented Since Round N-1:
    1. [method change 1 — from refine-logs/round-(N-1)-refinement.md "Changes Made"]
    2. [method change 2]
    ...

    [ROUND_N_PROMPT below — verbatim]
```

`model: "opus"` is **REQUIRED** for the same reason as Phase 2.

Save the full response for Round N+1 context.

#### ROUND_N_PROMPT (shared by both backends)

**USER_FOCUS re-assertion:** If `USER_FOCUS` is non-empty, prepend a `## User Focus (priority — persistent across rounds)` block at the very top of `ROUND_N_PROMPT`, **before** `[Round N re-evaluation]`. This re-assertion is redundant by design: Codex threads carry prior context and subagent prompts already embed prior reviews, but re-asserting every round guarantees the focus never silently decays across compaction or context reshuffling. If `USER_FOCUS` is empty, omit the block entirely.

```
## User Focus (priority — persistent across rounds)
[USER_FOCUS verbatim — omit this entire block if USER_FOCUS is empty]

This focus was specified at the start of the loop and applies to every round.
Continue scoring the proposal primarily on how well it satisfies this focus.

[Round N re-evaluation]

I revised the proposal based on your feedback.
First, check whether the original Problem Anchor is still preserved.
Second, judge whether the method is now more concrete, more focused, and more current.

Key changes:
1. [Method change 1]
2. [Method change 2]
3. [Simplification / modernization / pushback if any]

=== REVISED PROPOSAL ===
[Paste the FULL revised proposal]
=== END REVISED PROPOSAL ===

Please:
- Re-score the same 7 dimensions and overall
- State whether the Problem Anchor is preserved or drifted
- State whether the dominant contribution is now sharper or still too broad
- State whether the method is simpler or still overbuilt
- State whether the frontier leverage is now appropriate or still old-school / forced
- If USER_FOCUS is non-empty above, state whether this round adequately addresses it
- Focus new critiques on missing mechanism, weak training signal, weak integration point, pseudo-novelty, or unnecessary complexity
- Use the same verdict rule: READY only if overall score >= 9 and no blocking issue remains

Same output format: 7 scores, overall score, verdict, drift warning, simplification opportunities, modernization opportunities, remaining action items.
```

Save review to `refine-logs/round-N-review.md`. Include a header line `**Backend used:** codex | subagent`.

**Checkpoint:** Update `refine-logs/REFINE_STATE.json` with `{"phase": "review", "round": N, "threadId": "<saved or null>", "reviewer_backend": "<codex|subagent>", "user_focus": "<verbatim>", "last_score": <parsed>, "last_verdict": "<parsed>", ...}`.

Then return to Phase 3 until:

- **Overall score >= SCORE_THRESHOLD** and verdict is READY and no unresolved drift
- or **MAX_ROUNDS reached**

```

- [ ] **Step 2: Verify both Phase 4 branches and the ROUND_N_PROMPT block exist**

Run Grep for `ROUND_N_PROMPT \(shared by both backends\)|## User Focus \(priority — persistent across rounds\)` with `output_mode: content`, `-n: true`. Expect exactly 2 matches total (one for the heading, one for the injection block header).

- [ ] **Step 3: Verify backend branching appears twice (Phase 2 + Phase 4)**

Run Grep for `Branch by .REVIEWER_BACKEND.` with `output_mode: count`. Expect exactly 2 matches.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/research-refine/SKILL.md
git commit -m "feat(research-refine): Phase 4 backend branch + USER_FOCUS re-assertion every round"
```

---

## Task 7: Add Configuration block to REFINEMENT_REPORT, update Key Rules, update Output Structure

**Files:**
- Modify: `.claude/skills/research-refine/SKILL.md` (Phase 5 REFINEMENT_REPORT template, Key Rules section, Output Structure section)

- [ ] **Step 1: Add a Configuration block near the top of the REFINEMENT_REPORT template**

Use Edit to change the `old_string`:

```
# Refinement Report

**Problem**: [user's problem]
**Initial Approach**: [user's vague approach]
**Date**: [today]
**Rounds**: N / MAX_ROUNDS
**Final Score**: X / 10
**Final Verdict**: [READY / REVISE / RETHINK]

## Problem Anchor
```

to `new_string`:

```
# Refinement Report

**Problem**: [user's problem]
**Initial Approach**: [user's vague approach]
**Date**: [today]
**Rounds**: N / MAX_ROUNDS
**Final Score**: X / 10
**Final Verdict**: [READY / REVISE / RETHINK]

## Configuration
- **Reviewer backend:** codex | subagent
- **NotebookLM:** available | unavailable
- **MAX_ROUNDS:** N
- **SCORE_THRESHOLD:** X
- **USER_FOCUS:** "[verbatim user focus directive, or `(none)` if empty]"

## Problem Anchor
```

- [ ] **Step 2: Note the backend in per-round raw-response blocks**

Use Edit to change the `old_string`:

```
## Raw Reviewer Responses

<details>
<summary>Round 1 Review</summary>

[Full verbatim response from GPT-5.4]

</details>
```

to `new_string`:

```
## Raw Reviewer Responses

<details>
<summary>Round 1 Review (backend: codex | subagent)</summary>

[Full verbatim response from GPT-5.4 or Claude subagent]

</details>
```

- [ ] **Step 3: Append four entries to the Key Rules block**

Use Edit to change the `old_string`:

```
- **Document everything.** Save every raw review, every anchor check, every simplicity check, and every major method change.
```

to `new_string`:

```
- **Document everything.** Save every raw review, every anchor check, every simplicity check, and every major method change.
- **Subagent `model: "opus"` is MANDATORY.** The Agent tool inherits Sonnet from the parent when `model` is omitted, which silently degrades review quality. Never omit.
- **`user_focus` and `reviewer_backend` MUST be written on every `REFINE_STATE.json` checkpoint.** On post-compact resume, read both before entering Phase 3 or Phase 4; missing `user_focus` defaults to `""` and missing `reviewer_backend` defaults to `"auto"`.
- **USER_FOCUS is re-injected into every round's reviewer prompt**, even when thread context (Codex) or embedded summary (subagent) already carries it. Belt-and-suspenders: the focus must never silently decay across rounds.
- **NotebookLM is silent-skip on failure.** If `mcp__notebooklm__notebook_query` errors or is unavailable during Phase 3.1b, log once and continue applying fixes. Never abort the loop for a notebook miss.
```

- [ ] **Step 4: Update the Output Structure preamble to mention the Configuration block**

Use Edit to change the `old_string`:

```
Every `round-N-refinement.md` must contain a **full anchored proposal**, not just incremental fixes.
```

to `new_string`:

```
Every `round-N-refinement.md` must contain a **full anchored proposal**, not just incremental fixes.

`REFINE_STATE.json` persists `reviewer_backend` and `user_focus` on every checkpoint; `REFINEMENT_REPORT.md` surfaces both under a `## Configuration` block.
```

- [ ] **Step 5: Verify all four Key Rules entries landed**

Run Grep for `Subagent .model: .opus.. is MANDATORY|user_focus. and .reviewer_backend. MUST be written|USER_FOCUS is re-injected into every round|NotebookLM is silent-skip on failure`. Expect exactly 4 matches.

- [ ] **Step 6: Verify Configuration block exists in the report template**

Run Grep for `## Configuration\n- \*\*Reviewer backend:` with `multiline: true`. Expect exactly 1 match.

- [ ] **Step 7: Full-file sanity read**

Read the full modified file top-to-bottom once. Confirm:
- Constants block has REVIEWER_BACKEND and USER_FOCUS (around line 42–47 after edits).
- REFINE_STATE.json schema shows both new fields.
- Phase 2 has `#### If backend = \`codex\`` and `#### If backend = \`subagent\`` headings.
- Phase 3 has a `#### Step 3.1b: Ground CRITICAL Items in NotebookLM` heading.
- Phase 4 has the same two backend headings + ROUND_N_PROMPT block.
- REFINEMENT_REPORT template has `## Configuration` block.
- Key Rules has four new bullets at the end.

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/research-refine/SKILL.md
git commit -m "feat(research-refine): Configuration block in report + Key Rules updates"
```

---

## Task 8 (wrap-up): Session log entry

**Files:**
- Create: `quality_reports/session_logs/2026-04-20_research-refine-reviewer-fallback.md`

- [ ] **Step 1: Write the session log**

Use Write to create:

```markdown
# Session Log: research-refine Reviewer Fallback + USER_FOCUS

**Date:** 2026-04-20
**Branch:** main
**Spec:** quality_reports/specs/2026-04-20_research-refine-reviewer-fallback/design.md
**Plan:** quality_reports/plans/2026-04-20_research-refine-reviewer-fallback.md

## Goal
Mirror the reviewer-backend fallback and USER_FOCUS patterns from auto-paper-improvement-loop into research-refine so Codex MCP outages degrade gracefully and user-specified focus directives persist across every review round.

## Key Context
- Pattern source: `.claude/skills/auto-paper-improvement-loop/SKILL.md`
- Shared protocol: `.claude/rules/codex-fallback-protocol.md`
- Prior failure in sibling skill (memory S329): USER_FOCUS was silently dropped — mitigated here by Key Rule + defensive-read on resume + re-assertion every round.

## Changes
- [HH:MM] `.claude/skills/research-refine/SKILL.md` — add NotebookLM tool to frontmatter
- [HH:MM] `.claude/skills/research-refine/SKILL.md` — add REVIEWER_BACKEND + USER_FOCUS constants and argument-parsing subsection
- [HH:MM] `.claude/skills/research-refine/SKILL.md` — add reviewer_backend + user_focus to REFINE_STATE.json schema
- [HH:MM] `.claude/skills/research-refine/SKILL.md` — Phase 2 backend branch + USER_FOCUS injection
- [HH:MM] `.claude/skills/research-refine/SKILL.md` — Phase 3.1b NotebookLM grounding
- [HH:MM] `.claude/skills/research-refine/SKILL.md` — Phase 4 backend branch + USER_FOCUS re-assertion
- [HH:MM] `.claude/skills/research-refine/SKILL.md` — Configuration block + four Key Rules entries

## Verification
- All seven task commits landed on main.
- Grep checks at each task step passed.
- Full-file sanity read confirmed structural coherence.

## Open Questions
None. Doc-only edit; no functional test run (would require a full refinement session).
```

Replace each `[HH:MM]` with the actual commit time.

- [ ] **Step 2: Commit**

```bash
git add quality_reports/session_logs/2026-04-20_research-refine-reviewer-fallback.md
git commit -m "docs(session-log): research-refine reviewer fallback implementation"
```

---

## Self-Review Checklist (post-implementation)

Before declaring the plan executed:

1. **Spec coverage:** Every change in the spec's "Changes to SKILL.md" section A–J is covered by a task. Mapping:
   - A (frontmatter) → Task 1
   - B (constants) → Task 2
   - C (arg parsing) → Task 2
   - D (protocol pointer) → Task 2
   - E (state schema) → Task 3
   - F (Phase 2 branch + USER_FOCUS injection) → Task 4
   - G (Phase 3.1b NotebookLM) → Task 5
   - H (Phase 4 branch + USER_FOCUS re-assertion) → Task 6
   - I (Configuration block) → Task 7
   - J (Key Rules) → Task 7
2. **No orphaned references:** Every mention of `REVIEWER_BACKEND`, `USER_FOCUS`, `reviewer_backend`, `user_focus` in the final file resolves — defined in Constants, parsed from arguments, persisted in state, injected in prompts, logged in report.
3. **Backward compatibility:** Running `/research-refine` with no new arguments (no `reviewer:`, no `focus:`) must produce byte-identical reviewer prompts to the pre-change version. Verify by checking that empty USER_FOCUS omits the entire `## User Focus` block in both Phase 2 and Phase 4.
4. **No placeholders:** No TODO / TBD / "fill in" strings in the modified SKILL.md.

If any item fails, fix and re-verify before closing out.
