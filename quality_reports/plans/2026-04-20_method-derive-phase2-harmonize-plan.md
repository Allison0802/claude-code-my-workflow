# method-derive Phase 2 Harmonization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure Phase 2 of `.claude/skills/method-derive/SKILL.md` so that `REVIEWER_PROMPT` lives in a single downstream extracted section (matching Phase 4's `ROUND_N_PROMPT` pattern), with both backend branches becoming thin stubs. Prompt text, scoring rubric, and runtime behavior are byte-identical after the change.

**Architecture:** Three surgical `Edit` operations on one markdown file:
1. Codex branch (Phase 2): replace inline ~77-line prompt body with the stub `[REVIEWER_PROMPT below]`.
2. Subagent branch (Phase 2): trim the " — same text as Codex branch" suffix.
3. Downstream `#### REVIEWER_PROMPT` section: replace the pointer paragraph with the verbatim prompt body in a triple-backtick fenced block.

**Tech Stack:** Plain markdown. No code, compilation, or test suite. "Verification" = structural grep + line count sanity check.

**Spec reference:** [quality_reports/plans/2026-04-20_method-derive-phase2-harmonize.md](quality_reports/plans/2026-04-20_method-derive-phase2-harmonize.md)

---

## File Structure

**Modified:** `.claude/skills/method-derive/SKILL.md` (only file touched)

No new files. No helpers. No tests beyond verification greps.

---

### Task 1: Shrink Phase 2 Codex branch to stub

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` (lines ~204–282, the fenced `mcp__codex__codex:` block inside the `#### If backend = codex` section of Phase 2)

- [ ] **Step 1: Confirm the target block still exists**

Run:
```bash
grep -n 'You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: exactly **two** matches:

- One around line ~213 — inside Phase 2's Codex branch. **This is Task 1's target.**
- One around line ~419 — inside Phase 4's subagent branch. **This is by design and must NOT be touched.** Phase 4's Codex branch carries persona via `threadId` in the GPT thread, but the subagent branch must restate persona each round because subagents are stateless. This second occurrence is a permanent fixture.

If zero, one, or more than two matches, stop and inspect.

- [ ] **Step 2: Apply the Edit**

Use the `Edit` tool on `.claude/skills/method-derive/SKILL.md`.

`old_string` (the complete current Codex-branch fenced block — copy the `\`\`\`` fence lines too):

````
```
mcp__codex__codex:
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)
    with deep expertise in survival analysis, semiparametric estimation, recurrent
    event methods, missing data, and pseudo-observation theory.

    This is an early-stage mathematical derivation of a new statistical estimator.

    Your job is to stress-test whether:
    (1) The estimand is precisely defined and the derivation targets it exactly.
    (2) All identifying assumptions are explicitly stated and are sufficient.
    (3) Every algebraic and probabilistic step is mathematically valid.
    (4) The identification argument is complete and non-circular.
    (5) The variance/SE formula is correctly derived and consistently estimable.

    Review principles:
    - Prefer the minimal necessary assumption set. If an assumption is unnecessary,
      flag it as over-stated, not as missing.
    - Flag every gap in reasoning, even if the conclusion is probably correct.
    - Make implicit assumptions explicit rather than assuming the author intended them.
    - Do not suggest alternative estimands or methods unless the derivation is
      fundamentally broken.
    - Drift: if the derivation implicitly estimates something other than the stated
      estimand, call it out explicitly.

    === DERIVATION ===
    [Paste FULL derivation from Phase 1]
    === END DERIVATION ===

    Score these 7 dimensions from 1–10:

    1. **Estimand Fidelity** (15%): Is the target quantity precisely defined?
       Does the estimator provably estimate exactly that quantity?

    2. **Assumption Sufficiency** (20%): Are all identifying assumptions explicitly
       stated? Are they the minimal necessary set? Any hidden conditions?

    3. **Mathematical Correctness** (25%): Are all algebraic, probabilistic, and
       calculus steps valid? Are expectations, variances, and limits correct?

    4. **Identification Completeness** (15%): Is the argument from model + assumptions
       to estimability complete, non-circular, and free of logical gaps?

    5. **Variance and SE Validity** (15%): Is the variance formula correctly derived?
       Is the proposed SE estimator consistent? Does it account for data structure
       (clustering, censoring, correlation, plug-in components)?

    6. **Simulation Coherence** (5%): Does the described DGP faithfully instantiate
       the model assumptions, making the claimed properties verifiable?

    7. **Regularity Conditions** (5%): For asymptotic results, are the relevant
       regularity conditions checked, cited, or explicitly assumed?

    **OVERALL SCORE** (1–10): Weighted average using the percentages above.

    For each dimension scoring < 7, provide:
    - The specific gap or error (quote the exact step or equation)
    - A concrete correction (corrected equation, missing assumption statement, etc.)
    - Priority: CRITICAL / IMPORTANT / MINOR

    Then add:
    - **Hidden Assumptions**: Any unstated conditions the derivation implicitly requires.
    - **Drift Warning**: "NONE" if the derivation targets the stated estimand; otherwise describe.
    - **Verdict**: CORRECT / REVISE / REDERIVE

    Verdict rule:
    - CORRECT: overall >= 9, no errors or hidden assumptions, derivation is implementation-ready.
    - REVISE: direction is valid but specific steps need correction or clarification.
    - REDERIVE: a fundamental step (identification, key expectation, variance structure) is wrong.
```
````

