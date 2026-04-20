# method-derive Reviewer Fallback + USER_FOCUS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the `REVIEWER_BACKEND` subagent fallback and `USER_FOCUS` free-text instruction injection pattern from `auto-paper-improvement-loop` into `method-derive`, scoped to the math review loop (Phase 2 & Phase 4 only).

**Architecture:** Eight surgical edits to a single file (`.claude/skills/method-derive/SKILL.md`). Phase 6 `domain-reviewer` agent and all later phases remain untouched. Default behavior (empty `USER_FOCUS`, Codex available) is byte-identical to the pre-change skill. Verification is grep-based on the resulting Markdown, not test-driven in the code sense.

**Tech Stack:** Markdown edits to a Claude Code skill file; no runtime code changes.

**Spec:** [quality_reports/plans/2026-04-20_method-derive-reviewer-fallback.md](2026-04-20_method-derive-reviewer-fallback.md)

**Reference pattern:** [.claude/skills/auto-paper-improvement-loop/SKILL.md](../../.claude/skills/auto-paper-improvement-loop/SKILL.md)

---

## File Structure

**Modify (only):**
- `.claude/skills/method-derive/SKILL.md` — add two constants, an argument-parsing block, extend the reviewer-fallback line, extend state-persistence schema, add backend branches + USER_FOCUS injection blocks in Phase 2 and Phase 4, add three key-rule bullets, update the override example.

**Do NOT modify:**
- `.claude/rules/codex-fallback-protocol.md` — referenced only, no changes.
- `.claude/skills/auto-paper-improvement-loop/SKILL.md` — reference pattern, no changes.
- Any Phase 0, 1, 3, 5, 6, 7, 8, 9 content of method-derive.

---

## Pre-flight

- [ ] **Step P.1: Verify working tree is clean for SKILL.md**

Run: `git status .claude/skills/method-derive/SKILL.md`
Expected: `nothing to commit` or file shown as unstaged — both are acceptable. If file has uncommitted changes, ask user whether to stash or proceed on top.

- [ ] **Step P.2: Capture a baseline copy for the byte-identical verification in Task 9**

Run:
```bash
cp .claude/skills/method-derive/SKILL.md /tmp/method-derive-SKILL.md.baseline
wc -l /tmp/method-derive-SKILL.md.baseline
```
Expected: Baseline file exists; note the baseline line count for later comparison.

---

### Task 1: Add REVIEWER_BACKEND and USER_FOCUS constants

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md:36-49` (Constants block, inserting after line 47)

- [ ] **Step 1.1: Read the current Constants block**

Run: `sed -n '36,50p' .claude/skills/method-derive/SKILL.md`
Expected: you see lines 36–49 which list REVIEWER_MODEL, MAX_ROUNDS, SCORE_THRESHOLD, OUTPUT_DIR, PILOT_REPS, PILOT_N, BIAS_THRESHOLD, SE_RATIO_RANGE, COVERAGE_NOMINAL, COVERAGE_PILOT_RANGE, then the `> Override constants via argument …` line at 49.

- [ ] **Step 1.2: Insert two new bullets after the `COVERAGE_PILOT_RANGE` line (line 47), before the `> Override …` line**

Edit the file — find this exact block:
```
- **COVERAGE_PILOT_RANGE = [0.91, 0.99]** — Monte Carlo tolerance at B = 500

> Override constants via argument if needed, e.g. `-- pilot_n: 100, pilot_reps: 200`.
```

Replace with:
```
- **COVERAGE_PILOT_RANGE = [0.91, 0.99]** — Monte Carlo tolerance at B = 500
- **REVIEWER_BACKEND = `auto`** — Which reviewer to use for the math review loop (Phase 2 & Phase 4). Values: `auto` (detect Codex MCP at startup, fall back to Claude subagent), `codex` (force Codex MCP), `subagent` (force Claude subagent). See `.claude/rules/codex-fallback-protocol.md`. Phase 6's `domain-reviewer` agent is unaffected.
- **USER_FOCUS = `""`** — Free-text user directive that biases the math reviewer's attention (e.g., "scrutinize the sandwich variance derivation most heavily"). When non-empty, injected verbatim into **every** round's reviewer prompt (Phase 2 Round 1 through Phase 4 Round MAX_ROUNDS) so the user's focus persists across the full loop. Set via arguments (see parsing below) or omit for default reviewer behavior.

