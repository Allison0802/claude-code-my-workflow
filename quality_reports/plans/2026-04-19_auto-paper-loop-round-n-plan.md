# Auto-Paper-Improvement-Loop: Round N Robustness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `.claude/skills/auto-paper-improvement-loop/SKILL.md` correctly handle MAX_ROUNDS > 2 by replacing hardcoded "Round 2" logic with a generalized "Round N" loop body.

**Architecture:** One file, surgical edits only. Round 1 steps (Steps 0–4) are untouched. Steps 5–7 are renamed and generalized into a "Round N Loop Body" section parameterized by N. No new files created.

**Tech Stack:** Markdown skill document — no compilation. Verification is grep-based before/after each edit.

---

## File Map

| File | Change |
|------|--------|
| `.claude/skills/auto-paper-improvement-loop/SKILL.md` | All edits — 8 targeted sections |

---

### Task 1: Add "Round N Loop Body" section header + rename Step 5 header

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Verify old text exists**

```bash
grep -n "Step 5: Round 2 Review" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: one match with line number.

- [ ] **Step 2: Add section header above Step R.0 and rename Step 5**

Insert a `## Round N Loop Body` header directly above the existing `### Step R.0` heading. Also update the "Before this step" note inside Step 5 that says "For rounds beyond Round 2, repeat..." — that note is now superseded by the section header.

Replace:
```
### Step R.0: Re-collect Paper Text (before Round N ≥ 2)
```
With:
```
## Round N Loop Body (N = 2 to MAX_ROUNDS)

`N` is the current round number. Execute this section for N = 2, 3, …, MAX_ROUNDS in sequence: re-collect → pre-pass → review → checkpoint → fix → recompile.

### Step R.0: Re-collect Paper Text (before Round N ≥ 2)
```

Then replace:
```
### Step 5: Round 2 Review

**Before this step:** Run Step R.0 (re-collect paper text) then Step 1.5 (logic flow pre-pass, if `FLOW_PREPASS = true`). These generalized procedures apply to every subsequent round (Round 2, Round 3, ..., Round MAX_ROUNDS). For rounds beyond Round 2, repeat the same sequence: recompile → Step R.0 → Step 1.5 → reviewer call.
```
With:
```
### Step N.1: Round N Review

**Before this step:** Run Step R.0 (re-collect paper text) then Step 1.5 (logic flow pre-pass, if `FLOW_PREPASS = true`).
```

- [ ] **Step 3: Verify**

```bash
grep -n "Round N Loop Body\|Step N.1: Round N Review" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: both strings found.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): add Round N Loop Body header, rename Step 5 to Step N.1"
```

---

### Task 2: Fix ROUND_N_PROMPT label + subagent description

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Verify old text**

```bash
grep -n "Round 2 update\|Paper review round 2" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: two matches.

- [ ] **Step 2: Replace ROUND_N_PROMPT header label**

Replace:
```
[Round 2 update]
```
With:
```
[Round N update]
```

- [ ] **Step 3: Replace subagent description**

Replace:
```
  description: "Paper review round 2"
```
With:
```
  description: "Paper review round N"
```

- [ ] **Step 4: Verify**

```bash
grep -n "Round 2 update\|Paper review round 2" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: zero matches.

```bash
grep -n "Round N update\|Paper review round N" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: two matches.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): parameterize ROUND_N_PROMPT label and subagent description with N"
```

---

### Task 3: Generalize subagent context embedding for Round N ≥ 2

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

This replaces the hardcoded "Round 1 context" embedding with the option-C template: summaries of rounds 1..N-2 (omitted when N=2) + full Round N-1 review verbatim.

- [ ] **Step 1: Verify old text**

```bash
grep -n "You previously reviewed this paper in Round 1" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: one match.

- [ ] **Step 2: Replace subagent context block**

Replace the entire subagent `#### If backend = subagent` block under Step N.1 (the part that spawns "Paper review round 2") with:

```
#### If backend = `subagent`

Spawn a new subagent with prior review context embedded (since subagents don't persist state).
For Round N = 2, the "Summaries" block is omitted — degrades gracefully to single-round context.
Before calling for Round N ≥ 3, read `PAPER_IMPROVEMENT_LOG.md` to extract the score, verdict, and
fixes-implemented list for rounds 1..N-2. Generate a 3-sentence summary per prior round from that data.

```
Agent:
  description: "Paper review round N"
  model: "opus"
  prompt: |
    You are a senior associate editor at Biometrics with expertise in survival analysis,
    recurrent events, competing risks, and semiparametric efficiency theory.

    ## Context: You have reviewed this paper across N-1 previous rounds.

    ### Summaries of Rounds 1 through N-2:
    [Omit this block entirely when N=2. For N≥3, for each round k from 1 to N-2:]
    **Round k (Score: X/10):** [3-sentence summary: key weaknesses identified + fixes applied]

    ### Your Most Recent Review (Round N-1, verbatim):
    [paste full Round N-1 review text]

    ### Fixes Implemented Since Round N-1:
    1. [Fix 1]: [description]
    2. [Fix 2]: [description]
    ...

    [ROUND_N_PROMPT below]