`new_string`:

````
```
mcp__codex__codex:
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [REVIEWER_PROMPT below]
```
````

- [ ] **Step 3: Verify the persona line moved, not vanished**

Run:
```bash
grep -cn 'You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: **1** — the Phase 4 subagent branch persona remains (permanent fixture). The Phase 2 Codex inline persona is gone; it will be re-inserted into the downstream section in Task 3. Between Task 1 and Task 3, count is 1 — this is fine.

Run:
```bash
grep -n 'REVIEWER_PROMPT below' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: at least one match (the new Codex stub).

- [ ] **Step 4: Do NOT commit yet** — Task 1 alone leaves the file in a broken state (prompt text is missing entirely). Commit happens after Task 3.

---

### Task 2: Trim the subagent branch stub suffix

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` (lines ~288–293, the fenced `Agent:` block in the `#### If backend = subagent` section of Phase 2)

- [ ] **Step 1: Confirm the target line exists**

Run:
```bash
grep -n 'REVIEWER_PROMPT below — same text as Codex branch' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: exactly **one** match.

- [ ] **Step 2: Apply the Edit**

Use the `Edit` tool on `.claude/skills/method-derive/SKILL.md`.

`old_string`:
```
    [REVIEWER_PROMPT below — same text as Codex branch]
```

`new_string`:
```
    [REVIEWER_PROMPT below]
```

(Four-space leading indent is preserved because the stub sits inside a `prompt: |` YAML block.)

- [ ] **Step 3: Verify**

Run:
```bash
grep -c 'REVIEWER_PROMPT below — same text as Codex branch' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: **0**.

Run:
```bash
grep -cn 'REVIEWER_PROMPT below' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: **2** matches (Codex stub from Task 1 + subagent stub).

---

### Task 3: Replace the downstream pointer section with the full prompt body

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` (the `#### REVIEWER_PROMPT (shared by both backends)` section, lines ~309–313)

- [ ] **Step 1: Confirm the target pointer paragraph still exists**

Run:
```bash
grep -n 'unchanged from prior versions' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: exactly **one** match, inside the downstream `#### REVIEWER_PROMPT` section.

- [ ] **Step 2: Apply the Edit**

Use the `Edit` tool on `.claude/skills/method-derive/SKILL.md`.

`old_string` (the full current pointer paragraph — one blank line and one text paragraph between the header and the next `**CRITICAL` bold):

```
#### REVIEWER_PROMPT (shared by both backends)

The prompt body — persona, 7-dimension scoring rubric, verdict rules, output format — is unchanged from prior versions. It is the text that already appears above in the Codex branch after the `prompt: |` line.
```

`new_string` (header + fenced prompt body — text is verbatim from the pre-Task-1 Codex inline, with the 4-space YAML indent stripped):

````
#### REVIEWER_PROMPT (shared by both backends)