> Override constants via argument if needed, e.g. `-- pilot_n: 100, pilot_reps: 200, reviewer: subagent, focus: "scrutinize the sandwich variance derivation most heavily"`.
```

- [ ] **Step 1.3: Verify both constants landed**

Run:
```bash
grep -c '^- \*\*REVIEWER_BACKEND = `auto`\*\*' .claude/skills/method-derive/SKILL.md
grep -c '^- \*\*USER_FOCUS = `""`\*\*' .claude/skills/method-derive/SKILL.md
grep -c 'reviewer: subagent, focus:' .claude/skills/method-derive/SKILL.md
```
Expected: `1`, `1`, `1`.

---

### Task 2: Add "Argument Parsing for USER_FOCUS" block

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` — insert new subsection right after the updated `> Override constants …` line from Task 1, before the existing `Reviewer fallback & NotebookLM:` line.

- [ ] **Step 2.1: Locate the anchor line**

Run: `grep -n 'Reviewer fallback & NotebookLM:' .claude/skills/method-derive/SKILL.md`
Expected: one line number (will be ~53 after Task 1's insertions — exact number may differ; use what grep returns).

- [ ] **Step 2.2: Insert the Argument Parsing subsection immediately before that line**

Edit — find this exact block:
```
> Override constants via argument if needed, e.g. `-- pilot_n: 100, pilot_reps: 200, reviewer: subagent, focus: "scrutinize the sandwich variance derivation most heavily"`.

**Reviewer fallback & NotebookLM:**
```

Replace with:
```
> Override constants via argument if needed, e.g. `-- pilot_n: 100, pilot_reps: 200, reviewer: subagent, focus: "scrutinize the sandwich variance derivation most heavily"`.

### Argument Parsing for USER_FOCUS

`$ARGUMENTS` may contain a mix of (a) the estimand/method specification, (b) recognized parameters (`pilot_n:`, `pilot_reps:`, `reviewer:`, `focus:`, etc.), and (c) free-text directives. Parse as follows:

1. Extract the estimand/method specification (the `ESTIMAND: … | METHOD: …` block or equivalent).
2. Extract recognized parameters by their `key:` prefix.
3. **Anything left over — including any free-text natural-language directive (e.g., "focus on the variance step") — is treated as `USER_FOCUS`.** Concatenate and trim whitespace.
4. If the user explicitly provides `focus: "..."`, that value takes precedence over any free-text leftovers.
5. Log the parsed `USER_FOCUS` value (or `"(none)"`) to `derive-logs/score-history.md` under a "Configuration" block so the user can verify it was captured.

**Reviewer fallback & NotebookLM:**
```

(Note: the replacement leaves `**Reviewer fallback & NotebookLM:**` in place — Task 3 will rewrite that sentence.)

- [ ] **Step 2.3: Verify the new subsection exists and is in the right place**

Run:
```bash
grep -n '^### Argument Parsing for USER_FOCUS' .claude/skills/method-derive/SKILL.md
grep -c 'Anything left over' .claude/skills/method-derive/SKILL.md
```
Expected: one matching line number; count `1`.

---

### Task 3: Extend the Reviewer fallback & NotebookLM line

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` — the `**Reviewer fallback & NotebookLM:**` sentence (originally at line 51).

- [ ] **Step 3.1: Replace the existing one-sentence line**

Edit — find this exact block:
```
**Reviewer fallback & NotebookLM:** When Codex MCP is unavailable, this skill falls back to a Claude subagent reviewer — **always use `model: "opus"`** in the Agent call. Before implementing CRITICAL/MAJOR changes from reviews, consult NotebookLM. See `.claude/rules/codex-fallback-protocol.md` for full protocol.
```

Replace with:
```
**Reviewer fallback & NotebookLM:** The math review loop (Phase 2 & Phase 4) respects `REVIEWER_BACKEND`. Under `auto` (default), probe Codex MCP once at startup; if unavailable, fall back to a Claude subagent reviewer with `model: "opus"` (explicit — never omit). Log `"Reviewer backend: codex"` or `"Reviewer backend: subagent (Codex MCP unavailable)"` to `derive-logs/score-history.md`. Before implementing CRITICAL/MAJOR changes from reviews, consult NotebookLM. Phase 6's `domain-reviewer` agent is unaffected by `REVIEWER_BACKEND`. See `.claude/rules/codex-fallback-protocol.md` for full protocol.
```

- [ ] **Step 3.2: Verify**

Run:
```bash
grep -c 'probe Codex MCP once at startup' .claude/skills/method-derive/SKILL.md
grep -c 'Reviewer backend: codex' .claude/skills/method-derive/SKILL.md
```
Expected: `1`, `1`.

---

### Task 4: Extend DERIVE_STATE.json schema

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` — the JSON example and the field-value table (original lines 55–77).

- [ ] **Step 4.1: Update the JSON example**

Edit — find this exact block:
```json
{
  "phase": "anchor",
  "round": 0,
  "threadId": null,
  "last_score": null,
  "last_verdict": null,
  "status": "in_progress",
  "timestamp": "2026-03-27T10:00:00"
}
```

Replace with:
```json
{
  "phase": "anchor",
  "round": 0,
  "threadId": null,
  "reviewer_backend": "codex",
  "user_focus": "",
  "last_score": null,
  "last_verdict": null,
  "status": "in_progress",
  "timestamp": "2026-03-27T10:00:00"
}
```

- [ ] **Step 4.2: Add two rows to the field-value table**

Edit — find this exact block:
```
| Field | Values |
|-------|--------|
| `phase` | `"anchor"` / `"derivation"` / `"math-review"` / `"revision"` / `"simulation"` / `"code-review"` / `"pilot"` / `"slurm"` / `"done"` |
| `round` | 0–MAX_ROUNDS |
| `threadId` | Reviewer thread ID for `codex-reply` continuity |
| `last_score` | Most recent overall score |
| `last_verdict` | `CORRECT` / `REVISE` / `REDERIVE` |
| `status` | `"in_progress"` / `"completed"` |
```

Replace with:
```
| Field | Values |
|-------|--------|
| `phase` | `"anchor"` / `"derivation"` / `"math-review"` / `"revision"` / `"simulation"` / `"code-review"` / `"pilot"` / `"slurm"` / `"done"` |
| `round` | 0–MAX_ROUNDS |
| `threadId` | Reviewer thread ID for `codex-reply` continuity. **`null` when `reviewer_backend == "subagent"`**; in that case Round N-1 review text is stored in `derive-logs/round-N-1-math-review.md` for Round N context. |
| `reviewer_backend` | `"codex"` / `"subagent"` — records which backend was used. Logged alongside every round. |
| `user_focus` | Verbatim `USER_FOCUS` string, or `""` if none. Persisted so checkpoint recovery re-injects the same focus into subsequent rounds. |
| `last_score` | Most recent overall score |
| `last_verdict` | `CORRECT` / `REVISE` / `REDERIVE` |
| `status` | `"in_progress"` / `"completed"` |
```

- [ ] **Step 4.3: Verify**

Run:
```bash
grep -c '"reviewer_backend": "codex"' .claude/skills/method-derive/SKILL.md
grep -c '"user_focus":' .claude/skills/method-derive/SKILL.md
grep -c '| `reviewer_backend` |' .claude/skills/method-derive/SKILL.md
grep -c '| `user_focus` |' .claude/skills/method-derive/SKILL.md
```
Expected: `1`, `1`, `1`, `1`.

---

### Task 5: Phase 2 — add REVIEWER_BACKEND branch and USER_FOCUS injection block

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` — the `### Phase 2: External Math Review (Round 1)` section (originally starting at line 187).

- [ ] **Step 5.1: Locate Phase 2**

Run: `grep -n '^### Phase 2: External Math Review' .claude/skills/method-derive/SKILL.md`
Expected: one line number (exact value depends on earlier insertions).

- [ ] **Step 5.2: Replace the Phase 2 intro sentence ("Send the full derivation to GPT-5.4:") with a backend-branch preamble**

Edit — find this exact block:
```
### Phase 2: External Math Review (Round 1)

Send the full derivation to GPT-5.4:

```
mcp__codex__codex:
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
```

Replace with:
```
### Phase 2: External Math Review (Round 1)

**Branch by `REVIEWER_BACKEND`.** Both branches use the same `REVIEWER_PROMPT` (defined below, with the optional `## User Focus (priority)` block prepended when `USER_FOCUS` is non-empty).

#### If backend = `codex`

Send the full derivation to GPT-5.4:

```
mcp__codex__codex:
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
```

- [ ] **Step 5.3: After the existing Codex prompt block closes and before the `**CRITICAL: Save the `threadId`**` line, inject the subagent branch, the USER_FOCUS injection rules, and the shared REVIEWER_PROMPT heading**

Find the existing line:
```
**CRITICAL: Save the `threadId`** from this call for all later rounds.
```

Replace with:
```
#### If backend = `subagent`

Spawn a Claude subagent with the **same persona and prompt** as the Codex branch. `model: "opus"` is REQUIRED — never omit it (the `Agent` tool inherits Sonnet from the parent otherwise):

```
Agent:
  description: "method-derive math review round 1"
  model: "opus"
  prompt: |
    [REVIEWER_PROMPT below — same text as Codex branch]
```

Save the full raw response text to `derive-logs/round-1-math-review.md` inside a `<details>` block. For `subagent` backend, `threadId = null`; Round N (N ≥ 2) will re-read this file for context.

#### USER_FOCUS injection (shared by both backends)

If `USER_FOCUS` is non-empty, prepend a `## User Focus (priority)` block immediately **before** the `=== DERIVATION ===` line inside REVIEWER_PROMPT:

```
## User Focus (priority)
[USER_FOCUS verbatim — omit this entire block if USER_FOCUS is empty]

Treat this focus as the highest-priority review lens for this round. Score the derivation primarily on how well it satisfies this focus (weight the 7-dimension scoring accordingly), while still flagging any CRITICAL mathematical errors you observe in other dimensions.
```

If `USER_FOCUS` is empty, omit the entire block — the prompt is byte-identical to the pre-change version.

#### REVIEWER_PROMPT (shared by both backends)

The prompt body — persona, 7-dimension scoring rubric, verdict rules, output format — is unchanged from prior versions. It is the text that already appears below after the `prompt: |` line.

**CRITICAL (Codex branch only): Save the `threadId`** from the Codex call for all later rounds. For `subagent` backend, skip this — Round N ≥ 2 re-reads `derive-logs/round-N-1-math-review.md` instead.
```

- [ ] **Step 5.4: Update the Phase 2 checkpoint line to include `reviewer_backend` and `user_focus`**

Edit — find this exact line:
```
**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "math-review", "round": 1, "threadId": "<saved>", "last_score": <parsed>, "last_verdict": "<parsed>"`.
```

Replace with:
```
**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "math-review", "round": 1, "threadId": "<saved-or-null>", "reviewer_backend": "<codex|subagent>", "user_focus": "<USER_FOCUS verbatim>", "last_score": <parsed>, "last_verdict": "<parsed>"`.
```

- [ ] **Step 5.5: Verify all four insertions**

Run:
```bash
grep -c '^#### If backend = `codex`' .claude/skills/method-derive/SKILL.md
grep -c '^#### If backend = `subagent`' .claude/skills/method-derive/SKILL.md
grep -c '^#### USER_FOCUS injection (shared by both backends)' .claude/skills/method-derive/SKILL.md
grep -c '^## User Focus (priority)' .claude/skills/method-derive/SKILL.md
grep -c '"reviewer_backend": "<codex|subagent>"' .claude/skills/method-derive/SKILL.md
```
Expected: `1`, `1`, `1`, `1`, `1`. (After Task 6, the first four counts will double to `2` — that's expected.)

---

### Task 6: Phase 4 — add REVIEWER_BACKEND branch and persistent USER_FOCUS injection

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` — the `### Phase 4: Re-evaluation (Round 2+)` section (originally starting at line 345).

- [ ] **Step 6.1: Locate Phase 4**

Run: `grep -n '^### Phase 4: Re-evaluation' .claude/skills/method-derive/SKILL.md`
Expected: one line number.

- [ ] **Step 6.2: Replace the Phase 4 intro sentence ("Send the revised derivation in the **same thread**:") with a backend-branch preamble, and add the subagent branch + USER_FOCUS block after the existing codex-reply prompt**

Edit — find this exact block (starting at the Phase 4 heading through the `Save to \`derive-logs/round-N-math-review.md\`.` line):
```
### Phase 4: Re-evaluation (Round 2+)

Send the revised derivation in the **same thread**:

```
mcp__codex__codex-reply:
  threadId: [saved from Phase 2]
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [Round N re-evaluation]

    I revised the derivation based on your feedback.
    First, verify the Estimand Anchor is still preserved.
    Focus new critiques on any remaining math errors, gaps, or unstated assumptions.

    Key changes:
    1. [Change 1 — section, what was wrong, what was corrected]
    2. [Change 2]
    3. [Pushback if any — what was rejected and why]

    === REVISED DERIVATION ===
    [Paste full revised derivation]
    === END REVISED DERIVATION ===

    Re-score all 7 dimensions and provide updated overall score and verdict.
    Same output format: 7 scores, overall, verdict, hidden assumptions, drift warning.
    Use CORRECT only if overall >= 9 and no blocking issues remain.
```

Save to `derive-logs/round-N-math-review.md`.
```

Replace with:
```
### Phase 4: Re-evaluation (Round 2+)

**Branch by `REVIEWER_BACKEND`.** Both branches send the same `ROUND_N_PROMPT` (defined below, with the optional `## User Focus (priority — persistent across rounds)` block prepended when `USER_FOCUS` is non-empty).

#### If backend = `codex`

Send the revised derivation in the **same thread** using the saved `threadId`:

```
mcp__codex__codex-reply:
  threadId: [saved from Phase 2]
  model: REVIEWER_MODEL
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [ROUND_N_PROMPT below]
```

#### If backend = `subagent`

Spawn a **new** subagent with prior round context embedded (subagents don't persist state). `model: "opus"` is REQUIRED:

```
Agent:
  description: "method-derive math review round N"
  model: "opus"
  prompt: |
    You are a top-journal referee (Biostatistics, JASA, Statistics in Medicine)
    with deep expertise in survival analysis, semiparametric estimation, recurrent
    event methods, missing data, and pseudo-observation theory.

    ## Context: You have reviewed this derivation across N-1 previous rounds.

    ### Summaries of Rounds 1 through N-2:
    [Omit this block entirely when N=2. For N ≥ 3, for each round k from 1 to N-2:
    read `derive-logs/score-history.md` and `derive-logs/round-k-revision.md` to build
    a 3-sentence summary: score, key gaps identified, corrections applied.]

    ### Your Most Recent Review (Round N-1, verbatim):
    [paste full text of `derive-logs/round-(N-1)-math-review.md`]

    ### Revisions Implemented Since Round N-1:
    1. [Correction 1 — section, what was wrong, what was corrected]
    2. [Correction 2]
    3. [Pushback if any — what was rejected and why]

    [ROUND_N_PROMPT below]
```

Save the full raw response text to `derive-logs/round-N-math-review.md`.

#### USER_FOCUS injection (shared by both backends, every round N ≥ 2)

If `USER_FOCUS` is non-empty, prepend a `## User Focus (priority — persistent across rounds)` block at the top of `ROUND_N_PROMPT`, **before** the `[Round N re-evaluation]` line. This re-asserts the user's focus in every round even when the Codex thread or subagent summary carries prior context.

```
## User Focus (priority — persistent across rounds)
[USER_FOCUS verbatim — omit this entire block if USER_FOCUS is empty]

This focus was specified at the start of the derivation loop and applies to every round.
Continue scoring the derivation primarily on how well it satisfies this focus (weight the 7-dimension scoring accordingly), while still flagging any CRITICAL mathematical errors in other dimensions.
```

If `USER_FOCUS` is empty, omit the entire block.

#### ROUND_N_PROMPT (shared by both backends, applies to all rounds N ≥ 2)

```
[Round N re-evaluation]

I revised the derivation based on your feedback.
First, verify the Estimand Anchor is still preserved.
Focus new critiques on any remaining math errors, gaps, or unstated assumptions.

Key changes:
1. [Change 1 — section, what was wrong, what was corrected]
2. [Change 2]
3. [Pushback if any — what was rejected and why]

=== REVISED DERIVATION ===
[Paste full revised derivation]
=== END REVISED DERIVATION ===

Re-score all 7 dimensions and provide updated overall score and verdict.
Same output format: 7 scores, overall, verdict, hidden assumptions, drift warning.
Use CORRECT only if overall >= 9 and no blocking issues remain.
```

Save the response to `derive-logs/round-N-math-review.md`.
```

- [ ] **Step 6.3: Update the Phase 4 checkpoint line to include `reviewer_backend` and `user_focus`**

Edit — find this exact line:
```
**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "math-review", "round": N`.
```

Replace with:
```
**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "math-review", "round": N, "reviewer_backend": "<codex|subagent>", "user_focus": "<USER_FOCUS verbatim>"`.
```

- [ ] **Step 6.4: Verify all insertions**

Run:
```bash
grep -c '^#### If backend = `codex`' .claude/skills/method-derive/SKILL.md
grep -c '^#### If backend = `subagent`' .claude/skills/method-derive/SKILL.md
grep -c '^#### USER_FOCUS injection (shared by both backends, every round N ≥ 2)' .claude/skills/method-derive/SKILL.md
grep -c '^#### ROUND_N_PROMPT (shared by both backends, applies to all rounds N ≥ 2)' .claude/skills/method-derive/SKILL.md
grep -c 'User Focus (priority — persistent across rounds)' .claude/skills/method-derive/SKILL.md
```
Expected: `2`, `2`, `1`, `1`, `1`. (First two counts are `2` because Phase 2 has matching headings too.)

---

### Task 7: Add three bullets to the Key Rules section

**Files:**
- Modify: `.claude/skills/method-derive/SKILL.md` — the `## Key Rules` section (originally starting at line 600).

- [ ] **Step 7.1: Locate the `xhigh` rule line**

Run: `grep -n 'ALWAYS use `config: {"model_reasoning_effort": "xhigh"}`' .claude/skills/method-derive/SKILL.md`
Expected: one line number.

- [ ] **Step 7.2: Insert three new bullets immediately after that line**

Edit — find this exact line:
```
- **ALWAYS use `config: {"model_reasoning_effort": "xhigh"}`** for all Codex calls.
```

Replace with:
```
- **ALWAYS use `config: {"model_reasoning_effort": "xhigh"}`** for all Codex calls.
- **Subagent reviewer requires `model: "opus"`** — the `Agent` tool inherits Sonnet from the parent if `model` is omitted. Always pass `model: "opus"` explicitly for every `Agent` call used as a reviewer fallback in Phase 2 and Phase 4.
- **Log the reviewer backend** — record which backend was used (`codex` or `subagent`) in both `DERIVE_STATE.json` and `derive-logs/score-history.md` for every round.
- **USER_FOCUS persists across rounds and compacts.** It is re-injected into the reviewer prompt in every Phase 2 and Phase 4 call, and it is persisted in `DERIVE_STATE.json` so checkpoint recovery re-injects the same focus.
```

- [ ] **Step 7.3: Verify**

Run:
```bash
grep -c 'Subagent reviewer requires' .claude/skills/method-derive/SKILL.md
grep -c 'Log the reviewer backend' .claude/skills/method-derive/SKILL.md
grep -c 'USER_FOCUS persists across rounds' .claude/skills/method-derive/SKILL.md
```
Expected: `1`, `1`, `1`.

---

### Task 8: Self-review, diff audit, and commit

- [ ] **Step 8.1: Confirm Phase 6 `domain-reviewer` invocation is untouched**

Run:
```bash
grep -n 'Phase 6' .claude/skills/method-derive/SKILL.md
grep -n 'domain-reviewer' .claude/skills/method-derive/SKILL.md
git diff .claude/skills/method-derive/SKILL.md | grep -E '^\+|^-' | grep -iE 'domain-reviewer|Phase 6|Lens' | head
```
Expected: the grep for `Phase 6` and `domain-reviewer` returns the original line numbers + content; the diff grep returns **no lines** (nothing was added or removed touching `domain-reviewer` / `Phase 6` / `Lens`).

- [ ] **Step 8.2: Confirm Phase 7 (Pilot), Phase 8 (SLURM), Phase 9 (Final Report) were untouched**

Run:
```bash
git diff .claude/skills/method-derive/SKILL.md | grep -E '^\+|^-' | grep -iE 'pilot_results\.md|run_full\.slurm|FINAL_DERIVATION\.md|SLURM|Pilot Run' | head
```
Expected: **no matching lines** — none of these strings should appear in the added/removed lines.

- [ ] **Step 8.3: Spec coverage checklist — manually confirm each spec item is implemented**

Open [quality_reports/plans/2026-04-20_method-derive-reviewer-fallback.md](2026-04-20_method-derive-reviewer-fallback.md) and confirm:

- [ ] Spec §1 "New Constants" → Task 1
- [ ] Spec §2 "Argument Parsing block" → Task 2
- [ ] Spec §3 "Reviewer Fallback Line" → Task 3
- [ ] Spec §4 "DERIVE_STATE.json schema" → Task 4
- [ ] Spec §5 "Phase 2 branch + USER_FOCUS" → Task 5
- [ ] Spec §6 "Phase 4 branch + USER_FOCUS" → Task 6
- [ ] Spec §7 "Key Rules bullets" → Task 7
- [ ] Spec §8 "Override example" → completed inline within Task 1 Step 1.2

- [ ] **Step 8.4: Byte-identity sanity check for the common case**

The spec promises that with empty `USER_FOCUS` + Codex available, the reviewer prompts are byte-identical to the pre-change behavior. The prompts themselves (REVIEWER_PROMPT body and ROUND_N_PROMPT body) must remain unchanged. Verify by diff:

Run:
```bash
diff <(sed -n '/=== DERIVATION ===/,/=== END DERIVATION ===/p' /tmp/method-derive-SKILL.md.baseline) \
     <(sed -n '/=== DERIVATION ===/,/=== END DERIVATION ===/p' .claude/skills/method-derive/SKILL.md) || true

diff <(sed -n '/=== REVISED DERIVATION ===/,/=== END REVISED DERIVATION ===/p' /tmp/method-derive-SKILL.md.baseline) \
     <(sed -n '/=== REVISED DERIVATION ===/,/=== END REVISED DERIVATION ===/p' .claude/skills/method-derive/SKILL.md) || true
```
Expected: empty diff output for both (the prompt-content blocks themselves are unchanged).

If either diff is non-empty, inspect the output carefully — any change there violates the byte-identity guarantee and must be reverted.

- [ ] **Step 8.5: Placeholder scan**

Run:
```bash
grep -n -iE 'TBD|TODO|\[fill in|to be determined' .claude/skills/method-derive/SKILL.md | grep -vE 'Open Questions|placeholder quantity' || echo "OK: no placeholders"
```
Expected: `OK: no placeholders` (the `grep -v` tolerates the legitimate "Open Questions / Provisional Steps" header in Phase 1).

- [ ] **Step 8.6: Append to today's session log**

Run:
```bash
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)
LOG="quality_reports/session_logs/${DATE}_method-derive-reviewer-fallback.md"
if [ ! -f "$LOG" ]; then
  cat > "$LOG" <<EOF
# Session Log — ${DATE} — method-derive reviewer fallback

## Goal
Port \`REVIEWER_BACKEND\` subagent fallback + \`USER_FOCUS\` injection from auto-paper-improvement-loop into method-derive (Phase 2 & Phase 4 only).

## Approach
Eight surgical edits to \`.claude/skills/method-derive/SKILL.md\`. Phase 6 and later untouched. Default behavior byte-identical.

## Key Context
- Spec: \`quality_reports/plans/2026-04-20_method-derive-reviewer-fallback.md\`
- Plan: \`quality_reports/plans/2026-04-20_method-derive-reviewer-fallback-impl.md\`
- Reference pattern: \`.claude/skills/auto-paper-improvement-loop/SKILL.md\`

## Changes
EOF
fi
echo "- [${TIME}] .claude/skills/method-derive/SKILL.md — added REVIEWER_BACKEND + USER_FOCUS with math-review-loop subagent fallback; Phase 6 domain-reviewer unchanged." >> "$LOG"
echo "Session log updated: $LOG"
```
Expected: log file exists and has the new timestamped entry at the bottom.

- [ ] **Step 8.7: Update the `Last Updated:` header inside SKILL.md if one exists**

Run: `grep -n 'Last Updated' .claude/skills/method-derive/SKILL.md`
- If a line matches → edit it to today's date.
- If no line matches → skip.

- [ ] **Step 8.8: Commit**

Run:
```bash
git add .claude/skills/method-derive/SKILL.md quality_reports/session_logs/*.md
git commit -m "$(cat <<'EOF'
feat(skill): add reviewer subagent fallback + USER_FOCUS to method-derive

Mirrors the auto-paper-improvement-loop pattern for the math review loop
(Phase 2 & Phase 4). Phase 6 domain-reviewer and later phases unchanged.
Default behavior (empty USER_FOCUS, Codex available) byte-identical to
pre-change behavior.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```
Expected: commit succeeds; `git status` shows clean tree for the skill file.

- [ ] **Step 8.9: Final cleanup**

Run: `rm /tmp/method-derive-SKILL.md.baseline`

Expected: baseline file removed.

---

## Self-Review (executed once this plan is written, before handoff)

**1. Spec coverage:**
- §1 Constants → Task 1 ✓
- §2 Argument parsing → Task 2 ✓
- §3 Reviewer-fallback line → Task 3 ✓
- §4 State JSON → Task 4 ✓
- §5 Phase 2 → Task 5 ✓
- §6 Phase 4 → Task 6 ✓
- §7 Key Rules → Task 7 ✓
- §8 Override example → folded into Task 1 Step 1.2 ✓
- Verification §Checklist → Task 8 (grep-based verifications in every task + byte-identity diff in 8.4) ✓

**2. Placeholder scan:** plan contains no "TBD", "TODO", "similar to Task N". Every step contains either full replacement text or an exact grep/diff command with expected output.

**3. Type/identifier consistency:** `REVIEWER_BACKEND`, `USER_FOCUS`, `reviewer_backend`, `user_focus` are used consistently across all tasks. JSON field name matches constant casing (`reviewer_backend` not `ReviewerBackend`). `model: "opus"` (lowercase o, double-quoted) is consistent with APIL.

**4. Risk checks:**
- Line numbers in `grep -n` instructions drift as earlier tasks insert text — each task uses grep to *re-locate* the anchor, never assumes stale line numbers.
- Tasks 5 and 6 both add `#### If backend = \`codex\`` / `#### If backend = \`subagent\`` headings, so the count-2 expectation in Task 6 Step 6.4 is the deliberate correct result.
- The byte-identity diff in 8.4 only covers the prompt-body text between the `=== DERIVATION ===` / `=== REVISED DERIVATION ===` markers; the surrounding scaffolding (backend-branch headers, USER_FOCUS blocks) is intended to change, so the wider diff will show additions — that is expected.
