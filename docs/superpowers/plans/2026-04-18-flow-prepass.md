# Flow Pre-Pass for `auto-paper-improvement-loop` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional logic flow pre-pass subagent to `.claude/skills/auto-paper-improvement-loop/SKILL.md` that reverse-outlines the paper at paragraph and section levels before every review round, with a `FLOW_PREPASS` toggle. The pre-pass procedure itself is described in a generalized, round-agnostic way (works for any MAX_ROUNDS). Note: the existing review workflow (Steps 2, 5, 6, 7) remains 2-round hardcoded — extending it beyond 2 rounds is out of scope for this plan.

**Architecture:** All changes are edits to a single Markdown file (`SKILL.md`). Two new **generalized** procedures are inserted (one pre-pass step, one paper re-collection step) that are described once and apply to every round. One new constant is added. Two existing templates (log, HUMAN_CHECKPOINT) are updated with Round N placeholders. No new files created.

**Tech Stack:** Markdown (skill file), Bash grep for verification.

**Key design decisions:**
- Pre-pass runs before **every** review round (Round 1 through Round MAX_ROUNDS), not just the first two.
- Paper text re-collection runs before every round **after the first** (N ≥ 2), not just before Round 2.
- The pre-pass and re-collection procedures are described **once** in SKILL.md using "Round N" language; the main review loop references them.
- Injection rules branch on (a) backend (Codex vs. subagent) and (b) whether N == 1 or N ≥ 2.
- Failure policy for the pre-pass is uniform across rounds: log the failure and proceed without the pre-pass output. Never abort.

**Hard constraints (do not drop):**
- Only `SKILL.md` is modified. No new files.
- `FLOW_PREPASS` toggle (default `true`) gates the pre-pass for all rounds.
- Pre-pass uses `model: "opus"` (never omit).
- Pre-pass output is stored in runtime variable `FLOW_PREPASS_OUTPUT_RN`, where `N` is the current round number (e.g., `FLOW_PREPASS_OUTPUT_R1`, `FLOW_PREPASS_OUTPUT_R2`, `FLOW_PREPASS_OUTPUT_R3`, ...).
- All SKILL.md edits use exact "Find this exact text / Replace with" anchors — no prose-based insertion.

---

### Task 1: Capture Pre-Edit Reference State

**Purpose:** Snapshot the file so all subsequent Find/Replace anchors are known to exist.

- [ ] **Step 1:** Read the current `.claude/skills/auto-paper-improvement-loop/SKILL.md` in full. Confirm the following anchors are present verbatim (record line numbers):
  - `- **MAX_ROUNDS = 2**` (Markdown Constants bullet)
  - `> 💡 Override:` (override example line)
  - `- **HUMAN_CHECKPOINT = false**` (Markdown Constants bullet)
  - `- **NOTEBOOKLM_NOTEBOOKS**` (Markdown Constants bullet — used as anchor boundary)
  - `### Step 1: Collect Paper Text`
  - `done > /tmp/paper_full_text.txt` (end of Step 1 bash block)
  - `### Step 2: Round 1 Review`
  - `Verify: 0 undefined references, 0 undefined citations.` (end of Step 4)
  - `### Step 5: Round 2 Review`
  - `## Round 1 Review & Fixes` (inside Step 9 log template)
  - `## Round 2 Review & Fixes` (inside Step 9 log template)
  - `📋 Round 1 review complete.` (inside Step 2b HUMAN_CHECKPOINT block)
  - `#### ROUND_2_PROMPT (shared by both backends)` (Round 2 prompt label)

- [ ] **Step 2:** If any anchor is missing or the text differs, STOP and report the discrepancy. The remaining tasks depend on these exact strings.

---

### Task 2: Add `FLOW_PREPASS` Constant and Update Override Example

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Add FLOW_PREPASS constant after HUMAN_CHECKPOINT**

Find this exact text:

```
- **HUMAN_CHECKPOINT = false** — When `true`, pause after each round's review and present score + weaknesses to the user. The user can approve fixes, provide custom modification instructions, skip specific fixes, or stop early. When `false` (default), runs fully autonomously.
- **NOTEBOOKLM_NOTEBOOKS**
```

Replace with:

```
- **HUMAN_CHECKPOINT = false** — When `true`, pause after each round's review and present score + weaknesses to the user. The user can approve fixes, provide custom modification instructions, skip specific fixes, or stop early. When `false` (default), runs fully autonomously.
- **FLOW_PREPASS = true** — When `true` (default), spawn a logic flow pre-pass subagent before **every** review round (Round 1 through Round MAX_ROUNDS) to produce a section-level and paragraph-level reverse outline. Output is injected into the reviewer prompt as structural scaffolding. When `false`, skip the pre-pass for all rounds; reviewer prompts are byte-identical to current behavior.
- **NOTEBOOKLM_NOTEBOOKS**
```

- [ ] **Step 2: Update the override example**

Find this exact text:

```
> 💡 Override: `/auto-paper-improvement-loop "paper/" — human checkpoint: true, reviewer: subagent`
```

Replace with:

```
> 💡 Override: `/auto-paper-improvement-loop "paper/" — human checkpoint: true, reviewer: subagent, flow prepass: false`
```

- [ ] **Step 3: Verify**

```bash
grep -n "FLOW_PREPASS\|flow prepass" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: exactly **2** lines — one in the Constants list, one in the override example.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): add FLOW_PREPASS constant and override"
```

---

### Task 3: Insert Step 1.5 — Logic Flow Pre-Pass (Round N, generalized)

**Purpose:** Add one procedure, described once, that runs before every review round.

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Locate the insertion point**

```bash
grep -n "done > /tmp/paper_full_text.txt\|### Step 2: Round 1 Review" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: two lines. Step 1.5 inserts in the gap between them.

- [ ] **Step 2: Insert Step 1.5 using exact Find/Replace**

Find this exact text (the closing of Step 1's bash block and the opening of Step 2):

```
done > /tmp/paper_full_text.txt
```

followed immediately (within a few lines) by:

```
### Step 2: Round 1 Review
```

Perform the replacement: find the text block from the line after the bash closing fence through `### Step 2: Round 1 Review`, and insert Step 1.5 before `### Step 2`. Specifically, find:

```
### Step 2: Round 1 Review
```

Replace with:

`````
### Step 1.5: Logic Flow Pre-Pass (Round N)

**Applies to:** All rounds, Round 1 through Round MAX_ROUNDS. Runs after Step 1 (Round 1) or after Step R.0 paper re-collection (Round N ≥ 2).

**Skip entirely if `FLOW_PREPASS = false`.** When skipped, set `FLOW_PREPASS_OUTPUT_RN = ""` and proceed to the reviewer call for Round N with the prompt unchanged.

Spawn a pre-pass subagent. Save the full response as the runtime variable `FLOW_PREPASS_OUTPUT_RN` (where N is the current round number; e.g., `FLOW_PREPASS_OUTPUT_R1` in Round 1, `FLOW_PREPASS_OUTPUT_R3` in Round 3). This variable is **not** persisted to `PAPER_IMPROVEMENT_STATE.json` — it is regenerated fresh each round.

```
Agent:
  description: "Logic flow pre-pass (Round N)"
  model: "opus"
  prompt: |
    You are an expert academic editor specializing in scientific writing structure.
    Read the following biostatistics methodology paper and produce a structured
    logic flow analysis at two levels: section-to-section and paragraph-to-paragraph.

    ## Full Paper Text:
    [contents of /tmp/paper_full_text.txt]

    ## Output Format

    ### Section-Level Arc
    For each section, write one sentence describing what it argues or establishes.
    Then describe the logical connector to the next section (e.g., "motivates",
    "formalizes", "tests", "interprets", "extends"). Format:
      Introduction → [argues X] →(motivates)→
      Methods → [formalizes X as estimator Y] →(tested by)→
      Simulation → [tests Y under scenarios A/B/C] →(interpreted in)→
      Results → [shows Z] →(interpreted in)→
      Discussion → [claims W]

    ### Paragraph-Level Flow (per section)
    For each section, list each paragraph's main point in one clause, and note the
    logical link to the next paragraph (e.g., "extends", "contrasts", "justifies",
    "abrupt shift"). Flag any abrupt shifts.
    Format per section:
      [Section name]:
        P1: [argues X] →(extends to)→ P2: [formalizes Y] →(abrupt shift)→ P3: [introduces Z]

    ### Detected Breaks
    List any logic-flow problems found, in order of severity:
    - CRITICAL: A later section relies on something never established earlier
    - CRITICAL: A paragraph introduces a concept with no link to prior or next paragraph
    - MAJOR: A claim in one section is not supported or followed up in the next
    - MINOR: An abrupt paragraph transition with no bridging sentence

    Be specific: name the sections and paragraphs involved.

    Output the analysis only. Do not include any preamble, greeting, or closing remarks.