```
You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)
with deep expertise in survival analysis, semiparametric estimation, recurrent
event methods, missing data, and pseudo-observation theory.

This is an early-stage mathematical derivation of a new statistical estimator.

Your job is to stress-test whether:
(1) The estimand is precisely defined and the derivation targets it exactly.
(2) All identifying assumptions are explicitly stated and are sufficient.
(3) Every algebraic and probabilistic step is mathematically valid.
(4) The identification argument is complete and non-circular.
(5) The variance/SE formula is correctly derived and consistently estimable.

Review principles:
- Prefer the minimal necessary assumption set. If an assumption is unnecessary,
  flag it as over-stated, not as missing.
- Flag every gap in reasoning, even if the conclusion is probably correct.
- Make implicit assumptions explicit rather than assuming the author intended them.
- Do not suggest alternative estimands or methods unless the derivation is
  fundamentally broken.
- Drift: if the derivation implicitly estimates something other than the stated
  estimand, call it out explicitly.

=== DERIVATION ===
[Paste FULL derivation from Phase 1]
=== END DERIVATION ===

Score these 7 dimensions from 1–10:

1. **Estimand Fidelity** (15%): Is the target quantity precisely defined?
   Does the estimator provably estimate exactly that quantity?

2. **Assumption Sufficiency** (20%): Are all identifying assumptions explicitly
   stated? Are they the minimal necessary set? Any hidden conditions?

3. **Mathematical Correctness** (25%): Are all algebraic, probabilistic, and
   calculus steps valid? Are expectations, variances, and limits correct?

4. **Identification Completeness** (15%): Is the argument from model + assumptions
   to estimability complete, non-circular, and free of logical gaps?

5. **Variance and SE Validity** (15%): Is the variance formula correctly derived?
   Is the proposed SE estimator consistent? Does it account for data structure
   (clustering, censoring, correlation, plug-in components)?

6. **Simulation Coherence** (5%): Does the described DGP faithfully instantiate
   the model assumptions, making the claimed properties verifiable?

7. **Regularity Conditions** (5%): For asymptotic results, are the relevant
   regularity conditions checked, cited, or explicitly assumed?

**OVERALL SCORE** (1–10): Weighted average using the percentages above.

For each dimension scoring < 7, provide:
- The specific gap or error (quote the exact step or equation)
- A concrete correction (corrected equation, missing assumption statement, etc.)
- Priority: CRITICAL / IMPORTANT / MINOR

Then add:
- **Hidden Assumptions**: Any unstated conditions the derivation implicitly requires.
- **Drift Warning**: "NONE" if the derivation targets the stated estimand; otherwise describe.
- **Verdict**: CORRECT / REVISE / REDERIVE

Verdict rule:
- CORRECT: overall >= 9, no errors or hidden assumptions, derivation is implementation-ready.
- REVISE: direction is valid but specific steps need correction or clarification.
- REDERIVE: a fundamental step (identification, key expectation, variance structure) is wrong.
```
````

- [ ] **Step 3: Verify the prompt body is present exactly once in Phase 2**

Run:
```bash
grep -cn 'You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: **2** — one in the newly extracted Phase 2 `#### REVIEWER_PROMPT` section, and one in the Phase 4 subagent branch (permanent fixture, explained in Task 1 Step 1). Trajectory: was 2 before Task 1, 1 after Task 1, 2 after Task 3.

Run:
```bash
grep -c 'unchanged from prior versions' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: **0** (pointer paragraph is gone).

---

### Task 4: Structural parity verification

**Files:** Read-only check on `.claude/skills/method-derive/SKILL.md`.

- [ ] **Step 1: Phase 2 and Phase 4 should show isomorphic grep signatures**

Run:
```bash
grep -n 'REVIEWER_PROMPT\|ROUND_N_PROMPT\|^### Phase [24]\|^#### If backend\|^#### USER_FOCUS' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected pattern — Phase 2 and Phase 4 each show:
- one `### Phase N:` heading
- one preamble line mentioning `REVIEWER_PROMPT` / `ROUND_N_PROMPT`
- `#### If backend = codex`
- `#### If backend = subagent`
- `#### USER_FOCUS injection`
- `#### REVIEWER_PROMPT` / `#### ROUND_N_PROMPT`

The section sequence should be visually identical between the two phases.

- [ ] **Step 2: Prompt-body uniqueness check**

Run:
```bash
grep -cn 'Estimand Fidelity' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: **2** — one in the extracted Phase 2 `#### REVIEWER_PROMPT` (scoring rubric), and one in the Phase 3 score-history table header (`| Round | Estimand Fidelity | Assumption Sufficiency | ...`). The single-source-of-truth property for the rubric is preserved: only the rubric *body* appears once (inside REVIEWER_PROMPT); the other match is a bare table column header.