```
```

The exact old block to replace is:
```
#### If backend = `subagent`

Spawn a new subagent with full Round 1 context embedded (since subagents don't persist state):

```
Agent:
  description: "Paper review round 2"
  model: "opus"
  prompt: |
    You are a senior associate editor at Biometrics with expertise in survival analysis,
    recurrent events, competing risks, and semiparametric efficiency theory.

    ## Context: You previously reviewed this paper in Round 1.

    ### Your Round 1 Review (verbatim):
    [paste full Round 1 review text]

    ### Fixes Implemented Since Round 1:
    1. [Fix 1]: [description]
    2. [Fix 2]: [description]
    ...

    [ROUND_N_PROMPT below]
```
```

- [ ] **Step 3: Verify**

```bash
grep -n "You previously reviewed this paper in Round 1\|Round 1 Review (verbatim)" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: zero matches.

```bash
grep -n "Summaries of Rounds 1 through N-2\|Most Recent Review (Round N-1" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: two matches.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): generalize subagent context embedding to option-C (summaries + full recent)"
```

---

### Task 4: Fix Step N.2 checkpoint label + rename steps 5b, 6, 7

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Verify old text**

```bash
grep -n "Step 5b:\|Step 6:\|Step 7:\|present Round 2 review" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: four matches.

- [ ] **Step 2: Rename step headers and fix checkpoint message**

Replace:
```
### Step 5b: Human Checkpoint (if enabled)

**Skip if `HUMAN_CHECKPOINT = false`.** Same as Step 2b — present Round 2 review, wait for user input.
```
With:
```
### Step N.2: Human Checkpoint (if enabled)

**Skip if `HUMAN_CHECKPOINT = false`.** Same as Step 2b — present Round N review, wait for user input.
```

Replace:
```
### Step 6: Implement Round 2 Fixes
```
With:
```
### Step N.3: Implement Round N Fixes
```

Replace:
```
### Step 7: Recompile Round 2
```
With:
```
### Step N.4: Recompile Round N
```

- [ ] **Step 3: Verify**

```bash
grep -n "Step 5b:\|Step 6:\|Step 7:\|present Round 2 review" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: zero matches.

```bash
grep -n "Step N.2:\|Step N.3:\|Step N.4:\|present Round N review" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: four matches.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): rename steps 5b/6/7 to N.2/N.3/N.4 and fix checkpoint label"
```

---

### Task 5: Fix critical recompile cp command (overwrite bug)

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Verify old text**

```bash
grep -n "cp main.pdf main_round2.pdf" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: one match.

- [ ] **Step 2: Replace hardcoded round number**

Replace:
```
cp main.pdf main_round2.pdf
```
With:
```
cp main.pdf main_round${N}.pdf
```

- [ ] **Step 3: Verify**

```bash
grep -n "cp main.pdf main_round2.pdf" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: zero matches.

```bash
grep -n 'cp main.pdf main_round\${N}.pdf' .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: one match.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "fix(skill): parameterize recompile cp command to main_round\${N}.pdf"
```

---

### Task 6: Update output section to generalize PDF listing

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Verify old text**

```bash
grep -n "main_round2.pdf.*final\|= main_round2.pdf" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: matches in the Output section and the Step 9 PDFs list.

- [ ] **Step 2: Update Output section**

Replace:
```
paper/
├── main_round0_original.pdf    # Original
├── main_round1.pdf             # After Round 1
├── main_round2.pdf             # After Round 2 (final)
├── main.pdf                    # = main_round2.pdf
└── PAPER_IMPROVEMENT_LOG.md    # Full review log with scores
```
With:
```
paper/
├── main_round0_original.pdf         # Original
├── main_round1.pdf                  # After Round 1
├── main_round2.pdf                  # After Round 2
├── ...
├── main_round{MAX_ROUNDS}.pdf       # After final round
├── main.pdf                         # = main_round{MAX_ROUNDS}.pdf
└── PAPER_IMPROVEMENT_LOG.md         # Full review log with scores
```

- [ ] **Step 3: Update Step 9 PDFs list**

Replace:
```
## PDFs
- `main_round0_original.pdf` — Original generated paper
- `main_round1.pdf` — After Round 1 fixes
- `main_round2.pdf` — Final version after Round 2 fixes
```
With:
```
## PDFs
- `main_round0_original.pdf` — Original generated paper
- `main_round1.pdf` — After Round 1 fixes
- `main_round{k}.pdf` — After Round k fixes, for k = 2 to MAX_ROUNDS
- `main_round{MAX_ROUNDS}.pdf` — Final version
```

- [ ] **Step 4: Verify**

```bash
grep -n "= main_round2.pdf\|Final version after Round 2" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: zero matches.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): generalize output section PDF listing for MAX_ROUNDS > 2"
```

