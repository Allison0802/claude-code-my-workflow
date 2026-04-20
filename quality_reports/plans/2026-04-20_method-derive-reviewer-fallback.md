# Design Spec: `method-derive` Reviewer Subagent Fallback + USER_FOCUS

**Status:** DRAFT — awaiting user review
**Date:** 2026-04-20
**Scope:** Single-file edit to `.claude/skills/method-derive/SKILL.md`
**Reference pattern:** `.claude/skills/auto-paper-improvement-loop/SKILL.md` (APIL)
**Related design:** `quality_reports/plans/2026-04-20_research-refine-reviewer-fallback.md` (same pattern, different skill)

---

## Goal

Port the **REVIEWER_BACKEND subagent fallback** and **USER_FOCUS free-text instruction injection** pattern from `auto-paper-improvement-loop` into `method-derive`, scoped to the math review loop (Phase 2 & Phase 4) only.

**Why:** `method-derive`'s current Codex-only math review loop hard-fails when Codex MCP is unavailable, and there is no mechanism for the user to bias the reviewer's attention (e.g., "scrutinize the sandwich variance derivation most heavily"). Both gaps are already solved in APIL.

## Non-Goals

- **Phase 6 (`domain-reviewer` agent) is unchanged.** It is already an `Agent` call with a specific 5-lens rubric; layering USER_FOCUS risks diluting its lenses.
- **Pilot (Phase 7), SLURM (Phase 8), and Final Report (Phase 9) unchanged.**
- **No expansion of NotebookLM consultation.** The existing reference to `.claude/rules/codex-fallback-protocol.md` at line 51 is sufficient.
- **No new triggers, no rename, no description changes.**
- **Default behavior preserved:** when `USER_FOCUS = ""` and `REVIEWER_BACKEND = auto` with Codex available, the reviewer prompts are **byte-identical** to current behavior.

## Design

### 1. New Constants (insert after line 47, before the `> Override constants …` line)

```markdown
- **REVIEWER_BACKEND = `auto`** — Which reviewer to use for the math review loop (Phase 2 & Phase 4). Values: `auto` (detect Codex MCP, fall back to Claude subagent), `codex` (force Codex MCP), `subagent` (force Claude subagent). See `.claude/rules/codex-fallback-protocol.md`. Phase 6's `domain-reviewer` agent is unaffected.
- **USER_FOCUS = `""`** — Free-text user directive that biases the math reviewer's attention (e.g., "scrutinize the sandwich variance derivation most heavily"). When non-empty, injected verbatim into **every** round's reviewer prompt (Phase 2 Round 1 through Phase 4 Round MAX_ROUNDS). Set via arguments (see parsing below) or omit for default reviewer behavior.
```

### 2. Argument Parsing block (insert after the existing `> Override constants via argument …` line, before the reviewer-fallback line at 51)

```markdown
### Argument Parsing for USER_FOCUS

`$ARGUMENTS` may contain a mix of (a) the estimand/method specification, (b) recognized parameters (`pilot_n:`, `pilot_reps:`, `reviewer:`, `focus:`, etc.), and (c) free-text directives. Parse as follows:

1. Extract the estimand/method specification (the `ESTIMAND: … | METHOD: …` block or equivalent).
2. Extract recognized parameters by their `key:` prefix.
3. **Anything left over — including any free-text natural-language directive (e.g., "focus on the variance step") — is treated as `USER_FOCUS`.** Concatenate and trim whitespace.
4. If the user explicitly provides `focus: "..."`, that value takes precedence over any free-text leftovers.
5. Log the parsed `USER_FOCUS` (or `"(none)"`) to `derive-logs/score-history.md` under a "Configuration" block so the user can verify it was captured.
```

### 3. Update Reviewer Fallback Line (line 51)

**Replace:**
> Reviewer fallback & NotebookLM: When Codex MCP is unavailable, this skill falls back to a Claude subagent reviewer — always use `model: "opus"` in the Agent call. Before implementing CRITICAL/MAJOR changes from reviews, consult NotebookLM. See `.claude/rules/codex-fallback-protocol.md` for full protocol.

