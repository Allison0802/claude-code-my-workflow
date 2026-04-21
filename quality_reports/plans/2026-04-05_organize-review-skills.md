# Organize Review Skills — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce 9 review-related skills to a coherent set with a single `/review` entry point, one deletion, and a rewritten CLAUDE.md review section.

**Architecture:** Add a `/review` dispatcher skill that routes by file type. Delete the MiniMax variant (covered by the LLM variant). Rewrite the CLAUDE.md commands section to group skills by use case with "when to use" guidance.

**Tech Stack:** Claude Code skills (SKILL.md frontmatter + markdown), CLAUDE.md config

---

## Inventory (for reference)

| Skill | Touchable? | Action |
|-------|-----------|--------|
| `review-r` | yes (project) | keep as-is |
| `review-paper` | yes (project) | keep as-is |
| `lit-review` | yes (project) | keep; clarify in CLAUDE.md it's search, not review |
| `auto-review-loop` | yes (project) | keep; rename description for clarity |
| `auto-review-loop-llm` | yes (project) | keep |
| `auto-review-loop-minimax` | yes (project) | **DELETE** — fully covered by `-llm` |
| `research-review` | yes (project) | keep; description update for clarity |
| `plan-review-loop` | global | untouched |
| `code-review:code-review` | global plugin | untouched |

---

## Task 1: Create `/review` dispatcher skill

**Files:**
- Create: `.claude/skills/review/SKILL.md`

- [ ] **Step 1: Create the skill file**

```markdown
---
name: review
description: Smart review dispatcher. Routes to the right reviewer based on file type or content: .R files → review-r (r-reviewer agent), .tex files → review-paper (6-dimension referee review), research ideas/content → research-review (interactive Codex MCP). Use this as your default entry point for any review task.
disable-model-invocation: true
argument-hint: "[filename.R | filename.tex | 'research idea or content description']"
allowed-tools: ["Read", "Grep", "Glob", "Task"]
---

# Review Dispatcher

Route to the correct reviewer based on what you are reviewing.

## Routing Logic

Parse `$ARGUMENTS`:

### If argument ends in `.R` or matches a path to an R script:
→ Invoke the **`review-r`** skill with the same argument.
- Checks: code quality, reproducibility, domain correctness, figure standards
- Output: `quality_reports/[script_name]_r_review.md`

### If argument ends in `.tex` or matches a path to a LaTeX manuscript:
→ Invoke the **`review-paper`** skill with the same argument.
- Checks: argument structure, statistical methodology, estimation, literature, writing, presentation
- Output: `quality_reports/paper_review_[name].md`

### If argument is a research idea, results, or plain text description:
→ Invoke the **`research-review`** skill with the same argument.
- Interactive multi-round review via Codex MCP with dialogue
- No file output (interactive session)

### If no argument is provided:
Ask the user: "What would you like to review? Provide a filename (.R or .tex) or a description of your research idea."

## Notes

- For **autonomous iterative improvement** (review + auto-fix loop): use `/auto-review-loop` directly
- For **PR/git review**: use `/code-review:code-review` directly
- For **plan review and rewrite loop**: use `/plan-review-loop` directly
```

- [ ] **Step 2: Verify the file exists**

```bash
ls .claude/skills/review/SKILL.md
```
Expected: file found

---

## Task 2: Delete `auto-review-loop-minimax`

`auto-review-loop-minimax` uses MiniMax API. `auto-review-loop-llm` already supports any OpenAI-compatible API endpoint — MiniMax included. There is no reason to maintain a separate skill.

**Files:**
- Delete: `.claude/skills/auto-review-loop-minimax/` (entire directory)

- [ ] **Step 1: Delete the directory**

```bash
rm -rf .claude/skills/auto-review-loop-minimax/
```

- [ ] **Step 2: Verify it's gone and other loop skills remain**

```bash
ls .claude/skills/ | grep auto-review
```
Expected output:
```
auto-review-loop
auto-review-loop-llm
```
(`auto-review-loop-minimax` must NOT appear)

---

## Task 3: Rewrite CLAUDE.md review section

Replace the scattered review commands across multiple tables with a single organized "Review" section that groups by use case and explains when to use each.

**Files:**
- Modify: `CLAUDE.md`

First, read the current state of the review-related lines in CLAUDE.md:

- [ ] **Step 1: Locate the exact text to replace**

Find the "Writing & Manuscript" table and "Review & QA" table. The review commands are currently split across both sections. Replace both with the structure below.

