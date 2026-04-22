# Paper Stress-Test Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `paper-stress-test` Claude Code skill that uploads a paper to NotebookLM, runs a two-subagent adversarial debate against it (Opus Reviewer vs. Sonnet Author-surrogate), fires a concurrent `novelty-check` sub-call, and delivers a structured briefing with cite/build-on/flag/skip recommendation.

**Architecture:** Pure markdown skill with three component files (`SKILL.md`, `agents/{reviewer,author}.md`, `templates/briefing.md`). The Moderator (main Claude running the skill) orchestrates two persistent subagents via `Agent` + `SendMessage`, three NotebookLM notebooks (disposable per-paper + thematic cross-check + reviewer's Lens-7-only read access to thematic), and one sub-skill call (`novelty-check` via `Skill` tool). Outputs go to `master_supporting_docs/supporting_papers/stress_tests/{briefing,transcripts,state}/` with date-stamped slugs.

**Tech Stack:** Markdown prompt templates; Bash tool for arXiv download + file ops; `mcp__notebooklm__*` tools for notebook/source management; `Agent` + `SendMessage` for subagent lifecycle; `Skill` tool for `novelty-check` sub-call; `Read` tool for PDF metadata extraction.

**Spec reference:** `quality_reports/specs/2026-04-22_paper-stress-test-design.md` (commits `31ea4c9`, `22a4a7d`, `764a7e5`).

---

## File Structure

All files live under `.claude/skills/paper-stress-test/`:

| Path | Responsibility |
|------|---------------|
| `SKILL.md` | Moderator playbook. Frontmatter + Phases 0–6 instructions + error-handling table + resumability rules. ~400 lines. |
| `agents/reviewer.md` | Opus Reviewer persona prompt + output-format contract (QUESTION / JUDGMENT / FOLLOWUP / SEVERITY). ~80 lines. |
| `agents/author.md` | Sonnet Author-surrogate persona + retrieval protocol + "paper does not address this" requirement. ~60 lines. |
| `templates/briefing.md` | Fill-in-the-blank briefing skeleton with all 11 sections. ~150 lines. |

Runtime outputs (NOT in skill dir) live under `master_supporting_docs/supporting_papers/stress_tests/{briefing,transcripts,state}/`.

No bash helper scripts — all logic lives as instructions in `SKILL.md`. The Moderator executes via the Bash tool when needed (arXiv download, prior-test globbing, file dir creation).

---

## Task Dependencies

```
T0 (precondition probe) ──> T1 (scaffold) ──> T1.5 (parsing contract) ──┬──> T2 (Phase 0) ──> T3 (Phase 1) ──> T4 (Phase 2 classify)
                │                                           │
                │                                           v
                │                                    T5 (Phase 2 novelty) ──> T6 (Phase 2 confirm)
                │                                                                   │
                │                                                                   v
                ├──> T15 (reviewer.md) ─────────────────────────────────────> T7 (Phase 3 scaffold)
                │                                                                   │
                ├──> T16 (author.md) ───────────────────────────────────────────────┤
                │                                                                   v
                │                                                            T8 (Phase 3 debate)
                │                                                                   │
                │                                                                   v
                │                                                            T9 (Phase 3 Lens 7)
                │                                                                   │
                │                                                                   v
                │                                                            T10 (reseed) ──> T11 (severity + state)
                │                                                                               │
                ├──> T17 (templates/briefing.md) ──────────────────────────────────────────────> T12 (Phase 4 synthesis)
                │                                                                                    │
                │                                                                                    v
                │                                                                              T13 (Phase 5 write)
                │                                                                                    │
                │                                                                                    v
                │                                                                              T14 (Phase 6 + promote)
                │                                                                                    │
                │                                                                                    v
                └──────────────────────────────────────────────────────────────────────────── T18 (errors + resume)
                                                                                                     │
                                                                                                     v
                                                                                              T19 (smoke test)
```

T15, T16, T17 can be done in parallel with the phase tasks as long as they land before T7, T7, T12 respectively.

---

## Conventions for this Plan

- Each task edits `SKILL.md` (or creates a component file) and ends with a commit.
- "Verify" steps are visual reads of the rendered markdown unless otherwise noted; the skill itself has no unit-test framework — it is prose executed by Claude at runtime. Runtime verification happens in **T19 (smoke test)**.
- Commit messages follow the repo convention: `feat(paper-stress-test): <summary>`.
- All file paths are absolute to avoid ambiguity.

---

## Task 0: Precondition probe — verify Agent + SendMessage persistence

**Why:** The entire Phase 3 debate architecture assumes two subagents spawned once and continued across 9 lenses via `SendMessage`. If the current Claude Code harness does NOT support cross-call session persistence (the agent loses context between `SendMessage` calls, or `SendMessage` rejects the saved `agent_id`), the architecture must change to per-lens respawning with reseed briefs. This task proves the assumption before writing 2000+ lines of code on top of it.

**Files:**
- Create: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/quality_reports/session_logs/2026-04-22_paper-stress-test-probe.md` (ephemeral log of the probe session)

- [ ] **Step 0.1: Load deferred tools**

Load `Agent` and `SendMessage` schemas via ToolSearch:

```
ToolSearch(query="select:Agent,SendMessage", max_results=2)
```

Expected: both tool schemas returned. If either is missing, the skill cannot be built on this harness — stop.

- [ ] **Step 0.2: Spawn a probe agent that requires cross-turn memory**

```
Agent(
  description: "persistence probe",
  subagent_type: "general-purpose",
  model: "sonnet",
  prompt: "You are a counting agent. You maintain a running integer counter, initialized to 0. When I say the exact word 'next', increment the counter by 1 and reply with ONLY the new counter value (no prose, no explanation). When I say 'report', reply with ONLY the current counter value. On this first turn, reply with exactly the word READY. Nothing else."
)
```

Record the returned `agent_id` (call it `PROBE_ID`).

Verify the first response is literally `READY`. If it is anything else, the agent is noncompliant — record that.

- [ ] **Step 0.3: Send three `next` messages and verify counter increments**

```
SendMessage(to: PROBE_ID, message: "next")   # expect "1"
SendMessage(to: PROBE_ID, message: "next")   # expect "2"
SendMessage(to: PROBE_ID, message: "next")   # expect "3"
SendMessage(to: PROBE_ID, message: "report") # expect "3"
```

Capture all four responses verbatim.

- [ ] **Step 0.4: Evaluate probe outcome**

Pass criteria (ALL must hold):

- Each `next` response is a single integer, with no prose.
- The integers are exactly `1`, `2`, `3` in that order (proves persistence — the agent remembers the counter state across messages).
- The `report` response is `3` (proves the state has been carried continuously through all turns).

Write the probe log to `quality_reports/session_logs/2026-04-22_paper-stress-test-probe.md` with:

```markdown
# Persistence Probe — 2026-04-22

## Agent spawn
- agent_id: <PROBE_ID>
- initial response: <verbatim>

## SendMessage responses
1. next -> <response>
2. next -> <response>
3. next -> <response>
4. report -> <response>

## Outcome
<PASS | FAIL>

Reason: <one sentence>
```

- [ ] **Step 0.5: Branch on outcome**

**If PASS:** commit the probe log and proceed to T1. The current plan (T1–T19) is valid as written.

```bash
git add quality_reports/session_logs/2026-04-22_paper-stress-test-probe.md
git commit -m "chore(paper-stress-test): T0 persistence probe passed"
```

**If FAIL:** STOP. The architecture must change before T1. Two fallback paths, to be decided by user after reading the probe log:

- **Fallback A — per-lens respawn:** Every lens spawns a fresh Reviewer + Author pair, seeded with the reseed brief (same mechanism as T10). Cost: ~2x subagent spawns, more context-per-spawn from the reseed brief. Requires T7/T8/T9/T10 to be rewritten to spawn-per-lens and NOT use `SendMessage` continuity.
- **Fallback B — transcript-relay pattern:** Instead of persistent subagents, the Moderator maintains the "debate transcript" itself and sends the full running transcript to a fresh subagent each turn ("here's the debate so far, it's your turn as <role>, say your next line"). Much heavier per-call prompt; no cross-turn state to lose.

Do NOT proceed past T0 on FAIL without explicit user decision on which fallback to take. Update this plan's T7–T11 accordingly before starting T1.

- [ ] **Step 0.6: Probe background-agent mode (run_in_background + notification)**

T5 depends on `Agent(run_in_background: true)` returning immediately AND the harness later notifying the Moderator when the agent completes. If `run_in_background` is silently ignored (the call blocks anyway), or if the completion notification never surfaces, T5's enforceable-timeout design falls apart.

Spawn a short-running background agent:

```
Agent(
  description: "background mode probe",
  subagent_type: "general-purpose",
  model: "sonnet",
  run_in_background: true,
  prompt: "Wait briefly, then return exactly the string BG_PROBE_OK. Do not use any tools."
)
```

Record the returned `BG_PROBE_ID` and the exact timestamp of the call.

Pass criteria for Step 0.6:

- The Agent call **returns immediately** (within ~5s wall clock). If it blocks for noticeably longer, `run_in_background` is not working as assumed → FAIL this step.
- Within the next ~60s, a completion notification for `BG_PROBE_ID` surfaces in the Moderator's context (as a system message or comparable signal). When it does, verify the agent's final output was `BG_PROBE_OK`. If either the notification never arrives or the output differs, FAIL.
- Continue normal work (don't just wait) between the call and the notification — that's the scenario T5 relies on.

Append to the probe log:

```markdown
## Background-mode probe
- spawn timestamp: <ISO>
- call returned in: <seconds> s
- notification received: <YES | NO — timeout after 60s>
- notification timestamp: <ISO or n/a>
- final output matched BG_PROBE_OK: <YES | NO>

## Outcome: <PASS | FAIL — background mode>
```

**If background mode FAILS but persistence (0.3/0.4) PASSED:** T5 must be rewritten to call `novelty-check` synchronously via a non-background Agent and accept that timeout enforcement is impossible. The user should be warned at plan-confirmation time that the novelty-check step may take several minutes of foreground blocking. Document this rewrite as a follow-up before starting T1.

**If both FAIL:** stop; do not start T1. The entire skill architecture is incompatible with this harness.

- [ ] **Step 0.7: Let the probe agents expire**

No explicit "delete agent" tool exists. Note in the probe log: "counting agent and BG probe agent both left to expire naturally."

---

## Task 1: Scaffold skill directory + SKILL.md frontmatter

**Files:**
- Create: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`
- Create: directory `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/agents/`
- Create: directory `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/templates/`

- [ ] **Step 1.1: Create the skill directory tree**

Run:
```bash
mkdir -p "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/agents"
mkdir -p "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/templates"
ls "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/"
```

Expected: output lists `agents` and `templates`.

- [ ] **Step 1.2: Write SKILL.md frontmatter + overview**

Write to `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`:

````markdown
---
name: paper-stress-test
description: Upload a paper to NotebookLM, run an automated adversarial debate between an Opus Reviewer subagent and a Sonnet Author-surrogate subagent (with concurrent novelty-check sub-call), and produce a structured briefing with cite/build-on/flag/skip recommendation. Use when the user says "stress test this paper", "adversarial read of this paper", "brief me on this paper", "help me read this paper", "is this paper's claim real", or wants deep single-paper interrogation rather than surface-level summary. Not for reviewing the user's own manuscripts (use review-paper) or multi-paper synthesis (use lit-review).
argument-hint: "<paper-path-or-arxiv-id> [--depth N] [--type T] [--cross-check NB] [--skip-novelty]"
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Agent, mcp__notebooklm__notebook_create, mcp__notebooklm__notebook_delete, mcp__notebooklm__notebook_list, mcp__notebooklm__source_add, mcp__notebooklm__notebook_query
---

# Paper Stress-Test

Adversarial single-paper interrogation: **$ARGUMENTS**

## Overview

This skill uploads a paper to a disposable NotebookLM notebook, then runs a structured adversarial debate between two persistent subagents — an Opus Reviewer (hostile Biostatistics referee) and a Sonnet Author-surrogate (defends the paper using only paper-internal evidence retrieved via NotebookLM) — across nine lenses weighted by detected paper type. A concurrent sub-call to the `novelty-check` skill provides external novelty verification. The output is a structured briefing with per-lens severity, top-5 killer questions, sub-project relevance, and a cite/build-on/flag/skip recommendation.

Spec reference: `quality_reports/specs/2026-04-22_paper-stress-test-design.md`.

## Workflow

Six phases:

| Phase | Purpose |
|-------|---------|
| 0 | Input resolution + prior-test detection + output dir setup |
| 1 | NotebookLM setup (disposable notebook + paper upload + thematic resolution) |
| 2 | Reviewer spawn, paper-type detection, novelty-check sub-call, plan confirmation |
| 3 | Author spawn + per-lens adversarial debate (Lens 7 triangulates three sources) |
| 4 | Synthesis (top-5 questions, sub-project relevance, recommendation) |
| 5 | Write briefing + transcripts + state files |
| 6 | Cleanup with optional promote-to-thematic |

## Constants

- DISPOSABLE_NOTEBOOK_NAME_PREFIX = `stress-test-`
- CONTEXT_RESEED_THRESHOLD_TOKENS = 160000
- NOVELTY_CHECK_TIMEOUT_SECONDS = 300
- REVIEWER_MODEL = `claude-opus-4-7`
- AUTHOR_MODEL = `claude-sonnet-4-6`
- OUTPUT_DIR = `master_supporting_docs/supporting_papers/stress_tests`

## Defer-tool preamble

Before Phase 0, the Moderator must load three deferred tools via ToolSearch:

```
ToolSearch(query="select:Agent,SendMessage,TodoWrite", max_results=3)
```

These are required: `Agent` spawns subagents, `SendMessage` continues them across lenses, `TodoWrite` tracks lens progress.

## Known thematic notebooks (auto-suggest table)

| Notebook name | ID | Keywords that trigger auto-suggest |
|---|---|---|
| ML for Recurrent Events | `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` | survival, recurrent event, competing risk, hazard, censoring, pseudo-observation, landmark, time-to-event, frailty, counting process |
| Interpretable AI | `fea2207b-7ec1-463c-b73f-58c0c4febb41` | interpretability, explainability, feature importance, SHAP, LIME, partial dependence, counterfactual explanation |
| Machine Learning Fundamentals | `c3aab8e1-5c4b-43ec-bafc-ae3745a7c493` | neural network, deep learning, supervised learning, regularization, cross-validation, boosting, bagging |
| Survival Analysis Fundamentals | `3faa5656-280d-4ffc-ae2d-5487075bc94e` | Cox proportional hazards, Kaplan-Meier, log-rank, Nelson-Aalen, accelerated failure time, Weibull, exponential |

## Instructions

Follow the phase-by-phase instructions below. Phases 2 through 6 depend on state persisted after each lens, so Phase 3 must be resumable from `state.json`.

<!-- Phase 0 instructions added in Task 2 -->
<!-- Phase 1 instructions added in Task 3 -->
<!-- Phase 2 instructions added in Tasks 4, 5, 6 -->
<!-- Phase 3 instructions added in Tasks 7, 8, 9, 10, 11 -->
<!-- Phase 4 instructions added in Task 12 -->
<!-- Phase 5 instructions added in Task 13 -->
<!-- Phase 6 instructions added in Task 14 -->
<!-- Error handling + resumability added in Task 18 -->
````

- [ ] **Step 1.3: Commit**

```bash
git add .claude/skills/paper-stress-test/
git commit -m "feat(paper-stress-test): scaffold skill directory and frontmatter"
```

Expected: clean commit; `git status` reports clean tree.

---

## Task 1.5: Parsing contract section in SKILL.md

**Why:** Multiple downstream tasks (T4, T5, T8, T9, T11) parse free-form subagent output. Without canonical regexes centralized in one place, each task silently invents its own parsing logic, and small format drift in a persona prompt (e.g., `## Classification` vs `**Classification**`) quietly breaks every caller. This task creates the single source of truth for parsing.

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 1.5.1: Append a Parsing Contract section after the Constants block**

Use Edit to add the block below immediately after the `## Constants` section and before `## Defer-tool preamble`:

````markdown
## Parsing contract

All parsing of subagent output (Reviewer, Author, classification-triple, novelty-check runner) MUST use the regexes in this section. If a response does not match the canonical pattern, the calling task executes the "Reparse protocol" below once; if still no match, the calling task follows its task-specific recovery (recorded `errored`, user-prompted override, etc.).

### Reparse protocol

On first parse failure, reprompt the source subagent with a format reminder (verbatim from the persona file, quoted). Capture the second response. If the second response still fails, do NOT reprompt again — hand off to the task-specific recovery.

The reprompt message template:

```
Your previous response did not match the required format. The format is:

<copy the relevant format block from the persona verbatim>

Return ONLY a response in that format, nothing else.
```

### Patterns

All regexes below are POSIX-extended, multiline, case-sensitive unless noted. Matches may span newlines where `(?s)` is applied. Whitespace around field values must be trimmed on capture.

#### 1. Reviewer primary-question turn

```
^QUESTION:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
```
Captures one group: the question text (may span multiple lines, stops at next `FIELD:` line or end of string).

#### 2. Reviewer judgment + decision turn

Five fields, each on its own line; fields 4 and 5 are mutually exclusive based on field 3's value.

```
^JUDGMENT:[[:space:]]*(cited|evaded|handwaved|conceded)[[:space:]]*$
^REASONING:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
^NEXT:[[:space:]]*(FOLLOWUP|FINAL)[[:space:]]*$
^FOLLOWUP:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)     # only required if NEXT=FOLLOWUP
^SEVERITY:[[:space:]]*(critical|major|minor|clean)[[:space:]]*$  # only required if NEXT=FINAL
```

Validation: JUDGMENT must match the enum exactly. REASONING must be non-empty. If NEXT=FOLLOWUP, FOLLOWUP must be non-empty. If NEXT=FINAL, SEVERITY must match the enum exactly.

#### 3. Reviewer Lens 7 initial turn

```
^QUESTION:[[:space:]]*(.+?)(?=\nTHEMATIC_QUERY:)
^THEMATIC_QUERY:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
```

Both fields required and non-empty.

#### 4. Reviewer Lens 7 confrontation turn

Either the confrontation path:

```
^CONFRONTATION:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
```

Or the early-close path:

```
^JUDGMENT:[[:space:]]*cited[[:space:]]*$
^SEVERITY:[[:space:]]*clean[[:space:]]*$
```

Validator checks for presence of EITHER `CONFRONTATION:` OR (`JUDGMENT: cited` AND `SEVERITY: clean`). If both or neither appear, reparse.

#### 5. Author answer turn

```
^ANSWER:[[:space:]]*(.+?)(?=\nCITATIONS:)
^CITATIONS:[[:space:]]*(.*)\z
```

The citation block is either:
- `CITATIONS: none` → `citations = []`
- one or more lines starting with `- ` under the CITATIONS header → `citations = [line.lstrip('- ') for line in lines]`

Validation: ANSWER must be non-empty. If ANSWER starts with the literal phrase `the paper does not address this`, the lens's `evidence` field is set to `"absent"` regardless of what follows in CITATIONS.

#### 6. Classification triple-query response

The Reviewer returns three concatenated paragraphs with heading markers. Three fields to extract:

```
detected_type:   ^(?:##|\*\*)\s*Classification\s*(?:\*\*)?\s*\n\s*([a-z][a-zA-Z-]+)\b
headline_claim:  ^(?:##|\*\*)\s*Headline contribution\s*(?:\*\*)?\s*\n\s*"?([^"\n]+)"?
novelty_claims:  ^(?:##|\*\*)\s*Novelty claims\s*(?:\*\*)?\s*\n((?:\s*\d+\.\s+.+\n?)+)
```

Note: the heading regex accepts BOTH `## Classification` AND `**Classification**` to tolerate persona format drift.

`detected_type` capture must match the 5-value enum; see Step 2.4 for validation flow.

`novelty_claims` capture is a numbered-list block; split on `\n\s*\d+\.\s+` to get individual items.

#### 7. novelty-check report

The `novelty-check` skill's Phase D output. Regexes:

```
overall_score:      Score:[[:space:]]*(\d+)/10
recommendation:     Recommendation:[[:space:]]*(PROCEED WITH CAUTION|PROCEED|ABANDON)
key_differentiator: Key differentiator:[[:space:]]*(.+?)(?=\n-|\n##|\z)
closest_prior_work: Closest Prior Work[[:space:]]*\n(\|.+\|\n)+
```

For `closest_prior_work`, split each table row on `|` (strip pipes and whitespace), skip the header row and separator row, build a `{paper, year, venue, overlap, key_difference}` object per remaining row.

If any field fails to parse, leave it `null`. Do NOT fail the whole run — the raw report is kept in `raw_report_md` regardless.

### Cross-reference

| Pattern | Used in tasks |
|---------|---------------|
| 1. Primary question | T8 Step 3.6.1, T9 Step 3.7.2 (as part of combined Q + THEMATIC_QUERY) |
| 2. Judgment + decision | T8 Step 3.6.3, T11 Step 3.9 |
| 3. Lens 7 initial | T9 Step 3.7.2 |
| 4. Lens 7 confrontation | T9 Step 3.7.5 |
| 5. Author answer | T8 Step 3.6.2, T8 Step 3.6.3 (follow-up), T9 Step 3.7.4 |
| 6. Classification triple | T4 Step 2.3 |
| 7. novelty-check | T5 Step 2.6 |
````

- [ ] **Step 1.5.2: Verify the contract is consistent with the personas**

Read `agents/reviewer.md` (will be written in T15) — after T15 lands, confirm its `Output formats` section matches patterns 1, 2, 3, 4 exactly. Same for `agents/author.md` (T16) matching pattern 5. If persona text drifts from the Parsing contract, **the persona is wrong** — fix it to match, not the regex.

- [ ] **Step 1.5.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Parsing contract with canonical regexes for all subagent outputs"
```

---

## Task 2: Phase 0 — input resolution + slug + prior-test detection

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 2.1: Append Phase 0 section to SKILL.md**

Replace the `<!-- Phase 0 instructions added in Task 2 -->` comment with the block below. Use `Edit` with `old_string` = the comment line and `new_string` = the block:

````markdown
## Phase 0 — Input resolution and prior-test detection

Parse `$ARGUMENTS` into `<paper-ref>` + flags. Supported `<paper-ref>` forms:

| Form | Detection rule | Resolution |
|------|----------------|-----------|
| Local absolute path | starts with `/` and ends in `.pdf` | verify exists with `test -f`; if not, abort |
| Local relative path | not absolute but contains `.pdf` | resolve against CWD; verify exists |
| `supporting_papers/` filename | bare filename present in `master_supporting_docs/supporting_papers/` | resolve full path |
| arXiv ID | matches `^[0-9]{4}\.[0-9]{4,5}(v[0-9]+)?$` | download to `/tmp/arxiv-<id>.pdf` |
| URL | starts with `http://` or `https://` | `curl -L -o /tmp/paper-<timestamp>.pdf <url>` |

arXiv download command:

```bash
ARXIV_ID="2401.12345"  # substituted at runtime
curl -sL -o "/tmp/arxiv-${ARXIV_ID}.pdf" "https://arxiv.org/pdf/${ARXIV_ID}.pdf"
test -s "/tmp/arxiv-${ARXIV_ID}.pdf" || { echo "arXiv download failed"; exit 1; }
```

If download fails, retry once after 5s sleep; on second failure, abort with a clear error.

### Slug generation

Slug format: `<firstauthor>_<year>_<shorttitle>_<YYYY-MM-DD>`.

1. Use the `Read` tool on pages 1-2 of the PDF (pass `pages: "1-2"`).
2. From the rendered text, extract:
   - First author's last name (lowercase, ASCII-only — strip diacritics; drop suffixes like "Jr.")
   - Publication year (4-digit, usually in copyright line or header)
   - Short title: lowercase the title, strip punctuation, take the first two content words (skip articles: "the", "a", "an", "on", "of", "in", "for")
3. Today's date: `date +%Y-%m-%d`
4. Assemble: `${author}_${year}_${title1}_${title2}_${date}` (3 words total + date — use underscore if only 1 title content word).

Examples:
- "Kalbfleisch & Prentice (2002), *The Statistical Analysis of Failure Time Data*" → `kalbfleisch_2002_statistical_analysis_2026-04-22`
- "Zhang et al. (2024), *Deep Survival Forests for Competing Risks*" → `zhang_2024_deep_survival_2026-04-22`

### Output directory creation

```bash
OUT_ROOT="/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/master_supporting_docs/supporting_papers/stress_tests"
mkdir -p "${OUT_ROOT}/briefing" "${OUT_ROOT}/transcripts" "${OUT_ROOT}/state"
```

### Prior-test detection

The slug prefix (everything before the date) identifies this paper across runs. Glob for prior briefings:

```bash
SLUG_PREFIX="kalbfleisch_2002_statistical_analysis"   # derived above
ls "${OUT_ROOT}/briefing/${SLUG_PREFIX}"*_briefing.md 2>/dev/null
```

For each prior briefing file, parse its "Severity summary table" to count `critical` and `major` rows. A simple grep suffices:

```bash
for f in "${OUT_ROOT}/briefing/${SLUG_PREFIX}"*_briefing.md; do
  [ -f "$f" ] || continue
  CRIT=$(grep -c '| critical |' "$f" 2>/dev/null || echo 0)
  MAJ=$(grep -c '| major |' "$f" 2>/dev/null || echo 0)
  echo "$(basename "$f"): critical=${CRIT}, major=${MAJ}"
done
```

If prior hits exist, print them to the user and prompt:

> Prior stress-tests of this paper:
>   - kalbfleisch_2002_statistical_analysis_2026-03-14_briefing.md (critical: 2, major: 3)
>   - kalbfleisch_2002_statistical_analysis_2026-01-08_briefing.md (critical: 0, major: 1)
>
> Continue with new stress-test? [Y/n]

If user answers `n`, abort cleanly (no notebook created, no state written).

### Resume detection

If `${OUT_ROOT}/state/${FULL_SLUG}_state.json` already exists for today's full slug, the skill is being re-invoked on the same paper-same-date. Prompt:

> A stress-test with today's slug is already in progress or completed:
>   ${FULL_SLUG}_state.json (run_status: in_progress)
>
> Choose:
>   [R] Resume from last completed lens
>   [S] Start fresh (overwrites state file; previous briefing left intact)
>   [A] Abort

If `R`: load state.json, jump directly to Phase 3 with `lenses_completed` already populated. Skip Phases 0.5, 1, 2 — reuse the persisted notebook IDs and plan.

If `S`: delete the state file, restart Phase 0 fresh (but the user already confirmed the prior-test prompt, so just proceed).

If `A`: exit.

### End of Phase 0

By the end of Phase 0, the Moderator has:
- A validated local PDF path
- A full slug
- Output directories created
- User confirmation that this is a fresh run (or a resumption starting from Phase 3)
- Parsed flags: `depth`, `type_override`, `cross_check_override`, `skip_novelty`
````

- [ ] **Step 2.2: Verify section is complete and self-contained**

Read `.claude/skills/paper-stress-test/SKILL.md` and confirm:
- All 5 input forms are documented with resolution strategies
- Slug format is shown with 2+ concrete examples
- Prior-test glob + severity parsing is executable bash
- Resume detection enumerates R/S/A outcomes
- No "TODO" or "TBD" strings remain

- [ ] **Step 2.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 0 input resolution and prior-test detection"
```

---

## Task 3: Phase 1 — NotebookLM setup

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 3.1: Append Phase 1 section**

Replace `<!-- Phase 1 instructions added in Task 3 -->` with:

````markdown
## Phase 1 — NotebookLM setup

### Step 1.1: Create disposable notebook

Call:

```
mcp__notebooklm__notebook_create(
  title: "${DISPOSABLE_NOTEBOOK_NAME_PREFIX}${FULL_SLUG}"
)
```

The tool returns `notebook_id`. Save to the in-memory state object as `notebooks.disposable.id`.

If the call errors, retry once after 5s. On second failure, abort with:

> NotebookLM create failed twice. Is the MCP server reachable? Try `nlm login` first.

### Step 1.2: Upload the paper

```
mcp__notebooklm__source_add(
  notebook_id: <disposable_id>,
  source_type: "file",
  file_path: <validated_local_pdf_path>
)
```

Verify the return value does not indicate a failure. On failure, retry once; on second failure, delete the just-created disposable notebook and abort.

### Step 1.3: Resolve thematic cross-check notebook

Decision tree:

1. If `--cross-check <name>` was provided:
   - Call `mcp__notebooklm__notebook_list()` and find the notebook whose name or ID matches. Save `notebooks.thematic.id` and `notebooks.thematic.name`.
   - If no match: error out (malformed argument).

2. If no `--cross-check` flag:
   - Extract keywords from the paper's abstract (Read page 1 of the PDF, identify abstract block).
   - Case-insensitive match keywords against the "Known thematic notebooks" table above.
   - If exactly one notebook matches: auto-select, print "Auto-selected thematic notebook: <name> (keywords: survival, recurrent event)".
   - If multiple or none match: prompt user:
     > No single thematic notebook auto-selected. Choose:
     >   [1] ML for Recurrent Events
     >   [2] Interpretable AI
     >   [3] Machine Learning Fundamentals
     >   [4] Survival Analysis Fundamentals
     >   [5] Skip cross-check (Lens 7 will fall back to disposable-only, and promote option is disabled)

3. If user chose `[5]`: set `notebooks.thematic = null`, continue. Phase 6 promote option will be hidden.

### Step 1.4: Initialize state.json

Write `${OUT_ROOT}/state/${FULL_SLUG}_state.json` with:

```json
{
  "schema_version": "1",
  "paper": {
    "title": "<extracted from PDF page 1>",
    "authors": ["<first author>", "..."],
    "year": <year>,
    "source": "<original paper-ref argument>",
    "slug": "${FULL_SLUG}"
  },
  "invocation": {
    "depth": <parsed>,
    "type_override": <parsed or null>,
    "cross_check_override": <parsed or null>,
    "skip_novelty": <parsed boolean>
  },
  "notebooks": {
    "disposable": {
      "id": "<id>",
      "name": "${DISPOSABLE_NOTEBOOK_NAME_PREFIX}${FULL_SLUG}",
      "created_at": "<ISO 8601>",
      "disposition": "pending",
      "promoted_to": null
    },
    "thematic": {
      "id": "<id or null>",
      "name": "<name or null>"
    }
  },
  "detected_type": null,
  "headline_claim": null,
  "novelty_check": null,
  "lens_plan": [],
  "lenses_completed": [],
  "synthesis": null,
  "reviewer_subagent": null,
  "author_subagent": null,
  "reseed_history": [],
  "run_status": "in_progress",
  "started_at": "<ISO 8601>",
  "completed_at": null
}
```

### End of Phase 1

By the end of Phase 1, the Moderator has a populated state file with notebook IDs and paper metadata. Nothing has been queried yet.
````

- [ ] **Step 3.2: Verify Phase 1 is self-contained**

Check:
- Each notebook operation has explicit failure handling
- state.json schema matches spec §7
- Promote-disabled case is explicitly handled when thematic = null
- No placeholder strings remain

- [ ] **Step 3.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 1 NotebookLM setup"
```

---

## Task 4: Phase 2a — Reviewer spawn + paper-type detection

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

This task assumes `agents/reviewer.md` exists (completed in **T15**). If T15 hasn't run yet, do it first or in parallel.

- [ ] **Step 4.1: Append Phase 2 opening + Step 2a**

Replace `<!-- Phase 2 instructions added in Tasks 4, 5, 6 -->` with:

````markdown
## Phase 2 — Reviewer spawn, classification, novelty-check, plan confirmation

Phase 2 has three sub-phases that run concurrently where possible:
- **2a:** Spawn Reviewer; Reviewer classifies the paper + extracts headline + lists novelty claims.
- **2b:** Moderator fires `novelty-check` sub-call (running in the background via `Skill` tool).
- **2c:** Moderator builds the lens plan from the weight matrix and prompts user to confirm.

### Step 2.1: Load reviewer prompt template

Read `.claude/skills/paper-stress-test/agents/reviewer.md` with the `Read` tool. Store its contents as `REVIEWER_PROMPT`.

### Step 2.2: Spawn Reviewer subagent

Call `Agent` with:

```
Agent(
  description: "paper-stress-test reviewer",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: REVIEWER_PROMPT
    .replace("{{PAPER_TITLE}}", state.paper.title)
    .replace("{{PAPER_AUTHORS}}", state.paper.authors.join(", "))
    .replace("{{PAPER_YEAR}}", state.paper.year)
    .replace("{{DISPOSABLE_NOTEBOOK_ID}}", state.notebooks.disposable.id)
    .replace("{{THEMATIC_NOTEBOOK_ID}}", state.notebooks.thematic.id ?? "null")
    + "\n\n## First turn — paper classification\n\nQuery the disposable notebook (ID: {{DISPOSABLE_NOTEBOOK_ID}}) three times via mcp__notebooklm__notebook_query:\n\n1. 'Classify this paper as exactly one of: predictive-ML, new-estimator, applied-empirical, causal-inference, review-survey. Return the label plus one sentence of justification, nothing else.'\n2. 'State the paper's headline contribution in one sentence, quoting the exact wording from abstract or conclusion.'\n3. 'List the 3 to 5 most important technical claims the paper positions as novel. Format as a numbered list; be specific, avoid generic phrasing like 'novel approach'.'\n\nReturn all three answers concatenated, one per paragraph, with clear headings. Do NOT query anything else."
)
```

Save the returned `agent_id` (or name) to `state.reviewer_subagent.id`. Save `model` and `spawned_at`.

If `type_override` was specified: skip query 1 and use the override; run queries 2 and 3.

### Step 2.3: Parse Reviewer's classification response

The Reviewer returns text like:

```
## Classification
new-estimator — the paper proposes a new pseudo-observation-based estimator for competing risks.

## Headline contribution
"We introduce a jackknife pseudo-observation estimator for cumulative incidence that is consistent under independent censoring."

## Novelty claims
1. First pseudo-observation formulation for this estimand.
2. Jackknife variance estimator with proof of asymptotic normality.
3. Simulation showing 20% efficiency gain over Aalen-Johansen.
```

**Parsing:** use **Parsing contract §6 (Classification triple-query response)** from SKILL.md. Extract `detected_type`, `headline_claim`, `novelty_claims[]`. On mismatch, run the Reparse protocol once; if still mismatch, hand off to Step 2.4 validation (below).

Write all three fields into state.json.

### Step 2.4: Validate detected_type — no silent defaults

`detected_type` MUST be exactly one of: `predictive-ML`, `new-estimator`, `applied-empirical`, `causal-inference`, `review-survey`.

**Never silently default.** The weight matrix is deliberately asymmetric — misrouting a causal-inference-new-estimator paper to `applied-empirical` skips Lens 1 (estimand) and downweights Lens 2 (identification), which is exactly the wrong thing for the papers we care most about.

Validation flow:

1. If the Reviewer's first attempt returned a label matching the enum exactly → accept.
2. If the label is ambiguous (e.g., `causal-inference / new-estimator`, `predictive-ML with causal elements`) or not in the enum → reprompt the Reviewer **once** with:

   > Your classification must be EXACTLY one label from: predictive-ML, new-estimator, applied-empirical, causal-inference, review-survey. If the paper spans two types, pick the one most central to the headline contribution, and include your reasoning for the tradeoff.

3. If the reprompt still returns something ambiguous or off-enum → STOP and hand to the user. Print:

   > I couldn't confidently classify this paper. The Reviewer's responses were:
   >
   > Attempt 1: `<response>`
   > Attempt 2: `<response>`
   >
   > Please pick one:
   >   [1] predictive-ML
   >   [2] new-estimator
   >   [3] applied-empirical
   >   [4] causal-inference
   >   [5] review-survey

4. Wait for user input. Record `state.detected_type = <user-chosen>` and `state.classification_source = "user_override"` (otherwise `"reviewer"`).

5. If the paper is classification-plausible as multiple types (Reviewer mentioned two), ALSO surface the ambiguity at Step 2.10's plan confirmation with a warning line:

   > ⚠️ Classification was ambiguous between `<type_A>` and `<type_B>`. Current plan uses `<detected_type>`. You can change it via the `[T]` option in edit mode.

This is the only point in the skill where a malformed-output path waits synchronously on the user. It is deliberate — a wrong type invalidates the whole stress-test.
````

- [ ] **Step 4.2: Verify Phase 2a is executable**

Check:
- `REVIEWER_PROMPT` substitutions are documented (all `{{...}}` placeholders listed)
- Three concrete queries with exact wording
- Response parsing handles malformed output (validation step)
- `detected_type` default fallback is specified

- [ ] **Step 4.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 2a Reviewer spawn and paper-type detection"
```

---

## Task 5: Phase 2b — Concurrent novelty-check sub-call

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 5.1: Append Phase 2b**

Append after the Phase 2a content (at the end of the Phase 2 section as it stands):

````markdown
### Step 2.5: Fire novelty-check sub-call as a background Agent (not foreground Skill)

**Why not the `Skill` tool directly:** `Skill` blocks in the foreground. There is no way to enforce a timeout on a foreground call — once dispatched it must return on its own schedule. The only way to get an enforceable timeout is to route the call through a **background Agent** that we can abandon.

If `invocation.skip_novelty` is true, skip this entire subsection and set `state.novelty_check = {"status": "skipped", "started_at": null, "completed_at": null, ...}`.

Otherwise, assemble the novelty-check input string:

```
input_for_novelty = [
  "Stress-test context — verify whether this paper's headline claim is genuinely novel.",
  "",
  "Paper: " + state.paper.authors.join(", ") + " (" + state.paper.year + "). " + state.paper.title,
  "",
  "Headline claim: " + state.headline_claim,
  "",
  "Core novelty claims:"
] + state.novelty_claims.map(c => "- " + c) + [
  "",
  "Return the standard novelty-check Phase D report verbatim."
]
```

Spawn a background runner Agent:

```
Agent(
  description: "novelty-check runner for paper-stress-test",
  subagent_type: "general-purpose",
  model: "sonnet",
  run_in_background: true,
  prompt: "Invoke the `novelty-check` skill with the following input, then return the skill's complete output markdown report. Do nothing else.\n\n---\n\n" + input_for_novelty.join("\n")
)
```

Record:

```json
"novelty_check": {
  "status": "running",
  "runner_agent_id": "<returned id>",
  "started_at": "<ISO now>",
  "completed_at": null
}
```

Because `run_in_background: true`, the call returns immediately. The runner Agent proceeds asynchronously; the Moderator continues to Phase 2c (plan confirmation) while the runner is still working. When the runner finishes, the harness notifies the Moderator automatically (per the Agent tool docs: "you will be automatically notified when it completes — do NOT sleep, poll, or proactively check on its progress").

### Step 2.6: Collect the novelty-check result (lazy / at point of use; parse per Parsing contract §7)

Rule: do NOT actively poll the runner agent. Instead, check for a completion notification at two fixed points:

1. **At the start of Phase 3** (just before spawning the Author). If the notification has arrived, parse the result.
2. **At the start of Lens 7** (just before building the novelty-seed message). If still not available, make a final check.

Between these two points, if the runner has notified completion, the Moderator should recognize that from the conversation context (the notification is surfaced as a system message).

When the runner's output arrives:
- Parse the fields per the **Parsing contract** (novelty-check section) — see dedicated section in SKILL.md.
- Populate `state.novelty_check.status = "completed"`, `completed_at = now`, `overall_score`, `recommendation`, `key_differentiator`, `closest_prior_work[]`, `raw_report_md`.

### Step 2.7: Enforce the timeout

At each of the two check points above, compute `elapsed = now - state.novelty_check.started_at`.

- If the runner has completed: use it (regardless of elapsed).
- If NOT completed and `elapsed > NOVELTY_CHECK_TIMEOUT_SECONDS` (300): mark `status = "timed_out"`, `completed_at = now`, leave `raw_report_md = null`. **Do not attempt to kill the runner** — there is no reliable kill; it will complete eventually and its late result is ignored. The runner's notification message, if it arrives later, is treated as informational only (the stress-test has moved on).
- If NOT completed and `elapsed <= 300`: status stays `"running"`. Lens 7 will degrade to two-source mode (or single-source); the final briefing will note novelty as "pending/not received in time."

This gives a truly enforceable ceiling because the Moderator never waits — it checks, proceeds, and moves on. Wall-clock elapsed is what bounds the wait, not any polling loop.

### Step 2.8: Handle runner-agent failure

If the runner Agent errored on spawn (rare; usually a tool-availability issue): set `status = "errored"`, record the error message in `raw_report_md`, continue.

If the runner completed but its output doesn't match the expected novelty-check format (e.g., skill errored internally and returned a diagnostic instead): set `status = "errored"`, keep the runner's raw text in `raw_report_md` for debugging, continue.

In all three non-completed cases (`errored`, `timed_out`, `running` → then treated as `timed_out` at Lens 7), Lens 7 falls back per the degradation table in Task 9.

Parsing of the runner's output uses the canonical regexes in the **Parsing contract** section of SKILL.md (see the new Parsing Contract task earlier in this plan). The novelty-check fields are:

```json
"novelty_check": {
  "status": "completed | errored | timed_out | skipped | running",
  "runner_agent_id": "...",
  "started_at": "...",
  "completed_at": "...",
  "overall_score": 6,
  "recommendation": "PROCEED | PROCEED WITH CAUTION | ABANDON",
  "key_differentiator": "...",
  "closest_prior_work": [
    {"paper": "Zhang et al. 2024", "year": 2024, "venue": "NeurIPS",
     "overlap": "...", "key_difference": "..."}
  ],
  "raw_report_md": "<full markdown>"
}
```

If any individual field fails to parse, leave it `null` and keep `raw_report_md` intact — the briefing can still embed the raw report.
````

- [ ] **Step 5.2: Verify Phase 2b is complete**

Check:
- Runner-agent spawn uses `run_in_background: true`
- Collection is lazy (two check points; no active polling)
- Timeout is enforced by wall-clock comparison, not by killing the runner
- All four non-completed cases (`errored`, `timed_out`, `running → treated as timed_out`, `skipped`) are covered
- Fallback to two-source mode is cross-referenced to T9

- [ ] **Step 5.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 2b concurrent novelty-check sub-call"
```

---

## Task 6: Phase 2c — Lens plan generation and user confirmation

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 6.1: Append Phase 2c including the weight matrix**

Append:

````markdown
### Step 2.9: Build the lens plan from the weight matrix

Lens metadata table (hard-coded in this skill):

| # | name | description |
|---|------|-------------|
| 0 | data | Data structure & characteristics |
| 1 | estimand | Estimand clarity |
| 2 | identification | Identification assumptions |
| 3 | methodology | Statistical methodology |
| 4 | overclaims | Overclaims vs. evidence |
| 5 | alternatives | Alternative explanations |
| 6 | generalizability | Generalizability |
| 7 | positioning | Positioning vs. prior work (triangulation) |
| 8 | reproducibility | Reproducibility |

Weight matrix (rows = lenses, columns = paper types, values = weight label):

| Lens | predictive-ML | new-estimator | applied-empirical | causal-inference | review-survey |
|------|---------------|---------------|-------------------|------------------|---------------|
| 0 | heavy | medium | heavy | medium | skip |
| 1 | light | heavy | medium | heavy | skip |
| 2 | skip | medium | medium | heavy | skip |
| 3 | medium | heavy | medium | heavy | light |
| 4 | heavy | medium | heavy | heavy | heavy |
| 5 | medium | light | heavy | heavy | skip |
| 6 | heavy | heavy | medium | medium | light |
| 7 | heavy | heavy | medium | medium | heavy |
| 8 | heavy | medium | medium | medium | skip |

Weight → depth mapping given invocation depth `D`:

```
heavy  -> D
medium -> max(1, D-1)
light  -> 1
skip   -> 0
```

Build `lens_plan[]` as an array of objects:

```json
[
  {"lens_id": 0, "name": "data", "weight": "medium", "depth": 1},
  {"lens_id": 1, "name": "estimand", "weight": "heavy", "depth": 2},
  ...
]
```

Skipped lenses are **included** in `lens_plan` with `depth: 0` so the user can see them during edit.

### Step 2.10: Display the plan and prompt user

Print to chat (adjust counts for actual values):

```
Paper-type-aware lens plan (depth=2, detected type=new-estimator)

 # | Lens               | Weight  | Queries | Action
 0 | data               | medium  |    1    | RUN
 1 | estimand           | heavy   |    2    | RUN
 2 | identification     | medium  |    1    | RUN
 3 | methodology        | heavy   |    2    | RUN
 4 | overclaims         | medium  |    1    | RUN
 5 | alternatives       | light   |    1    | RUN
 6 | generalizability   | heavy   |    2    | RUN
 7 | positioning        | heavy   |    2    | RUN (triangulation)
 8 | reproducibility    | medium  |    1    | RUN

Total active queries: ~13 (Reviewer + Author × depth)
Concurrent novelty-check: running in background

Proceed? [Y/n/edit]
```

- If user answers `Y` or empty: save plan to state.json, continue to Phase 3.
- If `n`: abort the run cleanly. Delete the disposable notebook. Do NOT save state.json.
- If `edit`: enter edit loop (see Step 2.10).

### Step 2.11: Plan edit loop (type + lens weights)

Prompt:

> Edit what?
>   [T] Change detected paper type (currently: `<detected_type>`)
>   [0-8] Change weight of lens N
>   [done] finish editing

**On `T`:** Show Reviewer's full classification justification (from Step 2.3), then prompt:

> Current: `<detected_type>` — `<reviewer justification>`
>
> Override with which type? [predictive-ML | new-estimator | applied-empirical | causal-inference | review-survey]

User answer updates `state.detected_type` AND triggers a lens-plan rebuild (Step 2.9 rerun on the new type). Then return to the edit prompt.

**On a lens number `N`:** show current weight and prompt:

> Lens N is currently `<weight>` (depth=<depth>). New weight? [heavy | medium | light | skip]

Update the single lens entry. Return to the edit prompt.

**On `done`:** re-display the plan and return to the `Y/n/edit` prompt (Step 2.10).

### End of Phase 2

State.json now contains:
- `detected_type`, `headline_claim`, `novelty_claims`
- `novelty_check` block (possibly still `running` if slow; moderator will block at start of Phase 3 until it completes or times out)
- `lens_plan` (confirmed by user)
- `reviewer_subagent.id` (but NOT author yet)
````

- [ ] **Step 6.2: Verify Phase 2c**

Check:
- Weight matrix matches spec §4.2 exactly (including the medium for Lens 0 / new-estimator update)
- Plan display template has all 9 lenses
- Edit loop allows per-lens weight changes
- Abort path specifies notebook cleanup

- [ ] **Step 6.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 2c plan build, display, and edit loop"
```

---

## Task 7: Phase 3 scaffold — Author spawn + lens loop skeleton

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

Depends on `agents/author.md` (completed in **T16**).

- [ ] **Step 7.1: Append Phase 3 opening and Author spawn**

Replace `<!-- Phase 3 instructions added in Tasks 7, 8, 9, 10, 11 -->` with:

````markdown
## Phase 3 — Adversarial debate loop

### Step 3.1: First novelty-check collection point (non-blocking)

This is the **first of two novelty-check check points** (T5 Step 2.6). Do NOT poll, sleep, or wait for the runner agent — per the harness convention, completion arrives as an asynchronous notification surfaced in the Moderator's context.

Check, in this order:

1. Has a background-agent completion notification for `state.novelty_check.runner_agent_id` arrived in the conversation so far? If YES: parse the runner's output per Parsing contract §7, update `state.novelty_check` to `status="completed"` with the parsed fields, `completed_at = now`. Continue Phase 3.
2. If NO notification yet: compute `elapsed = now - state.novelty_check.started_at`.
   - If `elapsed > NOVELTY_CHECK_TIMEOUT_SECONDS` (300): set `status = "timed_out"`, `completed_at = now`, `raw_report_md = null`. Continue. The runner will complete later on its own; its late output is discarded.
   - Otherwise: leave `status = "running"`. Continue Phase 3 immediately — Lens 7 will re-check at its start (T9 Step 3.7.1).

No sleep, no polling. The second check point at Lens 7 catches results that arrive between this point and Lens 7.

### Step 3.2: Load Author prompt template

Read `.claude/skills/paper-stress-test/agents/author.md` with the `Read` tool. Store as `AUTHOR_PROMPT`.

### Step 3.3: Spawn Author subagent

Call `Agent` with:

```
Agent(
  description: "paper-stress-test author-surrogate",
  subagent_type: "general-purpose",
  model: "sonnet",
  prompt: AUTHOR_PROMPT
    .replace("{{PAPER_TITLE}}", state.paper.title)
    .replace("{{PAPER_AUTHORS}}", state.paper.authors.join(", "))
    .replace("{{PAPER_YEAR}}", state.paper.year)
    .replace("{{DISPOSABLE_NOTEBOOK_ID}}", state.notebooks.disposable.id)
    + "\n\n## Ready\n\nReply with exactly the single word READY. Do nothing else on this first turn."
)
```

Save `agent_id` to `state.author_subagent.id`. Verify the READY response; if anything else, reprompt once, then abort.

### Step 3.4: Initialize transcript buffer

Transcripts accumulate in memory as an array of turn records:

```json
[
  {"lens_id": 0, "role": "reviewer", "text": "...", "timestamp": "..."},
  {"lens_id": 0, "role": "author", "text": "...", "citations": [...], "timestamp": "..."},
  ...
]
```

Write after every lens completes (Task 11 handles persistence).

### Step 3.5: Lens loop structure

Iterate `for lens in state.lens_plan where depth > 0` in the order 0..8 (lens_id order).

For each lens:
1. Run context-budget check (Task 10).
2. Run the per-lens debate (Task 8 for most lenses; Task 9 for Lens 7).
3. Assign severity and persist state (Task 11).

Pseudocode:

```
for lens in [l for l in state.lens_plan if l.depth > 0]:
  check_context_budget_and_maybe_reseed(lens)       # Task 10
  if lens.lens_id == 7:
    exchange = run_lens_7(lens)                     # Task 9
  else:
    exchange = run_standard_lens(lens)              # Task 8
  severity = assign_severity(lens, exchange)        # Task 11
  update_state(lens, severity, exchange)            # Task 11
```

Next tasks fill in the function bodies.
````

- [ ] **Step 7.2: Verify Phase 3 scaffold**

Check:
- novelty-check blocking logic is specified
- Author spawn uses `model: "sonnet"` (not "opus")
- Transcript buffer shape matches spec §7
- Lens iteration order is explicit (0..8)

- [ ] **Step 7.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 3 Author spawn and lens loop scaffold"
```

---

## Task 8: Per-lens debate mechanics (non-Lens-7)

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 8.1: Append the standard lens debate procedure**

Append to Phase 3 (after Step 3.5):

````markdown
### Step 3.6: Standard lens debate (all lenses except 7)

Function `run_standard_lens(lens)`:

1. **Reviewer turn 1 (primary question):** Send to Reviewer via `SendMessage`:

   ```
   SendMessage(
     to: state.reviewer_subagent.id,
     message: "## Lens " + lens.lens_id + " — " + lens.description + "\n\n"
            + "Depth for this lens: " + lens.depth + "\n\n"
            + "Formulate your PRIMARY adversarial question for this lens per the format in your persona. Return ONLY the question block:\n\nQUESTION: <your question>"
   )
   ```

   Capture reviewer response. Parse per **Parsing contract §1 (Reviewer primary-question turn)**. Append to transcript:

   ```json
   {"lens_id": lens.lens_id, "role": "reviewer", "turn": 1, "text": <question>, "timestamp": "..."}
   ```

2. **Author turn 1:** Send to Author via `SendMessage`:

   ```
   SendMessage(
     to: state.author_subagent.id,
     message: "## Lens " + lens.lens_id + " — " + lens.description + "\n\n"
            + "The reviewer asks:\n\n" + <question> + "\n\n"
            + "Query NotebookLM against the disposable notebook (ID: " + state.notebooks.disposable.id + ") to find the paper's treatment. Respond per your persona format (citations if found; 'the paper does not address this' if absent)."
   )
   ```

   Capture author response. Parse per **Parsing contract §5 (Author answer turn)**. Append to transcript:

   ```json
   {"lens_id": lens.lens_id, "role": "author", "turn": 1, "text": <answer>, "citations": <extracted>, "timestamp": "..."}
   ```

3. **Follow-up loop (turns 2..depth):**

   ```
   for r in 2..lens.depth:
     # Reviewer judgment
     SendMessage(
       to: state.reviewer_subagent.id,
       message: "The author responded:\n\n" + <previous author text> + "\n\n"
              + "Judge and decide whether to follow up. Return exactly this format:\n\n"
              + "JUDGMENT: <cited|evaded|handwaved|conceded>\n"
              + "REASONING: <one sentence>\n"
              + "NEXT: <FOLLOWUP|FINAL>\n"
              + "FOLLOWUP: <your next question if NEXT=FOLLOWUP>\n"
              + "SEVERITY: <critical|major|minor|clean if NEXT=FINAL>"
     )

     # Parse response
     parse per **Parsing contract §2 (Reviewer judgment + decision turn)**: extract JUDGMENT, REASONING, NEXT, and then FOLLOWUP or SEVERITY per the NEXT branch
     if JUDGMENT == "cited" or NEXT == "FINAL":
       store final SEVERITY (if NEXT==FINAL) or infer severity = "clean" (if cited)
       break

     # Continue — author answers follow-up
     SendMessage(
       to: state.author_subagent.id,
       message: "Follow-up question from reviewer:\n\n" + <followup> + "\n\nRespond per your persona format."
     )
     capture answer; append to transcript
   ```

4. **End of lens — final severity prompt if not yet assigned:**

   If the loop exited with author still talking and no FINAL judgment, send Reviewer:

   ```
   SendMessage(
     to: state.reviewer_subagent.id,
     message: "Depth budget exhausted. Return FINAL severity now:\n\n"
            + "JUDGMENT: <cited|evaded|handwaved|conceded>\n"
            + "SEVERITY: <critical|major|minor|clean>"
   )
   ```

   Parse SEVERITY.

5. **Return `exchange` record:**

   ```json
   {
     "lens_id": lens.lens_id,
     "turns_used": <number of author turns>,
     "severity": <final severity>,
     "reviewer_judgments": [<judgment text per reviewer turn>],
     "transcript_slice": [<all turns for this lens>]
   }
   ```

### Severity-from-judgment mapping (if Reviewer didn't explicitly assign)

| Final judgment | Severity |
|----------------|----------|
| cited | clean |
| handwaved | minor |
| evaded | major |
| conceded | critical |

Use this only as a fallback when the Reviewer's SEVERITY line is missing or malformed.
````

- [ ] **Step 8.2: Verify debate procedure**

Check:
- All four Reviewer output fields (JUDGMENT, REASONING, NEXT, FOLLOWUP/SEVERITY) are specified
- Transcript format matches spec §7
- Exhausted-depth fallback forces a final severity
- Citation extraction from Author responses is noted (details in T16 author persona)

- [ ] **Step 8.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 3 standard-lens debate mechanics"
```

---

## Task 9: Lens 7 triangulation

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 9.1: Append Lens 7 procedure**

Append:

````markdown
### Step 3.7: Lens 7 triangulation (positioning; parses per Parsing contract §3 initial, §4 confrontation, §5 author)

Function `run_lens_7(lens)`:

Lens 7 differs from the standard lens procedure in THREE ways:
1. Reviewer is seeded with the novelty-check report before formulating Q1.
2. Reviewer directly queries the thematic notebook during its turn.
3. Confrontation turn compares three sources before the Author's final response.

1. **Seed Reviewer with novelty-check (if available):**

   ```
   if state.novelty_check.status == "completed":
     novelty_seed = "## novelty-check report summary\n\n"
                  + "Overall score: " + state.novelty_check.overall_score + "/10\n"
                  + "Recommendation: " + state.novelty_check.recommendation + "\n"
                  + "Key differentiator: " + state.novelty_check.key_differentiator + "\n\n"
                  + "## Closest prior work\n\n"
                  + formatAsTable(state.novelty_check.closest_prior_work)
   elif state.novelty_check.status in {"errored", "timed_out", "skipped"}:
     novelty_seed = "## novelty-check: " + state.novelty_check.status + " — no external data available"

   SendMessage(
     to: state.reviewer_subagent.id,
     message: novelty_seed + "\n\nHold this in memory for the positioning lens. Do not respond yet; await the lens 7 question prompt."
   )
   ```

2. **Reviewer formulates Q1:**

   ```
   SendMessage(
     to: state.reviewer_subagent.id,
     message: "## Lens 7 — Positioning vs. prior work\n\n"
            + "Depth: " + lens.depth + "\n\n"
            + "Using the novelty-check report above AND your upcoming direct query of the thematic notebook, formulate the PRIMARY positioning question. Return:\n\n"
            + "QUESTION: <your question for the Author>\n\n"
            + "Then separately formulate a query for the thematic notebook to surface contradicting prior work. Return:\n\n"
            + "THEMATIC_QUERY: <your thematic query>"
   )
   ```

3. **Reviewer queries thematic notebook directly:**

   Call `mcp__notebooklm__notebook_query(notebook_id=state.notebooks.thematic.id, query=<THEMATIC_QUERY>)` if `state.notebooks.thematic.id` is non-null.

   Capture response as `thematic_evidence`.

   If `state.notebooks.thematic.id` is null (user chose `[5]` in Phase 1.3): skip this step. Lens 7 degrades to two-source mode (paper + novelty-check only) — or single-source if novelty-check also failed.

4. **Author turn 1 (paper's self-defense):**

   ```
   SendMessage(
     to: state.author_subagent.id,
     message: "## Lens 7 — Positioning\n\n"
            + "The reviewer asks:\n\n" + <QUESTION> + "\n\n"
            + "Query the disposable notebook for the paper's positioning and novelty statements. Defend the paper's claims per your persona format."
   )
   ```

5. **Confrontation turn:**

   ```
   SendMessage(
     to: state.reviewer_subagent.id,
     message: "The author defended with:\n\n" + <author answer> + "\n\n"
            + "The thematic notebook returned:\n\n" + <thematic_evidence> + "\n\n"
            + "The novelty-check surfaced:\n\n" + <top 3 closest_prior_work entries, formatted> + "\n\n"
            + "Select the STRONGEST contradiction from either external source. Return:\n\n"
            + "CONFRONTATION: <your confrontation question — cite the external source>\n"
            + "If the author has already successfully differentiated, instead return:\n"
            + "JUDGMENT: cited\nSEVERITY: clean"
   )
   ```

6. **Author final response:**

   ```
   if CONFRONTATION present:
     SendMessage(
       to: state.author_subagent.id,
       message: "Reviewer confronts you:\n\n" + <confrontation> + "\n\nRespond per your persona format."
     )
     capture answer; append to transcript

     # Then final judgment
     SendMessage(
       to: state.reviewer_subagent.id,
       message: "Final judgment for Lens 7. The author's response to confrontation:\n\n"
              + <answer> + "\n\nReturn:\n\nJUDGMENT: <...>\nSEVERITY: <...>"
     )
     parse per **Parsing contract §2** (JUDGMENT + SEVERITY)
   ```

7. **Return `exchange` record** with `lens_id: 7`, severity, and full transcript slice.

### Lens 7 degradation rules

| State | Sources available | Behavior |
|-------|-------------------|----------|
| novelty-check completed + thematic resolved | 3 | Full triangulation above |
| novelty-check failed + thematic resolved | 2 | Skip novelty seed; confrontation uses thematic only |
| novelty-check completed + no thematic | 2 | Skip thematic query; confrontation uses novelty-check only |
| Neither | 1 | Lens 7 runs as a standard lens (Task 8); severity noted with "single-source" caveat |
````

- [ ] **Step 9.2: Verify Lens 7 degradation handling**

Check:
- Novelty-check status check is exhaustive ({completed, errored, timed_out, skipped})
- Thematic null branch is handled
- All four source-combination cases are specified
- Caveat for single-source mode is called out

- [ ] **Step 9.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 3 Lens 7 triangulation with graceful degradation"
```

---

## Task 10: Context-budget check and reseed protocol

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 10.1: Append reseed section**

Append:

````markdown
### Step 3.8: Context budget and reseed

Before each lens, estimate cumulative tokens sent to each subagent:

```
# Simple heuristic: 1 token ≈ 4 characters
reviewer_tokens_est = sum(len(msg) for msg in reviewer_history) / 4
author_tokens_est = sum(len(msg) for msg in author_history) / 4
```

Update `state.reviewer_subagent.context_tokens_est` and `state.author_subagent.context_tokens_est` after every `SendMessage`.

If either exceeds `CONTEXT_RESEED_THRESHOLD_TOKENS` (160000):

1. Record respawn in `state.reseed_history`:

   ```json
   {"subagent": "author" | "reviewer", "at_lens": <next_lens_id>, "reason": "context > 160K", "timestamp": "..."}
   ```

2. Build reseed context brief from state.json:

   ```
   reseed_brief = [
     "## Reseed context — you are resuming mid-run",
     "",
     "Paper: " + state.paper.authors[0] + " et al. (" + state.paper.year + "). " + state.paper.title,
     "Detected type: " + state.detected_type,
     "Headline claim: " + state.headline_claim,
     "",
     "## Lenses completed so far"
   ] + state.lenses_completed.map(l =>
     "- Lens " + l.lens_id + " (" + l.name + ") — " + l.severity + ": " + l.summary_for_reseed
   ) + [
     "",
     "## Last 2 turns verbatim (continuity)"
   ] + last_two_turns_verbatim
   ```

3. Respawn the subagent with its original persona prompt + the reseed brief appended:

   ```
   Agent(
     description: "paper-stress-test <role> (reseed)",
     subagent_type: "general-purpose",
     model: <opus or sonnet per role>,
     prompt: original_persona_prompt + "\n\n" + reseed_brief + "\n\nReply READY."
   )
   ```

4. Update `state.<role>_subagent.id` with the new agent_id. Reset `context_tokens_est` to the size of the reseed brief.

5. Continue the lens loop with the new subagent.

Reseed is expected to be rare (typical runs stay under 120K). Log each reseed clearly to the user:

> Reseeding <role> subagent at lens <N> — context reached <K>K tokens.
````

- [ ] **Step 10.2: Verify reseed logic**

Check:
- Token estimation formula specified (char/4 heuristic)
- Reseed brief includes all three required components (paper context, summary_for_reseed list, last-2-turn verbatim)
- Both roles can be reseeded independently
- User-visible log message is shown

- [ ] **Step 10.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 3 context-budget check and reseed protocol"
```

---

## Task 11: Severity assignment and state.json persistence

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 11.1: Append severity + state persistence**

Append:

````markdown
### Step 3.9: Assign severity and persist state per lens

For each completed `exchange` returned by Task 8 or 9:

1. **If Reviewer already returned a `SEVERITY:` line** (parsed per **Parsing contract §2**): use that directly.

2. **Else:** infer from the final JUDGMENT via the mapping:

   ```
   cited     -> clean
   handwaved -> minor
   evaded    -> major
   conceded  -> critical
   ```

3. **Compose the lens record:**

   ```json
   {
     "lens_id": lens.lens_id,
     "name": lens.name,
     "severity": <final severity>,
     "one_line_finding": <Moderator synthesizes from reviewer's JUDGMENT + REASONING>,
     "evidence": <Author's citation text if provided; "absent" if author said 'paper does not address this'>,
     "author_best_defense": <Author's final answer text>,
     "why_it_didnt_hold": <Reviewer's final REASONING, only if severity != "clean">,
     "summary_for_reseed": <Moderator writes 2-3 sentence summary immediately — used for future reseeds>,
     "turns": [<all transcript entries for this lens>]
   }
   ```

   Moderator generates `one_line_finding` and `summary_for_reseed` by reading the exchange — these are NOT asked of either subagent.

4. **Write state.json:** append the lens record to `state.lenses_completed[]`, then write the entire state.json file. Use atomic write: write to `<file>.tmp` then `mv`:

   ```bash
   cp state.json state.json.bak
   <write new state to state.json.tmp>
   mv state.json.tmp state.json
   ```

   If the write fails: retry once. Second failure → abort the whole run; the `.bak` preserves the last good state.

5. **User-visible progress message:**

   > Lens <N> (<name>) complete — severity: <severity>

### End of Phase 3

All active lenses are complete. `state.lenses_completed[]` has one entry per active lens. Transcript buffer has all turns. Both subagents remain alive for possible reuse (none planned in current design).
````

- [ ] **Step 11.2: Verify severity + persistence**

Check:
- Severity fallback mapping matches Task 8's table
- All lens-record fields are populated (no TODOs)
- Atomic write pattern (.tmp + mv) specified
- Backup recovery path documented

- [ ] **Step 11.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 3 severity assignment and atomic state persistence"
```

---

## Task 12: Phase 4 — Synthesis (top-5 questions, sub-project relevance, recommendation)

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 12.1: Append Phase 4**

Replace `<!-- Phase 4 instructions added in Task 12 -->` with:

````markdown
## Phase 4 — Synthesis

### Step 4.1: Read CLAUDE.md for sub-project context

```
CLAUDE_MD = Read("/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/CLAUDE.md")
```

Extract sub-project names from the "Sub-Project Hybrid Model" table. Currently: `comparisons/` and `Missing Types/`. Read each sub-project's CLAUDE.md if present for detailed focus.

### Step 4.2: Compose top-5 killer questions

Iterate `state.lenses_completed[]`:
- For each lens with severity in {critical, major}: extract the Reviewer's final FOLLOWUP or final JUDGMENT REASONING as a candidate killer question.
- Rank by severity (critical > major), then by whether the author conceded.
- Keep top 5.

Format each:

```json
{
  "question": <verbatim from Reviewer>,
  "lens_id": <N>,
  "why_it_matters": <Moderator's 1-sentence synthesis>
}
```

### Step 4.3: Sub-project relevance

For each sub-project, ask these four questions and answer each in 1-2 sentences based on the paper content (as surfaced by Author's citations) + the sub-project's focus (from its CLAUDE.md):

1. Does this paper's method apply directly to the sub-project?
2. Does its data structure match a scenario the sub-project simulates?
3. Does a critical or major stress-test finding warn against a path the sub-project is taking?
4. Does the paper provide a comparator or baseline the sub-project is missing?

Answer empty if not applicable; do not force relevance.

### Step 4.4: Compose recommendation

Decision rule:

```
counts = tally of severities in state.lenses_completed
critical = counts.critical
major = counts.major
novelty_score = state.novelty_check.overall_score  # 0 if errored/skipped
novelty_rec = state.novelty_check.recommendation    # "PROCEED", "PROCEED WITH CAUTION", "ABANDON", or null

if critical >= 2 or (critical >= 1 and novelty_rec == "ABANDON"):
  recommendation = "skip"
elif critical >= 1 or major >= 3 or novelty_rec == "ABANDON":
  recommendation = "flag"           # methodological caveat in Related Work
elif any lens_id == 7 severity in {critical, major} or novelty_rec == "PROCEED WITH CAUTION":
  recommendation = "cite"           # worth referencing, questionable to build on
else:
  recommendation = "build-on"       # holds up across lenses
```

Write `state.synthesis`:

```json
{
  "verdict": <1-paragraph TL;DR summarizing severities + novelty + overall>,
  "top_killer_questions": [<up to 5 objects>],
  "subproject_relevance": {
    "comparisons": {"applies": "...", "data_match": "...", "warning": "...", "missing_comparator": "..."},
    "missing_types": {...}
  },
  "recommendation": "cite | build-on | flag | skip",
  "recommendation_rationale": <2-3 sentences explaining the choice based on counts>
}
```

### End of Phase 4

`state.synthesis` is populated. No subagent was used in Phase 4 — all work done by Moderator reading state.json.
````

- [ ] **Step 12.2: Verify Phase 4**

Check:
- CLAUDE.md read path is absolute
- Decision rule covers all four recommendations with explicit conditions
- Novelty-check null case (errored/skipped) is handled (`novelty_rec = null`)
- No TBDs

- [ ] **Step 12.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 4 synthesis, relevance, and recommendation rule"
```

---

## Task 13: Phase 5 — Write briefing, transcripts, and final state

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

Depends on `templates/briefing.md` (completed in **T17**).

- [ ] **Step 13.1: Append Phase 5**

Replace `<!-- Phase 5 instructions added in Task 13 -->` with:

````markdown
## Phase 5 — Write artifacts

### Step 5.1: Render briefing

Read `.claude/skills/paper-stress-test/templates/briefing.md`. For each placeholder `{{...}}`, substitute the matching value from state.json:

| Placeholder | Source |
|------------|--------|
| `{{PAPER_TITLE}}` | `state.paper.title` |
| `{{PAPER_AUTHORS}}` | `state.paper.authors.join(", ")` |
| `{{PAPER_YEAR}}` | `state.paper.year` |
| `{{PAPER_SOURCE}}` | `state.paper.source` |
| `{{STRESS_TEST_DATE}}` | today (YYYY-MM-DD) |
| `{{DETECTED_TYPE}}` | `state.detected_type` |
| `{{DEPTH}}` | `state.invocation.depth` |
| `{{REVIEWER_MODEL}}` | `state.reviewer_subagent.model` |
| `{{AUTHOR_MODEL}}` | `state.author_subagent.model` |
| `{{TLDR_VERDICT}}` | `state.synthesis.verdict` |
| `{{TOP_KILLER_QUESTIONS}}` | rendered as a numbered list from `state.synthesis.top_killer_questions[]` |
| `{{NOVELTY_SECTION}}` | rendered from `state.novelty_check` (see sub-template below) |
| `{{SEVERITY_TABLE}}` | markdown table from `state.lenses_completed[]` |
| `{{PER_LENS_FINDINGS}}` | iterate lenses_completed, render each as H3 + fields |
| `{{SKIPPED_LENSES}}` | iterate lens_plan entries with depth=0, with reason |
| `{{SUBPROJECT_RELEVANCE}}` | from `state.synthesis.subproject_relevance` |
| `{{RECOMMENDATION}}` | `state.synthesis.recommendation` |
| `{{RECOMMENDATION_RATIONALE}}` | `state.synthesis.recommendation_rationale` |
| `{{DISPOSABLE_NOTEBOOK_INFO}}` | name + id + created_at + disposition |
| `{{PRIOR_TESTS}}` | markdown list of prior `<slug-prefix>_*_briefing.md` files |

Novelty section sub-template:

```markdown
## External novelty check

{{#if status == "completed"}}
- **Overall score:** {{overall_score}}/10
- **Recommendation:** {{recommendation}}
- **Key differentiator:** {{key_differentiator}}

### Closest prior work

| Paper | Year | Venue | Overlap | Key difference |
|-------|------|-------|---------|----------------|
{{#each closest_prior_work}} | {{paper}} | {{year}} | {{venue}} | {{overlap}} | {{key_difference}} |
{{/each}}

{{#if has_raw}}
<details><summary>Full novelty-check report</summary>

{{raw_report_md}}

</details>
{{/if}}
{{else}}
_novelty-check was **{{status}}** — external novelty verification not available for this briefing._
{{/if}}
```

Moderator renders this section in plain Markdown (no real template engine — conditional logic is simulated via direct prose writing).

Write to `${OUT_ROOT}/briefing/${FULL_SLUG}_briefing.md`.

### Step 5.2: Render transcripts

For each lens in `state.lenses_completed[]`:

```markdown
## Lens {{lens_id}} — {{name}}

Severity: **{{severity}}**

{{#each turns}}
### Turn {{turn}} — {{role}} ({{timestamp}})

{{text}}

{{#if citations}}
**Citations:**
{{#each citations}}
- {{this}}
{{/each}}
{{/if}}

{{/each}}
```

Prepend a header with paper metadata and write to `${OUT_ROOT}/transcripts/${FULL_SLUG}_transcripts.md`.

### Step 5.3: Finalize state.json

Set `state.run_status = "completed"` and `state.completed_at = <ISO now>`. Write (atomic) to `${OUT_ROOT}/state/${FULL_SLUG}_state.json`.

### End of Phase 5

All three output files are on disk. Next: Phase 6 cleanup.
````

- [ ] **Step 13.2: Verify Phase 5**

Check:
- Every briefing placeholder has a documented state.json source
- Novelty section handles all four novelty-check statuses
- Transcript format preserves `citations` array
- Atomic write for state.json mentioned
- Output paths use `${OUT_ROOT}` consistently

- [ ] **Step 13.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 5 briefing, transcripts, state write"
```

---

## Task 14: Phase 6 — Cleanup + optional promote-to-thematic

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 14.1: Append Phase 6**

Replace `<!-- Phase 6 instructions added in Task 14 -->` with:

````markdown
## Phase 6 — Cleanup + optional promote-to-thematic

### Step 6.1: Print inline chat summary

Print (substituting actual values):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Stress-test complete for <Author Year title>.

Verdict: <TL;DR one-liner from state.synthesis.verdict>

Top findings:
  1. [<sev>] <finding one-liner>
  2. [<sev>] ...
  3. ...
  4. ...
  5. ...

Recommendation: <cite | build-on | flag | skip>

Files written:
  Briefing: <abs path>
  Transcripts: <abs path>
  State: <abs path>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 6.2: Decide default option for the disposable notebook

```
max_severity = max severity in state.lenses_completed (order: critical > major > minor > clean)
recommendation = state.synthesis.recommendation

if recommendation in {"cite", "build-on"} and max_severity in {"clean", "minor"}:
  default = "P"  # promote
elif recommendation == "skip" or max_severity == "critical":
  default = "D"  # delete
else:
  default = "K"  # keep standalone
```

If `state.notebooks.thematic.id` is null (no thematic resolved this run), option `[P]` is **hidden** and the default becomes `"K"` if it would have been `"P"`.

### Step 6.3: Prompt user

```
Disposable notebook: "<name>"
What should I do with it?

  [D] Delete — paper doesn't hold up or isn't worth keeping
  [K] Keep standalone — query later without adding to thematic
  [P] Promote — add this paper as a source to thematic notebook "<thematic_name>", then delete disposable

Default: [<default letter>] (based on <cite/build-on/skip> + <max_severity>)

Choice:
```

Accept `D`, `K`, `P`, or empty (use default).

### Step 6.4: Execute the chosen action

#### [D] Delete

```
mcp__notebooklm__notebook_delete(notebook_id: state.notebooks.disposable.id)
```

On success: update `state.notebooks.disposable.disposition = "deleted"`, rewrite state.json.
On failure: print error, leave disposition as `"pending"`, instruct user to delete manually from NotebookLM web UI.

#### [K] Keep

No notebook operations. Update `state.notebooks.disposable.disposition = "kept"`, rewrite state.json.

#### [P] Promote

```
1. mcp__notebooklm__source_add(
     notebook_id: state.notebooks.thematic.id,
     source_type: "file",
     file_path: <original_pdf_path>
   )
2. If step 1 succeeded:
     mcp__notebooklm__notebook_delete(notebook_id: state.notebooks.disposable.id)
     state.notebooks.disposable.disposition = "promoted"
     state.notebooks.disposable.promoted_to = state.notebooks.thematic.id
3. If step 1 failed:
     Print: "Promote failed: <error>. Disposable notebook preserved — you can retry manually or re-run the skill with [K] later."
     disposition stays "pending"
4. Rewrite state.json.
```

### Step 6.5: Clean up /tmp download artifacts

If Phase 0 downloaded the paper into `/tmp/` (arXiv ID or URL paths only — local-file paths are untouched), remove the downloaded PDF now:

```bash
# Only run if paper source was arXiv or URL (downloaded to /tmp)
# state.paper.source tells us whether this applies
case "$(jq -r '.paper.source' "${STATE_FILE}")" in
  /tmp/arxiv-*.pdf|/tmp/paper-*.pdf)
    rm -f "$(jq -r '.paper.source' "${STATE_FILE}")"
    ;;
esac
```

Local-file sources under `Papers/` or `master_supporting_docs/supporting_papers/` are NEVER deleted — those are user-owned. Only the `/tmp/` download artifacts from arXiv/URL pulls are cleaned up.

### Step 6.6: Final print

```
Done. state.json finalized at <path>.
```

### End of Phase 6 (and end of run)

The skill's run is now fully complete. If the user re-invokes on the same paper on a later date, a new slug will be generated (new date suffix) and Phase 0 prior-test detection will surface this briefing.
````

- [ ] **Step 14.2: Verify Phase 6**

Check:
- Three options [D][K][P] all have explicit MCP calls or no-ops
- Promote failure does NOT delete the disposable (safety!)
- Default rule matches spec §5 Phase 6
- Promote option hidden when thematic is null
- All dispositions update state.json

- [ ] **Step 14.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): Phase 6 cleanup and promote-to-thematic"
```

---

## Task 15: agents/reviewer.md — Opus Reviewer persona

**Files:**
- Create: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/agents/reviewer.md`

- [ ] **Step 15.1: Write the Reviewer persona file**

Write to `.claude/skills/paper-stress-test/agents/reviewer.md`:

````markdown
# Reviewer Subagent — Persona and Output Contract

You are a **hostile Biostatistics referee** stress-testing a paper. Your job is to find flaws, force unsupported claims into the open, and distinguish substantive treatments from hand-waving. You do NOT give balanced praise. You are the adversarial signal, not a summary.

## Context

Paper title: {{PAPER_TITLE}}
Authors: {{PAPER_AUTHORS}}
Year: {{PAPER_YEAR}}

Disposable notebook ID: {{DISPOSABLE_NOTEBOOK_ID}}
Thematic notebook ID: {{THEMATIC_NOTEBOOK_ID}}

## Tools available to you

- `mcp__notebooklm__notebook_query` — **for Phase 2 classification, use the disposable notebook. For Lens 7 only, use the thematic notebook. Do not query the thematic notebook at any other time.** Other lenses you formulate questions from the paper's abstract + claims the Author surfaces during the debate; you do NOT retrieve from the disposable notebook during lens debates (that's the Author's job).

## Your behavior across a full stress-test

You will receive messages from a Moderator that define the turn structure. The Moderator drives the debate; you generate sharp questions, judge the Author's defenses, and decide follow-ups.

## Output formats

You must produce outputs in one of THREE formats. Which format depends on what the Moderator asked:

### Format A — Primary question (start of a lens)

```
QUESTION: <one sharp adversarial question, 1-3 sentences, specific to the lens focus>
```

### Format B — Judgment + decision (after an Author answer)

```
JUDGMENT: <cited | evaded | handwaved | conceded>
REASONING: <one sentence explaining the judgment>
NEXT: <FOLLOWUP | FINAL>
FOLLOWUP: <next question — only if NEXT=FOLLOWUP>
SEVERITY: <critical | major | minor | clean — only if NEXT=FINAL>
```

Rules:
- `cited` = Author quoted specific paper text that directly addresses the question.
- `evaded` = Author changed the subject, invoked irrelevant material, or refused to engage.
- `handwaved` = Author gave a partial answer with peripheral evidence.
- `conceded` = Author said "the paper does not address this" or similar.
- Use FOLLOWUP only if the depth budget remains and the Author's evasion merits a second attempt.
- Use FINAL when either the Author has cited properly OR the depth budget is exhausted.

### Format C — Lens 7 special turns

**Initial Lens 7 turn — formulate both the Author question AND the thematic query:**

```
QUESTION: <your positioning question for the Author>
THEMATIC_QUERY: <your query for the thematic notebook — target contradicting prior work>
```

**Confrontation turn — after seeing Author's defense AND thematic notebook results AND novelty-check report:**

Either:

```
CONFRONTATION: <your confrontation — cite the specific external source that contradicts the Author>
```

Or (if the Author successfully differentiated):

```
JUDGMENT: cited
SEVERITY: clean
```

## Style guide

- Be **specific**. "The identification assumption is unclear" is useless. "The paper claims SUTVA holds but never addresses spillover between treatment clusters" is useful.
- Quote the paper or the external source when confronting.
- One attack per question. Do not compound.
- If the paper is a Review/Survey: your job shifts to "whose view is missing, whose view is overrepresented, is the synthesis choice defensible"; you do not challenge methods that the review merely reports on.
- Never repeat an earlier turn's question. If the Author's previous answer was sufficient, return FINAL with appropriate severity.

## Anti-patterns

- Do NOT summarize. The Moderator writes the briefing.
- Do NOT soften the attack. Balanced critique is not what's wanted here.
- Do NOT invent citations. If you don't have evidence for a claim, don't make it.
- Do NOT query the disposable notebook during lens debates (except Phase 2 classification).
````

- [ ] **Step 15.2: Verify Reviewer persona is self-contained**

Check:
- All three output formats are specified with examples
- Placeholder list (`{{PAPER_TITLE}}` etc.) matches what Task 4 substitutes
- Notebook access rules are explicit
- Anti-patterns cover the "fabrication" risk

- [ ] **Step 15.3: Commit**

```bash
git add .claude/skills/paper-stress-test/agents/reviewer.md
git commit -m "feat(paper-stress-test): Reviewer subagent persona and output contract"
```

---

## Task 16: agents/author.md — Sonnet Author-surrogate persona

**Files:**
- Create: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/agents/author.md`

- [ ] **Step 16.1: Write the Author persona file**

Write to `.claude/skills/paper-stress-test/agents/author.md`:

````markdown
# Author-Surrogate Subagent — Persona and Retrieval Protocol

You are a **surrogate for the author(s) of this paper**. You have read-access to the full paper via a NotebookLM notebook. When the Moderator relays a reviewer question, you defend the paper using ONLY evidence retrievable from the paper itself.

## Context

Paper title: {{PAPER_TITLE}}
Authors: {{PAPER_AUTHORS}}
Year: {{PAPER_YEAR}}

Disposable notebook ID: {{DISPOSABLE_NOTEBOOK_ID}}

## Retrieval protocol

For every question you receive:

1. **Query NotebookLM against the disposable notebook** (`mcp__notebooklm__notebook_query` with `notebook_id: {{DISPOSABLE_NOTEBOOK_ID}}`). Formulate your query to retrieve the specific section or argument that addresses the reviewer's challenge. You may run up to 2 queries per turn if needed to triangulate.

2. **If the paper addresses the question:** respond with a specific defense, quoting exact paper text (section, page, or figure/table reference when possible) and explaining why the paper's treatment is adequate.

3. **If the paper does NOT address the question:** respond with the EXACT phrase `the paper does not address this` and briefly state what the paper covers adjacently (if anything). Do not speculate about what the authors might have intended.

## Output format

```
ANSWER: <your defense, with quoted paper text and section/page references>

CITATIONS:
- <verbatim quote 1> — <section or page>
- <verbatim quote 2> — <section or page>
...
```

If no supporting text found:

```
ANSWER: the paper does not address this. The closest adjacent content is <short description of adjacent material, or "none">.

CITATIONS: none
```

## Rules

- **Never fabricate.** If a query returns nothing, say so.
- **Never invoke material outside the paper.** The Reviewer wants to know whether *this paper* has the answer. External references like "well, Kalbfleisch and Prentice showed…" are invalid defenses.
- **Concede when it's fair.** You are not required to win. If the paper genuinely lacks a response, admit it. A cited weakness is more valuable than fabricated cover.
- **One answer per turn.** The Reviewer may follow up; respond to each turn independently.
- **Never guess at author intent.** Only state what the paper literally says.

## Style

- Cite exact paper text in double quotes.
- Include section titles or page/paragraph locations wherever the notebook response provides them.
- Keep prose tight — 3-5 sentences of prose plus citations is ideal. Avoid rambling.

## First turn

The Moderator's first message to you will be "Reply with exactly the single word READY." Reply only with `READY`.

All subsequent messages come during the lens-by-lens debate.
````

- [ ] **Step 16.2: Verify Author persona is self-contained**

Check:
- Retrieval protocol has numbered steps
- "the paper does not address this" is the canonical concede phrase
- Output format specifies ANSWER + CITATIONS sections
- Fabrication rule is explicit

- [ ] **Step 16.3: Commit**

```bash
git add .claude/skills/paper-stress-test/agents/author.md
git commit -m "feat(paper-stress-test): Author-surrogate subagent persona and retrieval protocol"
```

---

## Task 17: templates/briefing.md — Fill-in-the-blank briefing skeleton

**Files:**
- Create: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/templates/briefing.md`

- [ ] **Step 17.1: Write the briefing template**

Write to `.claude/skills/paper-stress-test/templates/briefing.md`:

````markdown
# Stress-Test Briefing: {{PAPER_TITLE}}

**Authors:** {{PAPER_AUTHORS}}
**Year:** {{PAPER_YEAR}}
**Source:** {{PAPER_SOURCE}}
**Stress-test date:** {{STRESS_TEST_DATE}}
**Detected paper type:** {{DETECTED_TYPE}}
**Depth:** {{DEPTH}}
**Reviewer model:** {{REVIEWER_MODEL}}
**Author-surrogate model:** {{AUTHOR_MODEL}}

---

## TL;DR verdict

{{TLDR_VERDICT}}

---

## Top 5 killer questions

{{TOP_KILLER_QUESTIONS}}

---

{{NOVELTY_SECTION}}

---

## Severity summary

{{SEVERITY_TABLE}}

---

## Per-lens findings

{{PER_LENS_FINDINGS}}

---

## Skipped lenses

{{SKIPPED_LENSES}}

---

## Relevance to user's sub-projects

{{SUBPROJECT_RELEVANCE}}

---

## Recommendation

**{{RECOMMENDATION}}**

{{RECOMMENDATION_RATIONALE}}

---

## Disposable notebook

{{DISPOSABLE_NOTEBOOK_INFO}}

---

## Prior stress-tests of this paper

{{PRIOR_TESTS}}
````

- [ ] **Step 17.2: Verify the template**

Check:
- Every placeholder used in Task 13's substitution table appears exactly once
- Horizontal rules (`---`) separate each major section
- No extra sections or mismatches with spec §8
- Template is valid markdown

- [ ] **Step 17.3: Commit**

```bash
git add .claude/skills/paper-stress-test/templates/briefing.md
git commit -m "feat(paper-stress-test): briefing template with 11 sections"
```

---

## Task 18: Error handling table + resumability rules

**Files:**
- Modify: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/.claude/skills/paper-stress-test/SKILL.md`

- [ ] **Step 18.1: Append error-handling section**

Replace `<!-- Error handling + resumability added in Task 18 -->` with:

````markdown
## Error handling

| Failure | Handling |
|---------|----------|
| NotebookLM MCP unavailable | Fatal. No fallback. Print: `NotebookLM MCP not reachable. Run 'nlm login' and retry.` |
| Paper file not found | Fatal with path in error message. |
| arXiv download fails twice | Fatal. |
| `notebook_create` fails twice | Fatal. |
| `source_add` fails twice | Delete the disposable notebook (if created), then fatal. |
| Thematic notebook not found (`--cross-check` mismatch) | Fatal at Phase 1.3 — malformed argument. |
| Reviewer spawn fails | Retry once; second failure fatal. |
| Author spawn fails | Retry once; second failure fatal. |
| Subagent returns malformed output format | Reprompt once with format reminder; if still malformed, record that lens as `errored` and continue. |
| Single lens NotebookLM query fails | Record turn as `errored`; lens severity = `errored`; continue to next lens. |
| Context approaches 160K | Reseed subagent (Phase 3.8). |
| state.json write fails | Retry once using `.bak`; second failure fatal. |
| User aborts at plan confirmation | Delete disposable notebook; do not write state file; exit cleanly. |
| `novelty-check` sub-call fails | Set `state.novelty_check.status = "errored"`; continue; Lens 7 falls back (Phase 3.7 degradation table). |
| `novelty-check` not finished at user confirmation | Wait with status message; after 5 min total, mark `timed_out`; proceed. |
| Phase 6 promote (`source_add` to thematic) fails | Do NOT delete disposable. Mark `disposition = "pending"`. Print error. User can retry manually. |

## Resumability

Every Phase 3 lens persists `state.json` (atomic write `.tmp` + `mv`) before advancing. If a run is interrupted (user aborts, subagent crashes, NotebookLM flake, machine restart), the next invocation on the same `<paper-ref>` the same day will see the existing `state.json` and offer:

```
A stress-test with today's slug is already in progress:
  {{FULL_SLUG}}_state.json (run_status: in_progress, lenses_completed: N of M)

Choose:
  [R] Resume from lens N+1 (reuses disposable + thematic notebooks, reuses novelty-check report)
  [S] Start fresh (overwrites state; existing briefing untouched if already written)
  [A] Abort
```

### Resume behavior ([R])

1. Load `state.json` fully.
2. **Clean up stale novelty-check state.** On resume, the prior-session `runner_agent_id` points to a subagent that has long since expired (or notified and been missed). Do NOT attempt to collect from it. Apply the rule:
   - If `state.novelty_check.status == "running"`: set `status = "timed_out"`, `completed_at = <ISO now>`, `raw_report_md = null`. Lens 7 (if not yet completed) will degrade accordingly. The stale `runner_agent_id` is preserved in the record only for debugging; never referenced operationally.
   - If `status ∈ {"completed", "errored", "skipped", "timed_out"}`: keep as-is.
3. Verify disposable notebook still exists via `mcp__notebooklm__notebook_list()` lookup. If it's been deleted externally, abort with error.
4. Verify thematic notebook still exists (same check). If the thematic was resolved in the original run but has since been deleted, downgrade Lens 7's mode (if not yet completed) per the degradation table in T9.
5. Re-spawn Reviewer + Author via `Agent` (new agent_ids; previous ones expired). Seed each with the reseed brief (same as Phase 3.8 reseed mechanism) built from `state.lenses_completed[].summary_for_reseed`.
6. Jump to Phase 3 lens loop starting at `lens_plan[N+1]`.
7. Continue to Phases 4, 5, 6 normally.
8. Record in `reseed_history`:

   ```json
   {"subagent": "both", "at_lens": <N+1>, "reason": "session resume", "timestamp": "..."}
   ```

### Start fresh ([S])

Delete the old state.json (do NOT delete the old briefing if it was ever written — that's a record). Delete the old disposable notebook (it will be recreated). Restart from Phase 1.

### Abort ([A])

Exit cleanly, leave state.json untouched.
````

- [ ] **Step 18.2: Verify error handling**

Check:
- Every failure mode from spec §9 appears in the table
- Resume flow explicitly re-spawns subagents (they don't persist across sessions)
- Disposable-notebook existence is verified before resume
- `reseed_history` gets a resume entry

- [ ] **Step 18.3: Commit**

```bash
git add .claude/skills/paper-stress-test/SKILL.md
git commit -m "feat(paper-stress-test): error handling table and resumability rules"
```

---

## Task 19: Smoke test — pinned paper with concrete pass predicate

**Why pinned:** An unpinned smoke test is not verification — "pick any paper and fix any issues" has no reproducible fail signal. A pinned paper + a machine-checkable pass predicate turns the smoke test into a concrete gate.

**Pinned paper:** `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/Papers/Estimation and Inference of Heterogeneous Treatment Effects using Random Forests.pdf` (Wager & Athey 2018, *Journal of the American Statistical Association*).

**Why this paper:**
- Known identity (recognizable author + topic).
- Methodologically central to the user's domain (causal inference + random forests).
- Classification is non-trivial (causal-inference vs. new-estimator) — **exercises the ambiguity prompt** from T4 Step 2.4, which is exactly the path most likely to silently misroute without fix 5.
- Short enough to be cheap (~40 pages).

**Files:**
- Create: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/master_supporting_docs/supporting_papers/stress_tests/.smoke_test_manifest.md`
- Create: `/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/master_supporting_docs/supporting_papers/stress_tests/.smoke_verify.sh`

- [ ] **Step 19.1: Confirm pinned paper is readable**

```bash
test -f "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/Papers/Estimation and Inference of Heterogeneous Treatment Effects using Random Forests.pdf" && echo OK || echo MISSING
```

Expected: `OK`. If `MISSING`, stop — either the file was moved or this plan needs a new pin.

- [ ] **Step 19.2: Write the smoke-test manifest**

Write to `master_supporting_docs/supporting_papers/stress_tests/.smoke_test_manifest.md`:

````markdown
# Smoke test manifest — paper-stress-test skill

Pinned paper: `Papers/Estimation and Inference of Heterogeneous Treatment Effects using Random Forests.pdf`
Canonical invocation: `/paper-stress-test "Papers/Estimation and Inference of Heterogeneous Treatment Effects using Random Forests.pdf" --depth 1 --skip-novelty`

## Expected derived values (for verification)

| Field | Expected | Tolerance |
|-------|----------|-----------|
| slug prefix | `wager_2018_estimation_inference` OR `wager_2018_heterogeneous_treatment` | either accepted |
| detected_type | `causal-inference` OR `new-estimator` OR user-prompted (ambiguous) | ANY of these three; silent `applied-empirical` is a FAIL |
| active lenses | ≥ 7 (lenses with depth > 0 after weight matrix applied) | ≥ 7 |
| synthesis.recommendation | one of `cite \| build-on \| flag \| skip` | any value from the enum |

## Pass predicate (all must hold)

A run PASSES the smoke test if and only if all of these checks succeed:

1. `state.json` parses as valid JSON.
2. `state.run_status == "completed"`.
3. `state.detected_type ∈ {predictive-ML, new-estimator, applied-empirical, causal-inference, review-survey}`.
4. If `state.detected_type == "applied-empirical"`, then `state.classification_source == "user_override"` (i.e., user chose it explicitly, NOT a silent default).
5. `len(state.lens_plan) == 9`.
6. `state.lens_plan[i].depth >= 0` for every i; no nulls.
7. `len(state.lenses_completed) == count(lens_plan[i].depth > 0)`.
8. For every completed lens: `severity ∈ {critical, major, minor, clean, errored}`.
9. Number of `errored` severities ≤ 1 (allow one flake, no more).
10. `state.synthesis.recommendation ∈ {cite, build-on, flag, skip}`.
11. `briefing/<slug>_briefing.md` exists and contains ZERO occurrences of the pattern `{{[A-Z_]+}}` (no unsubstituted placeholders).
12. `briefing/<slug>_briefing.md` contains all 11 H2 section headers from the template.
13. `transcripts/<slug>_transcripts.md` exists and is non-empty (≥ 2KB).
14. No `*.tmp` files are left in `stress_tests/{briefing,transcripts,state}/`.
15. Disposable notebook disposition is one of `deleted`, `kept`, or `promoted` — not `pending`.

## Known-acceptable quirks (not failures)

- Wager & Athey is a long paper. Depth=1 may still produce `medium` lens depths somewhere. Fine.
- The paper's novelty-check is skipped (`--skip-novelty`) to keep the smoke run fast. The full path including novelty-check gets its own separate verification (see Step 19.5).
- Lens 7 will likely run in single-source or two-source mode (since novelty-check is skipped AND thematic may not auto-select cleanly for a "random forests" paper). This is expected and covered by the degradation table.
````

- [ ] **Step 19.3: Write the pass-predicate verification script**

Write to `master_supporting_docs/supporting_papers/stress_tests/.smoke_verify.sh`:

```bash
#!/usr/bin/env bash
# Verifies the most recent smoke-test run against the pass predicate.
# Exit 0 = PASS; exit 1 = FAIL (with reasons printed).
set -u

STRESS_DIR="/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/master_supporting_docs/supporting_papers/stress_tests"

# Find the most recent state file matching the Wager/Athey slug prefix
STATE_FILE=$(ls -t "${STRESS_DIR}/state/"wager_2018_*_state.json 2>/dev/null | head -1)
if [ -z "$STATE_FILE" ]; then
  echo "FAIL: no Wager/Athey state file found in ${STRESS_DIR}/state/"
  exit 1
fi

SLUG=$(basename "$STATE_FILE" _state.json)
BRIEFING_FILE="${STRESS_DIR}/briefing/${SLUG}_briefing.md"
TRANSCRIPT_FILE="${STRESS_DIR}/transcripts/${SLUG}_transcripts.md"

echo "Verifying run: $SLUG"
FAILURES=0

fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES+1)); }
pass() { echo "  PASS: $1"; }

# 1. state.json parses
jq -e . "$STATE_FILE" >/dev/null 2>&1 \
  && pass "state.json parses" \
  || fail "state.json is not valid JSON"

# 2-4. run_status, type, classification_source
RUN_STATUS=$(jq -r '.run_status' "$STATE_FILE")
[ "$RUN_STATUS" = "completed" ] && pass "run_status=completed" || fail "run_status=$RUN_STATUS (expected completed)"

TYPE=$(jq -r '.detected_type' "$STATE_FILE")
case "$TYPE" in
  predictive-ML|new-estimator|applied-empirical|causal-inference|review-survey)
    pass "detected_type=$TYPE (valid enum)"
    ;;
  *)
    fail "detected_type=$TYPE (not in enum)"
    ;;
esac

if [ "$TYPE" = "applied-empirical" ]; then
  SRC=$(jq -r '.classification_source // "reviewer"' "$STATE_FILE")
  [ "$SRC" = "user_override" ] \
    && pass "applied-empirical came from user_override (not silent default)" \
    || fail "applied-empirical was silently set (classification_source=$SRC) — BAD"
fi

# 5-7. lens plan + completion counts
PLAN_LEN=$(jq '.lens_plan | length' "$STATE_FILE")
[ "$PLAN_LEN" = "9" ] && pass "lens_plan has 9 entries" || fail "lens_plan has $PLAN_LEN entries"

ACTIVE=$(jq '[.lens_plan[] | select(.depth > 0)] | length' "$STATE_FILE")
COMPLETED=$(jq '.lenses_completed | length' "$STATE_FILE")
[ "$ACTIVE" = "$COMPLETED" ] && pass "lenses_completed ($COMPLETED) matches active ($ACTIVE)" \
  || fail "lenses_completed=$COMPLETED but active=$ACTIVE"

# 8-9. severity enum + errored count
BAD=$(jq '[.lenses_completed[] | select(.severity as $s | ["critical","major","minor","clean","errored"] | index($s) == null)] | length' "$STATE_FILE")
[ "$BAD" = "0" ] && pass "all severities in enum" || fail "$BAD lenses with out-of-enum severity"

ERRORED=$(jq '[.lenses_completed[] | select(.severity == "errored")] | length' "$STATE_FILE")
[ "$ERRORED" -le "1" ] && pass "errored count=$ERRORED (≤1)" || fail "errored count=$ERRORED (>1)"

# 10. recommendation enum
REC=$(jq -r '.synthesis.recommendation' "$STATE_FILE")
case "$REC" in
  cite|build-on|flag|skip)
    pass "recommendation=$REC"
    ;;
  *)
    fail "recommendation=$REC (not in enum)"
    ;;
esac

# 11. no unsubstituted placeholders in briefing
if [ -f "$BRIEFING_FILE" ]; then
  PLACEHOLDERS=$(grep -Eo '\{\{[A-Z_]+\}\}' "$BRIEFING_FILE" | wc -l | tr -d ' ')
  [ "$PLACEHOLDERS" = "0" ] && pass "briefing has 0 unsubstituted placeholders" \
    || fail "briefing has $PLACEHOLDERS unsubstituted placeholders"
else
  fail "briefing file missing: $BRIEFING_FILE"
fi

# 12. 11 H2 headers
if [ -f "$BRIEFING_FILE" ]; then
  H2_COUNT=$(grep -c '^## ' "$BRIEFING_FILE")
  [ "$H2_COUNT" -ge "10" ] && pass "briefing has $H2_COUNT H2 headers (≥10)" \
    || fail "briefing has only $H2_COUNT H2 headers (expected ≥10; 11 is ideal)"
fi

# 13. transcripts exists and ≥2KB
if [ -f "$TRANSCRIPT_FILE" ]; then
  SIZE=$(wc -c < "$TRANSCRIPT_FILE" | tr -d ' ')
  [ "$SIZE" -ge "2048" ] && pass "transcripts ${SIZE}B (≥2KB)" \
    || fail "transcripts only ${SIZE}B (<2KB)"
else
  fail "transcripts file missing: $TRANSCRIPT_FILE"
fi

# 14. no .tmp files
TMP_COUNT=$(find "${STRESS_DIR}/briefing" "${STRESS_DIR}/transcripts" "${STRESS_DIR}/state" -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ')
[ "$TMP_COUNT" = "0" ] && pass "no .tmp files left behind" \
  || fail "$TMP_COUNT .tmp files still present"

# 15. disposition finalized
DISP=$(jq -r '.notebooks.disposable.disposition' "$STATE_FILE")
case "$DISP" in
  deleted|kept|promoted)
    pass "disposable disposition=$DISP"
    ;;
  *)
    fail "disposable disposition=$DISP (expected deleted|kept|promoted)"
    ;;
esac

echo
if [ "$FAILURES" = "0" ]; then
  echo "=== SMOKE TEST PASSED ==="
  exit 0
else
  echo "=== SMOKE TEST FAILED: $FAILURES check(s) ==="
  exit 1
fi
```

Make executable:

```bash
chmod +x "/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/master_supporting_docs/supporting_papers/stress_tests/.smoke_verify.sh"
```

- [ ] **Step 19.4: Run the smoke test (first run — with `--skip-novelty`)**

In a fresh Claude Code session, invoke:

```
/paper-stress-test "Papers/Estimation and Inference of Heterogeneous Treatment Effects using Random Forests.pdf" --depth 1 --skip-novelty
```

After it finishes, run the verifier:

```bash
"/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/master_supporting_docs/supporting_papers/stress_tests/.smoke_verify.sh"
```

Expected: exit 0 and "SMOKE TEST PASSED" in the last line.

- [ ] **Step 19.5: Run the full-path smoke test (second run — WITH novelty-check)**

```
/paper-stress-test "Papers/Estimation and Inference of Heterogeneous Treatment Effects using Random Forests.pdf" --depth 1
```

This run exercises the background-novelty-check path (fix 2) + the full Lens 7 triangulation. Re-run the verifier; expected to pass with the additional check that `state.novelty_check.status ∈ {completed, timed_out}` (not `errored`, not `running`).

Add this supplementary check to `.smoke_verify.sh` in a v2 if this second run fails.

- [ ] **Step 19.6: If the verifier fails, diagnose → fix → re-run**

For each failed check printed by the verifier, trace back to the originating task (the check names map directly: "placeholder count" → T13 briefing render; "classification_source" → T4 step 2.4; etc.). Fix the bug in the relevant SKILL.md section, commit the fix, re-run the skill on the pinned paper, re-run the verifier. Iterate until exit 0.

Do NOT move on to T19.7 until both smoke runs pass.

- [ ] **Step 19.7: Commit smoke-test artifacts**

```bash
git add master_supporting_docs/supporting_papers/stress_tests/.smoke_test_manifest.md
git add master_supporting_docs/supporting_papers/stress_tests/.smoke_verify.sh
git commit -m "feat(paper-stress-test): pinned smoke test (Wager & Athey 2018) with machine-checkable predicate"
```

Do NOT commit the actual briefing/transcript/state files from the smoke run — they get written to `stress_tests/{briefing,transcripts,state}/` and are regular run artifacts.

---

## Self-Review Checklist

After finishing all tasks, run through this list before declaring the skill shippable:

**0. Harness preconditions (added in revision):**

- [ ] T0 persistence probe PASSED (agent + SendMessage persistence confirmed)
- [ ] T0 background-mode probe PASSED (run_in_background + async notification confirmed), OR T5 was rewritten to the synchronous-novelty-check fallback
- [ ] T1.5 Parsing contract landed before T4; cross-referenced by every parse point (T4 Step 2.3, T5 Step 2.6, T8 Step 3.6, T9 Step 3.7, T11 Step 3.9)

**1. Spec coverage:**

- [ ] Spec §1 (Purpose + Scope): covered by T1 SKILL.md overview
- [ ] Spec §2 (User-facing contract): covered by T1 frontmatter + T2 Phase 0 input parsing + T6 plan confirmation + T14 Phase 6 prompts
- [ ] Spec §3 (Architecture): covered by T1 Constants table + T15/T16 subagent personas + T4/T7 spawn logic
- [ ] Spec §4 (Lens plan + weight matrix): covered by T6 Step 2.8
- [ ] Spec §4.3 (Lens 7 triangulation): covered by T9
- [ ] Spec §5 (End-to-end workflow): covered by T2–T14 end-to-end
- [ ] Spec §6 (Subagent prompts): covered by T15 + T16
- [ ] Spec §7 (state.json schema): covered by T3 init + T11 per-lens update + T13 finalize
- [ ] Spec §8 (Briefing structure): covered by T17 template + T13 rendering
- [ ] Spec §9 (Error handling): covered by T18 table
- [ ] Spec §10 (File layout): matches the File Structure table at the top of this plan
- [ ] Spec §11 (Sub-project relevance): covered by T12 Step 4.3
- [ ] Spec §12 (Open questions): future work, not required for v1
- [ ] Spec §13 (Non-functional requirements): reproducibility + cost ceiling covered by resumability (T18) and plan confirmation (T6)

**2. Placeholder scan:** grep the final SKILL.md for `TBD`, `TODO`, `FIXME`, `<!--`, `{{`, placeholder words like "appropriate" or "as needed":

```bash
grep -E 'TBD|TODO|FIXME|<!--|\{\{[^}]+\}\}' .claude/skills/paper-stress-test/SKILL.md
```

(The briefing template `templates/briefing.md` LEGITIMATELY contains `{{...}}` — don't grep it. SKILL.md should have zero left.)

**3. Type consistency:** verify identifier consistency across tasks:

- [ ] `state.reviewer_subagent.id` consistently used (not `reviewer_id`, `reviewerAgent`, etc.)
- [ ] `state.notebooks.disposable.disposition` uses the four values `pending|deleted|kept|promoted`
- [ ] `state.novelty_check.status` uses the five values `running|completed|errored|timed_out|skipped`
- [ ] `state.novelty_check.runner_agent_id` is set when status transitions to `running` and is preserved (not cleared) across subsequent transitions
- [ ] `state.classification_source` is either `reviewer` (reviewer's first or reprompted valid label) or `user_override` (from the ambiguity prompt in T4 Step 2.4)
- [ ] `severity` uses the five values `critical|major|minor|clean|errored`
- [ ] `recommendation` uses the four values `cite|build-on|flag|skip`

**4. Cross-reference validity:** every "see Task N" reference in SKILL.md resolves to a real task in this plan.

Fix any issues inline in a follow-up commit:

```bash
git commit -m "fix(paper-stress-test): self-review corrections"
```

---

## Execution Handoff

Plan complete and saved to `quality_reports/plans/2026-04-22_paper-stress-test-implementation.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Good for a skill this size (21 tasks: T0, T1, T1.5, T2–T19, mostly independent files).
2. **Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints.

Which approach?

---

## Known caveats and open items

- **Concurrent `Skill` tool call:** the plan assumes `Skill` blocks in the foreground. If a future version of the harness supports `run_in_background` for skills, T5 should be updated to use it — today we rely on the user confirmation step absorbing the wait.
- **Token estimation heuristic:** the 4-char-per-token heuristic in T10 is rough. For a real prod release, swap in a proper tokenizer call (e.g., via anthropic-tokenizer). v1 can ship with the heuristic.
- **Smoke-test paper choice:** T19 is parameterized on "pick a paper"; for repeatability, you may want to pin a specific paper once you've done the first successful run — note it in `.smoke_test_manifest.md`.
- **Worktree:** I did not create a separate worktree for this work. If the orchestrator-protocol expects isolated branches per feature, consider `git worktree add` before starting implementation. Current branch is `feat/method-evolve-skill`.