**With:**
> **Reviewer fallback & NotebookLM:** The math review loop (Phase 2 & Phase 4) respects `REVIEWER_BACKEND`. Under `auto` (default), probe Codex MCP once at startup; if unavailable, fall back to a Claude subagent reviewer with `model: "opus"` (explicit — never omit). Log `"Reviewer backend: codex"` or `"Reviewer backend: subagent (Codex MCP unavailable)"`. Before implementing CRITICAL/MAJOR changes from reviews, consult NotebookLM. See `.claude/rules/codex-fallback-protocol.md` for full protocol.

### 4. State Persistence Update (lines 57–76)

**Add two fields to `DERIVE_STATE.json`:**

```json
{
  "phase": "anchor",
  "round": 0,
  "threadId": null,
  "reviewer_backend": "codex",
  "user_focus": "scrutinize the sandwich variance derivation most heavily",
  "last_score": null,
  "last_verdict": null,
  "status": "in_progress",
  "timestamp": "2026-03-27T10:00:00"
}
```

**Add to the field table:**

| Field | Values |
|-------|--------|
| `reviewer_backend` | `"codex"` / `"subagent"` |
| `user_focus` | Verbatim USER_FOCUS string, or `""` if none. Persisted so checkpoint recovery re-injects the same focus. |

**Note:** `threadId` is only populated when `reviewer_backend == "codex"`. When `"subagent"`, `threadId = null` and the Round N-1 review text is stored in `derive-logs/round-N-1-math-review.md` for Round N context.

### 5. Phase 2 (Round 1 Math Review) — add backend branch + USER_FOCUS block

**Current structure (line 187):** Single `mcp__codex__codex:` call with embedded prompt.

**New structure:**

```markdown
**Branch by `REVIEWER_BACKEND`:**

#### If backend = `codex`

[existing mcp__codex__codex call — unchanged except for USER_FOCUS injection below]
Save the threadId for Phase 4.

#### If backend = `subagent`

Spawn a Claude subagent with the **same persona and prompt**. `model: "opus"` is REQUIRED:

Agent:
  description: "method-derive math review round 1"
  model: "opus"
  prompt: |
    [REVIEWER_PROMPT — same text as Codex branch]

Save the full raw response text to `derive-logs/round-1-math-review.md` for Phase 4 context.

#### USER_FOCUS injection (shared by both backends)

If `USER_FOCUS` is non-empty, prepend a `## User Focus (priority)` block immediately **before** the `=== DERIVATION ===` line:

## User Focus (priority)
[USER_FOCUS verbatim — omit this entire block if USER_FOCUS is empty]

Treat this focus as the highest-priority review lens for this round. Score the derivation primarily on how well it satisfies this focus (weight the 7-dimension scoring accordingly), while still flagging any CRITICAL mathematical errors you observe in other dimensions.

If `USER_FOCUS` is empty, omit the block — prompt is byte-identical to current behavior.
```

**Checkpoint update:** include `"reviewer_backend"` and `"user_focus"` in the state write.

### 6. Phase 4 (Round N Re-evaluation) — add backend branch + persistent USER_FOCUS

**Current structure (line 345):** Single `mcp__codex__codex-reply:` call.

**New structure:**

```markdown
**Branch by `REVIEWER_BACKEND`:**

#### If backend = `codex`

Use `mcp__codex__codex-reply` with the saved `threadId` (current behavior — unchanged).

#### If backend = `subagent`

Spawn a **new** subagent with prior round context embedded (subagents don't persist state). `model: "opus"` is REQUIRED:

Agent:
  description: "method-derive math review round N"
  model: "opus"
  prompt: |
    You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)
    with deep expertise in survival analysis, semiparametric estimation, recurrent
    event methods, missing data, and pseudo-observation theory.

    ## Context: You have reviewed this derivation across N-1 previous rounds.

    ### Summaries of Rounds 1 through N-2:
    [Omit this block entirely when N=2. For N≥3, summarize each prior round in
    3 sentences: score, key gaps identified, corrections applied. Read
    derive-logs/score-history.md and derive-logs/round-K-revision.md to build these.]

    ### Your Most Recent Review (Round N-1, verbatim):
    [paste full round-(N-1)-math-review.md response]

    ### Revisions Implemented Since Round N-1:
    1. [Correction 1]
    2. [Correction 2]
    ...

    [ROUND_N_PROMPT below]

