# Design Spec: Harmonize Phase 2 Prompt Layout with Phase 4 in method-derive SKILL.md

**Status:** APPROVED (pending user spec review)
**Date:** 2026-04-20
**Target file:** `.claude/skills/method-derive/SKILL.md`
**Scope:** Pure markdown restructure of Phase 2. Prompt text and skill behavior unchanged.

---

## 1. Problem

Phase 2 and Phase 4 both have a "branch by `REVIEWER_BACKEND`, both branches send the same prompt" structure, but they express it differently:

- **Phase 2 (lines ~200–320)** — the full `REVIEWER_PROMPT` body (persona, 7-dimension scoring rubric, verdict rules, ~77 lines of prompt text) lives **inline inside the Codex branch's `prompt: |` block**. The subagent branch contains only a stub (`[REVIEWER_PROMPT below — same text as Codex branch]`). The downstream `#### REVIEWER_PROMPT` section is **just a pointer**: *"It is the text that already appears above in the Codex branch after the `prompt: |` line."*
- **Phase 4 (lines ~393–484)** — both branches contain only stubs (`[ROUND_N_PROMPT below]`). The downstream `#### ROUND_N_PROMPT` section contains the **full prompt text** in a fenced code block — single source of truth.

This asymmetry is confusing to read (readers must reconcile two different organizational patterns within a few hundred lines) and fragile to edit (changing REVIEWER_PROMPT requires editing inside YAML indentation in one branch while keeping the downstream pointer accurate).

## 2. Goal

Make Phase 2 structurally isomorphic to Phase 4. Both phases should read identically in terms of section ordering and where the shared prompt body lives.

## 3. Target Structure (applies to both phases)

```
### Phase X: <title>

**Branch by `REVIEWER_BACKEND`.** Both branches send the same <PROMPT_NAME>
(defined below, with the optional `## User Focus (...)` block prepended when
USER_FOCUS is non-empty).

#### If backend = `codex`
  <thin stub: tool call scaffolding + "[<PROMPT_NAME> below]">

#### If backend = `subagent`
  <thin stub: Agent scaffolding + any branch-specific context setup
   + "[<PROMPT_NAME> below]">

#### USER_FOCUS injection (shared by both backends)
  <block, unchanged>

#### <PROMPT_NAME> (shared by both backends)
  <FULL prompt text as fenced code block — single source of truth>

<closing checkpoint / save instructions>
```

Phase 4 already follows this pattern for `ROUND_N_PROMPT`. Phase 2 will be edited to follow it for `REVIEWER_PROMPT`.

## 4. Concrete Edits to Phase 2

All edits are to `.claude/skills/method-derive/SKILL.md`. Line numbers are approximate (based on current file state).

### Edit 1 — Codex branch (lines ~206–282)

**Before:** Contains the full inline prompt body after `prompt: |`:

```
mcp__codex__codex:
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)
    ... [~77 lines of prompt text] ...
    - REDERIVE: a fundamental step ... is wrong.
```

**After:** Thin stub matching Phase 4's Codex stub:

```
mcp__codex__codex:
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [REVIEWER_PROMPT below]
```

### Edit 2 — Subagent branch (lines ~284–295)

**Before:**

```
Agent:
  description: "method-derive math review round 1"
  model: "opus"
  prompt: |
    [REVIEWER_PROMPT below — same text as Codex branch]
```

**After:** Trim the dangling " — same text as Codex branch" since the prompt text will now actually live below. Stub becomes exactly:

```
Agent:
  description: "method-derive math review round 1"
  model: "opus"
  prompt: |
    [REVIEWER_PROMPT below]
```

(`model: "opus"` note and `threadId = null` explanation remain.)

### Edit 3 — Downstream `#### REVIEWER_PROMPT (shared by both backends)` section (lines ~309–313)

**Before:** Three-line pointer:

> The prompt body — persona, 7-dimension scoring rubric, verdict rules, output format — is unchanged from prior versions. It is the text that already appears above in the Codex branch after the `prompt: |` line.

**After:** Full prompt text in a fenced code block, copied **verbatim** from the current Codex-branch inline. Use triple-backtick fencing (not YAML-indented) to match Phase 4's `ROUND_N_PROMPT` style:

<pre>
```
You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)
with deep expertise in survival analysis, semiparametric estimation, recurrent
event methods, missing data, and pseudo-observation theory.

... [full ~77 lines, byte-identical to pre-edit Codex inline] ...

- REDERIVE: a fundamental step (identification, key expectation, variance structure) is wrong.
```
</pre>

### Edit 4 — Checkpoint tail

The existing "**CRITICAL (Codex branch only): Save the `threadId`** ..." sentence and the "**Checkpoint:** Update `DERIVE_STATE.json` ..." line remain after the extracted prompt section, matching where Phase 4 places its checkpoint. No text change.

## 5. What Does NOT Change

- **Prompt text itself** — persona, 7-dim rubric, scoring weights, verdict rules, output format — byte-identical before and after.
- **USER_FOCUS injection block** — already correct; untouched.
- **Phase 4** — untouched.
- **Checkpoint schema** — `reviewer_backend`, `user_focus`, `threadId`, `last_score`, `last_verdict` fields unchanged.
- **File paths** — `derive-logs/round-N-math-review.md`, `DERIVE_STATE.json` unchanged.
- **Ordering of subsections** within Phase 2 — already matches Phase 4 ordering (codex → subagent → USER_FOCUS → extracted PROMPT → checkpoint). Only the *content distribution* between stubs and extracted section changes.

## 6. Risks and Ambiguity

- **Code-fence style for extracted block.** Phase 4's `ROUND_N_PROMPT` uses triple-backtick fencing (not YAML-indented). Matching that keeps the two phases visually consistent and avoids confusion with the YAML tool-call blocks.
- **Cross-reference in USER_FOCUS injection.** The USER_FOCUS block says *"immediately before the `=== DERIVATION ===` line inside REVIEWER_PROMPT"*. That line still exists in the extracted block, so the reference remains valid without edit.
- **No semantic drift.** Because the extracted prompt is a verbatim copy of the Codex-branch inline, the text sent to either backend on Round 1 is byte-identical to the pre-edit version.

## 7. Verification Plan

1. After applying edits, `grep -n 'REVIEWER_PROMPT\|ROUND_N_PROMPT' SKILL.md` should show a parallel structure between the two phases (preamble mention → 2× branch stubs → USER_FOCUS → extracted section header).
2. Diff the extracted `#### REVIEWER_PROMPT` body against the pre-edit Codex-branch inline: should be line-for-line identical (modulo fence style vs. YAML indent).
3. Read both phases top-to-bottom; section ordering and rhetoric should feel interchangeable.
4. No rendering/compilation check needed — markdown only.

## 8. Out of Scope

- Refactoring Phase 3 or later phases.
- Editing the USER_FOCUS injection wording.
- Changing any behavior, scoring weights, or verdict rules.
- Touching other skills that use the same fallback protocol.

## 9. Estimated Impact

- Lines changed: ~90 in Phase 2 (prompt body moves; two stubs shrink; pointer section gains body).
- Net line count: approximately unchanged (the ~77-line prompt moves from one location to another; branch stubs shrink by the same amount).
- Behavior change: none.

---

**Next step after user approval of this spec:** invoke `writing-plans` skill to produce a step-by-step implementation plan (exact Edit tool calls with old/new string pairs).
