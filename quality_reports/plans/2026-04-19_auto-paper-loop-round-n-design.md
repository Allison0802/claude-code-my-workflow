# Design: Make `auto-paper-improvement-loop` Robust to MAX_ROUNDS > 2

**Date:** 2026-04-19  
**Skill:** `.claude/skills/auto-paper-improvement-loop/SKILL.md`  
**Status:** APPROVED

---

## Problem

The skill has `MAX_ROUNDS` as a user-configurable constant, but steps 5–7 are hardcoded for "Round 2." Running with `MAX_ROUNDS = 3` would:

- **CRITICAL:** Overwrite `main_round2.pdf` with Round 3 results (Step 7: `cp main.pdf main_round2.pdf`)
- **MAJOR:** Send `[Round 2 update]` label to reviewer on Round 3+ (confusing)
- **MAJOR:** Step 5b checkpoint message hardcodes "Round 2"
- **MAJOR:** Subagent context embedding rule undefined for Round N ≥ 3
- **MINOR:** Subagent description `"Paper review round 2"` hardcoded
- **MINOR:** Output section lists only round0/round1/round2 PDFs

---

## Approach: Collapse Round N ≥ 2 into a Single Loop Body

Round 1 is genuinely different (cold start, full paper sent for the first time, no prior context). Keep Steps 1–4 as-is.

Replace Steps 5–7 with a single **"Round N Loop Body (N = 2 to MAX_ROUNDS)"** section, parameterized by N. All rounds N ≥ 2 execute the same section.

---

## Design

### 1. Structural Reorganization

```
Step 0–1:   Setup + collect paper text
Step 1.5:   Logic flow pre-pass (Round 1)
Steps 2–4:  Round 1 → review → checkpoint → fix → recompile

[Loop N = 2 to MAX_ROUNDS]:
  Step R.0   Re-collect paper text
  Step 1.5   Logic flow pre-pass (Round N)
  Step N.1   Round N review
  Step N.2   Human checkpoint (if enabled)
  Step N.3   Implement Round N fixes
  Step N.4   Recompile Round N

Steps 8–10: Format check → document → summary
```

### 2. Changes Inside the Loop Body

#### Labels and descriptions
- ROUND_N_PROMPT header: `[Round 2 update]` → `[Round N update]`
- Subagent `description`: `"Paper review round 2"` → `"Paper review round N"`
- Step N.2 checkpoint message: `"Round 2 review complete"` → `"Round N review complete"`

#### Subagent context embedding (option C: summaries of older rounds + full most recent)

For Round N ≥ 2, the subagent prompt structure:

```
## Context: You have reviewed this paper across N-1 previous rounds.

### Summaries of Rounds 1 through N-2:        ← omitted entirely when N=2
**Round k (Score: X/10):** [3-sentence summary: key weaknesses + fixes applied]
...

### Your Most Recent Review (Round N-1, verbatim):
[full review text]

### Fixes Implemented Since Round N-1:
[list of fixes]

[ROUND_N_PROMPT]
```

When N=2, the "Summaries" block is absent — degrades gracefully to current Round 2 behavior.

**Source of summaries:** Read `PAPER_IMPROVEMENT_LOG.md` before each Round N ≥ 3 subagent call. Extract score, verdict, and fixes-implemented list for rounds 1..N-2. Generate a 3-sentence summary per round from that data. No new state to persist.

The Codex (`codex-reply`) path is unchanged — threadId carries full context natively.

#### Recompile (critical fix)

```bash
cp main.pdf main_round${N}.pdf
```

Replaces hardcoded `cp main.pdf main_round2.pdf`.

### 3. Output Section

```
paper/
├── main_round0_original.pdf     # Original
├── main_round1.pdf              # After Round 1
├── main_round2.pdf              # After Round 2
├── ...
├── main_round{MAX_ROUNDS}.pdf   # After final round
├── main.pdf                     # = main_round{MAX_ROUNDS}.pdf
└── PAPER_IMPROVEMENT_LOG.md
```

### 4. Log Template (Step 9)

Replace the hardcoded Round 1 / Round 2 sections + trailing `> For MAX_ROUNDS > 2` note with a single loop pattern:

```markdown
## Round N Review & Fixes    ← repeat for N = 1 to MAX_ROUNDS

### Logic Flow Pre-Analysis (Round N)
[FLOW_PREPASS_OUTPUT_RN verbatim — or failure/disabled message]

<details>
<summary>[Backend] Review (Round N)</summary>
[Full raw review text, verbatim]
</details>

### Fixes Implemented
1. [Fix] — NotebookLM: [notebook] — [finding] (if consulted)
```

Score Progression table in Step 10 — example updated to show 3 rounds.

---

## What Does NOT Change

- Steps 0–4 (Round 1): unchanged
- Step R.0: already generalized, no changes
- Step 1.5: already generalized, no changes  
- Step 8 (Format Check): unchanged
- Step 10 (Summary): example table gains a third row, no structural change
- All constants, reviewer persona, fix patterns, NotebookLM protocol: unchanged

---

## Files to Modify

- `.claude/skills/auto-paper-improvement-loop/SKILL.md` — one file, surgical edits