Run:
```bash
grep -cn 'Round N re-evaluation' "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: **2** — one inside the Phase 4 `ROUND_N_PROMPT` extracted block, and one inside Phase 4's USER_FOCUS injection prose (*"before the `[Round N re-evaluation]` line"*). Both are pre-existing and untouched by this refactor.

- [ ] **Step 3: Spot-read both phases**

Read lines ~200–320 and ~393–485 and confirm: section ordering identical, Codex and subagent branches are thin stubs in both, extracted `#### <PROMPT_NAME>` section contains a triple-backtick fenced block in both.

- [ ] **Step 4: Total line count sanity**

Run:
```bash
wc -l "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/method-derive/SKILL.md"
```
Expected: within ±5 lines of the pre-edit count (~749). The prompt body (~77 lines) moves rather than appears or disappears.

---

### Task 5: Commit

**Files:** `.claude/skills/method-derive/SKILL.md` plus the two plan files from this session.

- [ ] **Step 1: Confirm working tree state**

Run:
```bash
git -C "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research" status --short .claude/skills/method-derive/SKILL.md quality_reports/plans/2026-04-20_method-derive-phase2-harmonize.md quality_reports/plans/2026-04-20_method-derive-phase2-harmonize-plan.md
```
Expected: SKILL.md shows `M`, both plan files show `??` or `A`.

- [ ] **Step 2: Ask the user to confirm the commit**

Pause and ask: "Ready to commit Phase 2 harmonization + spec + plan? (y/n)"

Only proceed on explicit approval — per the global CLAUDE.md rule to ask before committing.

- [ ] **Step 3: Stage and commit (only after approval)**

Run:
```bash
git -C "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research" add .claude/skills/method-derive/SKILL.md quality_reports/plans/2026-04-20_method-derive-phase2-harmonize.md quality_reports/plans/2026-04-20_method-derive-phase2-harmonize-plan.md
```

Then:
```bash
git -C "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research" commit -m "$(cat <<'EOF'
refactor(skill): harmonize method-derive Phase 2 prompt layout with Phase 4

Extracts REVIEWER_PROMPT into a single downstream section (triple-backtick
fence, matching ROUND_N_PROMPT's pattern in Phase 4). Both Codex and subagent
branches become thin "[REVIEWER_PROMPT below]" stubs. Prompt text, scoring
rubric, and runtime behavior are byte-identical.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Verify commit**

Run:
```bash
git -C "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research" log -1 --stat
```
Expected: a single new commit touching SKILL.md and the two plan files.

---

## Self-Review

**Spec coverage:**
- Spec §4 Edit 1 → Task 1. ✓
- Spec §4 Edit 2 → Task 2. ✓
- Spec §4 Edit 3 → Task 3. ✓
- Spec §4 Edit 4 (checkpoint tail — no change) → not a task; explicitly noted as untouched. ✓
- Spec §7 verification plan → Task 4. ✓

**Placeholder scan:** no "TBD" / "TODO" / "handle edge cases" / "similar to Task N" in the plan. Each step shows the exact Edit payload or exact shell command.

**Type consistency:** stub wording is `[REVIEWER_PROMPT below]` everywhere (Tasks 1, 2 both target this exact string). Section header `#### REVIEWER_PROMPT (shared by both backends)` appears in Task 3 exactly as the pre-edit file already spells it.

**Cross-task string reuse:** Task 1's `new_string` stub and Task 2's `new_string` stub both end with `[REVIEWER_PROMPT below]` (no trailing suffix). Task 3's extracted body matches Task 1's removed body byte-for-byte after stripping the 4-space YAML indent.

**Known pre-existing duplicate (not a bug):** The persona line `"You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)"` exists in Phase 2 (Codex inline, then moves to extracted section) **and** in Phase 4's subagent branch. Phase 4's subagent branch restates the persona every round because subagents are stateless between calls (unlike the Codex branch, which carries persona via `threadId`). This is intentional, out of scope for the current refactor, and causes all grep counts of the persona line to carry a permanent +1 offset from what you'd naïvely expect for a Phase-2-only analysis.

---

**Plan complete and saved to `quality_reports/plans/2026-04-20_method-derive-phase2-harmonize-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