#### USER_FOCUS injection (shared by both backends, every round N ≥ 2)

If `USER_FOCUS` is non-empty, prepend a `## User Focus (priority — persistent across rounds)` block at the top of `ROUND_N_PROMPT`, **before** the `[Round N re-evaluation]` line:

## User Focus (priority — persistent across rounds)
[USER_FOCUS verbatim — omit this entire block if USER_FOCUS is empty]

This focus was specified at the start of the derivation loop and applies to every round.
Continue scoring the derivation primarily on how well it satisfies this focus, while
still flagging any CRITICAL mathematical errors in other dimensions.

If `USER_FOCUS` is empty, omit the block.
```

### 7. Key Rules (insert three bullets, near line 610 next to the existing `config: {"model_reasoning_effort": "xhigh"}` rule)

```markdown
- **Subagent reviewer requires `model: "opus"`** — the `Agent` tool inherits Sonnet from the parent if `model` is omitted. Always pass `model: "opus"` explicitly for every `Agent` call used as a reviewer fallback in this skill.
- **Log the reviewer backend** — record which backend was used (`codex` or `subagent`) in both `DERIVE_STATE.json` and `derive-logs/score-history.md` for every round.
- **USER_FOCUS persists across rounds and compacts.** It is re-injected in every Phase 2 and Phase 4 reviewer call, and it is persisted in `DERIVE_STATE.json` so checkpoint recovery re-injects the same focus.
```

### 8. Update Override Example (line 49)

**Current:**
> Override constants via argument if needed, e.g. `-- pilot_n: 100, pilot_reps: 200`.

**Updated:**
> Override constants via argument if needed, e.g. `-- pilot_n: 100, pilot_reps: 200, reviewer: subagent, focus: "scrutinize the sandwich variance derivation most heavily"`.

---

## Verification Checklist (for implementation phase)

1. **Default behavior unchanged:** with `USER_FOCUS = ""` and Codex available, the reviewer prompts in Phase 2 and Phase 4 are byte-identical to pre-change versions.
2. **Subagent fallback:** when Codex MCP is disabled (simulate by forcing `REVIEWER_BACKEND = subagent`), Phase 2 and Phase 4 use `Agent` with `model: "opus"`.
3. **USER_FOCUS injection:** a non-empty `USER_FOCUS` appears verbatim in the Round 1 prompt AND the Round N prompt (N ≥ 2), in both `codex` and `subagent` branches.
4. **State persistence:** `DERIVE_STATE.json` contains `"reviewer_backend"` and `"user_focus"` after each phase transition; checkpoint recovery reads and re-uses both.
5. **Phase 6 unchanged:** diff shows no modification to the `domain-reviewer` agent invocation or its prompt.
6. **Logging:** `derive-logs/score-history.md` Configuration block shows `Reviewer backend: …` and `USER_FOCUS: "…"` (or `(none)`).
7. **Argument parsing:** invoking with `/method-derive "ESTIMAND: X | METHOD: Y — focus on the variance step"` captures the free-text after the em-dash as `USER_FOCUS`. Invoking with explicit `focus: "…"` takes precedence.

## Files Modified

- `.claude/skills/method-derive/SKILL.md` (only)

## Files NOT Modified

- `.claude/rules/codex-fallback-protocol.md` (referenced, unchanged)
- `.claude/skills/auto-paper-improvement-loop/SKILL.md` (reference pattern, unchanged)
- All other phases / agents / scripts in method-derive

## Commit Convention

```
feat(skill): add reviewer subagent fallback + USER_FOCUS to method-derive

Mirrors the auto-paper-improvement-loop pattern, scoped to the math review
loop (Phase 2 & Phase 4). Phase 6 domain-reviewer unchanged.
```
