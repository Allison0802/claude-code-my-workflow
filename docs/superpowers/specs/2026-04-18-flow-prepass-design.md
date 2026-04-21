# Design: Logic Flow Pre-Pass for `auto-paper-improvement-loop`

**Date:** 2026-04-18
**Status:** APPROVED
**Skill:** `.claude/skills/auto-paper-improvement-loop/SKILL.md`

---

## Summary

Add an optional pre-pass subagent (Option C) that performs a paragraph-to-paragraph and section-to-section reverse outline before each review round. The summary is injected into the reviewer prompt as structural scaffolding, priming the reviewer to flag logic-flow breaks in addition to the existing checklist criteria.

---

## New Constant

```
FLOW_PREPASS = true
```

Default: `true`. Switchable at invocation:

```
/auto-paper-improvement-loop "paper/" — flow prepass: false
```

When `false`, the pre-pass subagent is skipped entirely; reviewer prompt is unchanged from current behavior.

---

## New Step: Step 1.5 — Logic Flow Pre-Pass

**Location:** Inserted before Step 2 (Round 1 Review) and before Step 5 (Round 2 Review).

**Runs when:** `FLOW_PREPASS = true`

**Skips when:** `FLOW_PREPASS = false`

### Subagent call

```
Agent:
  description: "Logic flow pre-pass (Round N)"
  model: "opus"
  prompt: |
    You are an expert academic editor specializing in scientific writing structure.
    Read the following biostatistics methodology paper and produce a structured
    logic flow analysis at two levels: section-to-section and paragraph-to-paragraph.

    ## Full Paper Text:
    [concatenated sections]

    ## Output Format

    ### Section-Level Arc
    For each section, write one sentence describing what it argues or establishes.
    Then describe the logical connector to the next section (e.g., "motivates",
    "formalizes", "tests", "interprets", "extends"). Format:
      Introduction → [argues X] →(motivates)→
      Methods → [formalizes X as estimator Y] →(tested by)→
      Simulation → [tests Y under scenarios A/B/C] →(interpreted in)→
      Results → [shows Z] →(contextualized by)→
      Discussion → [claims W]

    ### Paragraph-Level Flow (per section)
    For each section, list each paragraph's main point in one clause,
    and note the logical link to the next paragraph (e.g., "extends",
    "contrasts", "justifies", "abrupt shift"). Flag any abrupt shifts.
    Format per section:
      [Section name]:
        P1: [argues X] →(extends to)→ P2: [formalizes Y] →(abrupt shift)→ P3: [introduces Z]

    ### Detected Breaks
    List any logic-flow problems found, in order of severity:
    - CRITICAL: A later section relies on something never established earlier
    - MAJOR: A claim in one section is not supported or followed up in the next
    - MINOR: An abrupt paragraph transition with no bridging sentence

    Be specific: name the sections and paragraphs involved.
```

### Injection into REVIEWER_PROMPT

Prepend the following block to the REVIEWER_PROMPT, before `## Full Paper Text`:

```
## Logic Flow Pre-Analysis
[paste full pre-pass output verbatim]

---
```

The reviewer sees: pre-analysis → full paper text → review instructions.

---

## Rounds

The pre-pass runs **before both Round 1 and Round 2** (independently each time), since the paper changes between rounds and the flow analysis must reflect the current state.

---

## State Persistence

No changes to `PAPER_IMPROVEMENT_STATE.json`. The pre-pass output is written verbatim into `PAPER_IMPROVEMENT_LOG.md` under each round's section:

```markdown
### Logic Flow Pre-Analysis (Round N)
[full pre-pass output]
```

---

## Token Cost

When `FLOW_PREPASS = true`, each review round incurs one extra Agent call reading the full paper (~30-page methods paper ≈ 15–20k tokens input). This roughly doubles the token cost per round. Users sensitive to cost should set `flow prepass: false`.

---

## Files Changed

- `.claude/skills/auto-paper-improvement-loop/SKILL.md` — only file modified
  - Add `FLOW_PREPASS` constant to Constants section
  - Add Step 1.5 before Step 2 (with `if FLOW_PREPASS = false → skip` guard)
  - Add Step 1.5 (Round 2 variant) before Step 5 with same guard
  - Update `PAPER_IMPROVEMENT_LOG.md` template to include pre-pass output per round
  - Add `flow prepass: false` to the override example in Constants

---

## Out of Scope

- Sentence-level flow (within a paragraph) — not addressed
- Standalone `/paper-flow-check` skill — deferred; extract later if needed outside improvement loop
- Changes to the fix patterns or NotebookLM consultation logic