---

### Task 7: Replace hardcoded Round 1/2 log template with loop pattern

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Verify old text**

```bash
grep -n "## Round 1 Review & Fixes\|## Round 2 Review & Fixes\|For MAX_ROUNDS > 2" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: three matches.

- [ ] **Step 2: Replace the hardcoded Round 1 / Round 2 sections and trailing note**

Replace the entire block from `## Round 1 Review & Fixes` through the `> **For MAX_ROUNDS > 2:**` note with the loop pattern:

Old block:
```
## Round 1 Review & Fixes

### Logic Flow Pre-Analysis (Round 1)
[Full `FLOW_PREPASS_OUTPUT_R1` verbatim — or: `Flow pre-pass failed for Round 1 — proceeding with unchanged reviewer prompt.` if failed — or: `Flow pre-pass disabled (FLOW_PREPASS = false).` if toggled off]

<details>
<summary>[Backend] Review (Round 1)</summary>

[Full raw review text, verbatim — from GPT-5.4 xhigh or Claude subagent]

</details>

### Fixes Implemented
1. [Fix description] — NotebookLM: [notebook name] — [key finding] (if consulted)
2. [Fix description]
...

## Round 2 Review & Fixes

### Logic Flow Pre-Analysis (Round 2)
[Full `FLOW_PREPASS_OUTPUT_R2` verbatim — or failure/disabled message as above]

<details>
<summary>[Backend] Review (Round 2)</summary>

[Full raw review text, verbatim]

</details>

### Fixes Implemented
1. [Fix description] — NotebookLM: [notebook name] — [key finding] (if consulted)
2. [Fix description]
...

> **For MAX_ROUNDS > 2:** For each additional round N (Round 3, Round 4, ...), append an analogous `## Round N Review & Fixes` section to this log, prepending `### Logic Flow Pre-Analysis (Round N)` with `FLOW_PREPASS_OUTPUT_RN` (or the appropriate failure/disabled message).
```

New block:
```
## Round N Review & Fixes    ← repeat for N = 1 to MAX_ROUNDS

### Logic Flow Pre-Analysis (Round N)
[Full `FLOW_PREPASS_OUTPUT_RN` verbatim — or: `Flow pre-pass failed for Round N — proceeding with unchanged reviewer prompt.` if failed — or: `Flow pre-pass disabled (FLOW_PREPASS = false).` if toggled off]

<details>
<summary>[Backend] Review (Round N)</summary>

[Full raw review text, verbatim — from GPT-5.4 xhigh or Claude subagent]

</details>

### Fixes Implemented
1. [Fix description] — NotebookLM: [notebook name] — [key finding] (if consulted)
2. [Fix description]
...
```

- [ ] **Step 3: Verify**

```bash
grep -n "## Round 1 Review & Fixes\|## Round 2 Review & Fixes\|For MAX_ROUNDS > 2" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: zero matches.

```bash
grep -n "## Round N Review & Fixes" .claude/skills/auto-paper-improvement-loop/SKILL.md
```
Expected: one match.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): replace hardcoded Round 1/2 log template with generalized Round N loop pattern"
```

---

### Task 8: Final smoke-check

Verify no "Round 2" references remain in the generalized sections (Round 1-specific references are expected and correct — do not change those).

- [ ] **Step 1: Check for stray "Round 2" in loop body sections**

```bash
grep -n "Round 2" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected surviving references (these are correct — they describe Round 1 or examples):
- Step 5 (Round 2 Review) → now Step N.1, so "Round 2" should not appear in step names
- `main_round2.pdf` in the output/PDFs list → now generalized
- "Typical Score Progression" table at the bottom shows `Round 2 | 7/10 | ...` — this is an example row, acceptable to keep (it illustrates a 2-round run)
- `main_round2_review` or similar in key-rules section → check if any remain

If any stray "Round 2" references appear in step names, section headers, or the loop body description, fix them.

- [ ] **Step 2: Verify `ROUND_N_PROMPT` section heading**

```bash
grep -n "ROUND_N_PROMPT" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: the heading `#### ROUND_N_PROMPT (shared by both backends, applies to Round 2 and all subsequent rounds)` — update "applies to Round 2 and all subsequent rounds" to "applies to all rounds N ≥ 2".

Replace:
```
#### ROUND_N_PROMPT (shared by both backends, applies to Round 2 and all subsequent rounds)
```
With:
```
#### ROUND_N_PROMPT (shared by both backends, applies to all rounds N ≥ 2)
```

- [ ] **Step 3: Final verify**

```bash
grep -c "Round 2" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Review each remaining hit and confirm it is either:
- The "Typical Score Progression" example table (acceptable)
- A `main_round2.pdf` reference in the `Key Rules` section that was already updated
- A reference within Round 1's own steps that happens to say "Round 2" (should not exist)

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "fix(skill): clean up stray Round 2 references in ROUND_N_PROMPT heading"
```