```

Note: CRITICAL/MAJOR/MINOR tags are **structural observations only** — advisory scaffolding. The reviewer assigns final fix severity.

**Injection into the reviewer prompt (by backend and round):**

- **Round 1, Codex backend:** Prepend `## Logic Flow Pre-Analysis\n[FLOW_PREPASS_OUTPUT_R1 verbatim]\n\n---\n` immediately before `## Full Paper Text` in the REVIEWER_PROMPT string. Skip if `FLOW_PREPASS_OUTPUT_R1` is empty.
- **Round 1, Subagent backend:** Same as Codex Round 1.
- **Round N ≥ 2, Codex backend (`codex-reply`):** Prepend `## Logic Flow Pre-Analysis (Round N)\n[FLOW_PREPASS_OUTPUT_RN verbatim]\n\n---\n` at the **top** of ROUND_N_PROMPT (there is no `## Full Paper Text` anchor in this path — the paper text is in thread history). This rule applies to **every** subsequent-round Codex call (Round 2, Round 3, Round 4, ...). Skip if `FLOW_PREPASS_OUTPUT_RN` is empty.
- **Round N ≥ 2, Subagent backend:** Insert the pre-analysis block between the "Fixes Implemented" list and the ROUND_N_PROMPT instructions. Skip if empty.

**Failure policy (applies to every round N):** If the pre-pass subagent errors or times out, log `"Flow pre-pass failed for Round N — proceeding with unchanged reviewer prompt"` to `PAPER_IMPROVEMENT_LOG.md` and set `FLOW_PREPASS_OUTPUT_RN = ""`. Continue the reviewer call for Round N without injection. Do not retry, do not abort.

### Step 2: Round 1 Review
`````

- [ ] **Step 3: Verify**

```bash
grep -n "Step 1.5\|FLOW_PREPASS_OUTPUT_RN\|advisory scaffolding\|every round\|Round 1 through Round MAX_ROUNDS" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: **≥ 4** lines.

- [ ] **Step 4: Verify step ordering**

```bash
grep -n "^### Step" .claude/skills/auto-paper-improvement-loop/SKILL.md | head -7
```

Expected: Step 0, Step 1, Step 1.5, Step 2, Step 2b, Step 3, Step 4.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): insert generalized Step 1.5 logic flow pre-pass (all rounds)"
```

---

### Task 4: Insert Step R.0 — Re-collect Paper Text (Round N ≥ 2)

**Purpose:** Before every round after the first, re-collect paper text from updated sources. Described once, applies to every N ≥ 2.

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Locate the insertion point**

```bash
grep -n "Verify: 0 undefined references, 0 undefined citations.\|### Step 5: Round 2 Review" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: two lines. Step R.0 inserts between them.

- [ ] **Step 2: Insert Step R.0**

Find this exact text:

```
Verify: 0 undefined references, 0 undefined citations.

### Step 5: Round 2 Review
```

Replace with:

`````
Verify: 0 undefined references, 0 undefined citations.

### Step R.0: Re-collect Paper Text (before Round N ≥ 2)

**Applies to:** Every round after the first — before Round 2, before Round 3, ..., before Round MAX_ROUNDS. Runs after the recompile step for Round N-1 and before Step 1.5 (pre-pass) for Round N.

**Always runs regardless of `FLOW_PREPASS`.** The reviewer for Round N must see the post-fix paper text whether or not the pre-pass is enabled.

Re-run the same collection loop from Step 1, overwriting `/tmp/paper_full_text.txt` with the updated sources:

```bash
for f in paper/sections/*.tex; do
    echo "% === $(basename $f) ==="
    cat "$f"
done > /tmp/paper_full_text.txt
```

**Failure policy:** If re-collection fails (e.g., missing section file), log `"Re-collection failed before Round N — using stale /tmp/paper_full_text.txt"` to `PAPER_IMPROVEMENT_LOG.md` and proceed with whatever text is at that path. Do not abort.

### Step 5: Round 2 Review
`````

- [ ] **Step 3: Verify**

```bash
grep -n "Step R.0\|Re-collect Paper Text\|before Round N\|regardless of.*FLOW_PREPASS" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: **≥ 4** lines.

- [ ] **Step 4: Verify ordering**

```bash
grep -n "^### Step" .claude/skills/auto-paper-improvement-loop/SKILL.md | grep -A2 -B1 "Step 4:"
```

Expected: Step 3, Step 4 (Recompile Round 1), Step R.0, Step 5 (four lines).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): insert generalized Step R.0 paper text re-collection (all rounds N>=2)"
```

---

### Task 5: Update Round N ≥ 2 Review Step to Reference Step R.0 and Step 1.5

**Purpose:** Make Round 2 (and every subsequent round) explicitly invoke the generalized procedures.

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Update the Round 2 review section header note**

Find this exact text (the opening of Step 5):

```
### Step 5: Round 2 Review

**Branch by `REVIEWER_BACKEND`:**
```

Replace with:

```
### Step 5: Round 2 Review

**Before this step:** Run Step R.0 (re-collect paper text) then Step 1.5 (logic flow pre-pass, if `FLOW_PREPASS = true`). These generalized procedures apply to every subsequent round (Round 2, Round 3, ..., Round MAX_ROUNDS). For rounds beyond Round 2, repeat the same sequence: recompile → Step R.0 → Step 1.5 → reviewer call.

**Branch by `REVIEWER_BACKEND`:**
```

- [ ] **Step 2: Update ROUND_2_PROMPT label to ROUND_N_PROMPT**

Find this exact text:

```
#### ROUND_2_PROMPT (shared by both backends)
```

Replace with:

```
#### ROUND_N_PROMPT (shared by both backends, applies to Round 2 and all subsequent rounds)
```

- [ ] **Step 3: Verify**

```bash
grep -n "ROUND_N_PROMPT\|Before this step.*Step R.0\|every subsequent round" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: **≥ 3** lines — ROUND_N_PROMPT heading, the "Before this step" note, and the "every subsequent round" phrase.

```bash
grep -c "ROUND_2_PROMPT" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: **0** (fully replaced).

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): generalize Round 2 review step to reference Step R.0 and Step 1.5 for all rounds"
```

---

### Task 6: Update Log Template and HUMAN_CHECKPOINT Template

**Files:**
- Modify: `.claude/skills/auto-paper-improvement-loop/SKILL.md`

- [ ] **Step 1: Prepend pre-analysis section to Round 1 log entry**

Find this exact text (inside the Step 9 log template):

```
## Round 1 Review & Fixes

<details>
<summary>[Backend] Review (Round 1)</summary>
```

Replace with:

```
## Round 1 Review & Fixes

### Logic Flow Pre-Analysis (Round 1)
[Full `FLOW_PREPASS_OUTPUT_R1` verbatim — or: `Flow pre-pass failed for Round 1 — proceeding with unchanged reviewer prompt.` if failed — or: `Flow pre-pass disabled (FLOW_PREPASS = false).` if toggled off]

<details>
<summary>[Backend] Review (Round 1)</summary>
```

- [ ] **Step 2: Prepend pre-analysis section to Round 2 log entry**

Find this exact text:

```
## Round 2 Review & Fixes

<details>
<summary>[Backend] Review (Round 2)</summary>
```

Replace with:

```
## Round 2 Review & Fixes

### Logic Flow Pre-Analysis (Round 2)
[Full `FLOW_PREPASS_OUTPUT_R2` verbatim — or failure/disabled message as above]

<details>
<summary>[Backend] Review (Round 2)</summary>
```

- [ ] **Step 3: Add a note for rounds beyond Round 2**

Find this exact text (immediately after the Round 2 block you just edited, and before the PDFs section):

```
## PDFs
```

Insert immediately before it:

```
> **For MAX_ROUNDS > 2:** For each additional round N (Round 3, Round 4, ...), append an analogous `## Round N Review & Fixes` section to this log, prepending `### Logic Flow Pre-Analysis (Round N)` with `FLOW_PREPASS_OUTPUT_RN` (or the appropriate failure/disabled message).

## PDFs
```

- [ ] **Step 4: Update HUMAN_CHECKPOINT summary block**

Find this exact text (Step 2b):

```
📋 Round 1 review complete.
```

Replace with:

```
📋 Round N review complete.
```

- [ ] **Step 5: Verify all template updates**

```bash
grep -n "Logic Flow Pre-Analysis\|FLOW_PREPASS_OUTPUT_R\|pre-pass disabled\|Round N review complete\|MAX_ROUNDS > 2" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: **≥ 8** lines.

```bash
grep -c "Round 1 review complete" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: **0** (replaced).

- [ ] **Step 6: Final structural verification**

```bash
grep -n "Step 1.5\|Step R.0\|FLOW_PREPASS" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: **≥ 8** lines — Step 1.5 heading and references, Step R.0 heading, FLOW_PREPASS constant, override, guards.

- [ ] **Step 7: Confirm no stale ROUND_2_PROMPT remains**

```bash
grep -c "ROUND_2_PROMPT" .claude/skills/auto-paper-improvement-loop/SKILL.md
```

Expected: **0**.

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/auto-paper-improvement-loop/SKILL.md
git commit -m "feat(skill): update log template and HUMAN_CHECKPOINT for generalized Round N pre-pass"
```

---

### Task 7: MAX_ROUNDS > 2 Sanity Trace

Mental execution check — no file edits needed.

- [ ] **Step 1: Trace MAX_ROUNDS = 4 with FLOW_PREPASS = true**

Verify the edited SKILL.md produces this runtime sequence:
- Round 1: Step 1 collects text → Step 1.5 pre-pass → `FLOW_PREPASS_OUTPUT_R1` → review → fixes → recompile
- Round 2: Step R.0 re-collects → Step 1.5 pre-pass → `FLOW_PREPASS_OUTPUT_R2` → review → fixes → recompile
- Round 3: Step R.0 re-collects → Step 1.5 pre-pass → `FLOW_PREPASS_OUTPUT_R3` → review → fixes → recompile
- Round 4: Step R.0 re-collects → Step 1.5 pre-pass → `FLOW_PREPASS_OUTPUT_R4` → review → fixes → recompile
- Log: `## Round 1`, `## Round 2`, `## Round 3`, `## Round 4` each with `### Logic Flow Pre-Analysis (Round N)`
- Checkpoint: "Round N review complete" (N=1,2,3,4)

If any step in this trace is not accounted for by the edited skill, return to the relevant task and fix before committing.

- [ ] **Step 2: Trace MAX_ROUNDS = 4 with FLOW_PREPASS = false**

Verify:
- Step R.0 still runs for Rounds 2, 3, 4 (it is `FLOW_PREPASS`-independent)
- Step 1.5 is skipped for all rounds
- Reviewer prompts are unmodified
- Log sections contain `Flow pre-pass disabled (FLOW_PREPASS = false).` in each `### Logic Flow Pre-Analysis` subsection

- [ ] **Step 3: If either trace exposes a gap, fix it before declaring done**

---

## Self-Review (spec coverage)

| Spec requirement | Covered by |
|---|---|
| FLOW_PREPASS constant | Task 2 Step 1 |
| Override example updated | Task 2 Step 2 |
| Pre-pass for ALL rounds (not just 1 and 2) | Task 3 Step 2 (Step 1.5 uses "Round N" language) |
| Round 1 injection (both backends) | Task 3 Step 2 |
| Round N≥2 Codex injection (all subsequent rounds) | Task 3 Step 2 |
| Round N≥2 subagent injection | Task 3 Step 2 |
| Failure policy (all rounds) | Task 3 Step 2 |
| Re-collection for ALL rounds N≥2 | Task 4 Step 2 (Step R.0) |
| Re-collection failure policy | Task 4 Step 2 |
| Round 2 step references Step R.0 + Step 1.5 | Task 5 Step 1 |
| ROUND_2_PROMPT → ROUND_N_PROMPT | Task 5 Step 2 |
| Log template Round 1 and Round 2 pre-pass sections | Task 6 Steps 1–2 |
| Log note for MAX_ROUNDS > 2 | Task 6 Step 3 |
| HUMAN_CHECKPOINT "Round N" | Task 6 Step 4 |
| MAX_ROUNDS > 2 trace verification | Task 7 |