The "Writing & Manuscript" section currently contains:
```
| `/proofread [file]` | Grammar/typo review |
| `/review-paper [file]` | Deep manuscript review |
```

The "Review & QA" section currently contains:
```
| `/research-review [file]` | Deep critical review via GPT/Codex |
| `/auto-review-loop [file]` | Autonomous multi-round review → fix loop |
| `/auto-review-loop-llm [file]` | Same, using any OpenAI-compatible LLM API |
| `/proof-writer [theorem]` | Write rigorous mathematical proofs |
| `/research-pipeline [topic]` | Full pipeline: idea discovery → implementation → review |
```

- [ ] **Step 2: Remove `/proofread` and `/review-paper` from Writing & Manuscript table**

In the Writing & Manuscript table, remove these two rows:
```
| `/proofread [file]` | Grammar/typo review |
| `/review-paper [file]` | Deep manuscript review |
```

- [ ] **Step 3: Replace the Review & QA section entirely**

Replace:
```markdown
### Review & QA

| Command | What It Does |
|---------|-------------|
| `/research-review [file]` | Deep critical review via GPT/Codex |
| `/auto-review-loop [file]` | Autonomous multi-round review → fix loop |
| `/auto-review-loop-llm [file]` | Same, using any OpenAI-compatible LLM API |
| `/proof-writer [theorem]` | Write rigorous mathematical proofs |
| `/research-pipeline [topic]` | Full pipeline: idea discovery → implementation → review |
```

With:
```markdown
### Review & QA

**Use `/review [file-or-topic]` as your default.** It routes automatically:

| Command | When to Use |
|---------|-------------|
| `/review [file or topic]` | **Default entry point** — routes to right reviewer by file type |
| `/review-r [file.R]` | R code quality, reproducibility, domain correctness |
| `/review-paper [file.tex]` | LaTeX manuscript: argument, stats, estimation, writing (referee-style) |
| `/proofread [file]` | Grammar, typos, overflow, consistency only |
| `/research-review [topic]` | Interactive Codex MCP review with back-and-forth dialogue |
| `/auto-review-loop [file]` | Autonomous: Codex reviews → Claude implements fixes → repeat (4 rounds) |
| `/auto-review-loop-llm [file]` | Same, using any OpenAI-compatible API (set endpoint in config) |
| `/code-review:code-review` | PR review: 5 parallel agents → posts high-confidence issues to GitHub |
| `/plan-review-loop [plan]` | Iterate review→rewrite a plan until it passes criteria |
| `/proof-writer [theorem]` | Write rigorous mathematical proofs |
| `/research-pipeline [topic]` | Full pipeline: idea discovery → implementation → review |

> **Note:** `/lit-review` is a search/synthesis tool (not a review) — see Literature & Ideas section.
```

- [ ] **Step 4: Verify CLAUDE.md renders cleanly**

```bash
grep -n "review" CLAUDE.md | head -40
```
Check: no orphaned `/review-paper` or `/proofread` in Writing & Manuscript, correct new section in Review & QA.

---

## Task 4: Session log

**Files:**
- Append to: `quality_reports/session_logs/2026-04-05_merge-review-skills.md`

- [ ] **Step 1: Append to today's session log**

Add these lines to the existing `quality_reports/session_logs/2026-04-05_merge-review-skills.md`:

```
- [12:30] `.claude/skills/review/SKILL.md` — created: dispatch router for .R → review-r, .tex → review-paper, else → research-review
- [12:30] `.claude/skills/auto-review-loop-minimax/` — deleted: fully covered by auto-review-loop-llm
- [12:30] `CLAUDE.md` — rewrote Review & QA section with grouped "when to use" guidance; moved /proofread and /review-paper from Writing table into Review section
```

---

## Verification

After all tasks complete:

1. `ls .claude/skills/review/SKILL.md` → exists
2. `ls .claude/skills/ | grep minimax` → empty (deleted)
3. `grep -c "Default entry point" CLAUDE.md` → 1
4. `grep "auto-review-loop-minimax" CLAUDE.md` → 0 results
5. `grep "lit-review" CLAUDE.md` → appears only in Literature & Ideas section with the note "search/synthesis tool"

---

## Net result

| Before | After |
|--------|-------|
| 9 visible review skills with no clear entry point | 1 dispatcher + 8 underlying skills |
| `auto-review-loop-minimax` redundant | Deleted |
| Review commands split across Writing and Review tables | Single organized Review section |
| `lit-review` listed among review skills | Clarified as search tool in correct section |
