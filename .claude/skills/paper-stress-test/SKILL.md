---
name: paper-stress-test
description: Upload a paper to NotebookLM, run an automated adversarial debate between an Opus Reviewer subagent and a Sonnet Author-surrogate subagent (with concurrent novelty-check sub-call), and produce a structured briefing with cite/build-on/flag/skip recommendation. Use when the user says "stress test this paper", "adversarial read of this paper", "brief me on this paper", "help me read this paper", "is this paper's claim real", or wants deep single-paper interrogation rather than surface-level summary. Not for reviewing the user's own manuscripts (use review-paper) or multi-paper synthesis (use lit-review).
argument-hint: "<paper-path-or-arxiv-id> [--depth N] [--type T] [--cross-check NB] [--skip-novelty] [--resume <slug>]"
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Agent, mcp__notebooklm__notebook_create, mcp__notebooklm__notebook_delete, mcp__notebooklm__notebook_list, mcp__notebooklm__source_add, mcp__notebooklm__notebook_query
---

# Paper Stress-Test

Adversarial single-paper interrogation: **$ARGUMENTS**

## Overview

This skill uploads a paper to a disposable NotebookLM notebook, then runs a structured adversarial debate across nine lenses weighted by detected paper type. Each round of each lens spawns a fresh Opus Reviewer (hostile Biostatistics referee) and a fresh Sonnet Author-surrogate (defends the paper using only paper-internal evidence retrieved via NotebookLM); the Moderator holds the running transcript and writes a read-reasoning-and-decision entry after every (Reviewer, Author) exchange, which steers the next round. A concurrent sub-call to the `novelty-check` skill provides external novelty verification. The output is a structured briefing with per-lens severity, top-5 killer questions, sub-project relevance, and a cite/build-on/flag/skip recommendation.

Spec reference: `quality_reports/specs/2026-04-22_paper-stress-test-design.md`.

## Workflow

Seven phases (0–6):

| Phase | Purpose |
|-------|---------|
| 0 | Input resolution + prior-test detection + output dir setup |
| 1 | NotebookLM setup (disposable notebook + paper upload + thematic resolution) |
| 2 | Paper-type detection (one-shot Reviewer classification spawn), novelty-check sub-call, plan confirmation |
| 3 | Per-lens adversarial debate — fresh Reviewer + Author spawns per round, with Moderator read-reasoning-decision entries between rounds (Lens 7 triangulates three sources) |
| 4 | Synthesis (top-5 questions, sub-project relevance, recommendation) |
| 5 | Write briefing + transcripts + state files |
| 6 | Cleanup with optional promote-to-thematic |

## Constants

- DISPOSABLE_NOTEBOOK_NAME_PREFIX = `stress-test-`
- COMPACTION_THRESHOLD_CHARS = 80000
- NOVELTY_CHECK_TIMEOUT_SECONDS = 300
- REVIEWER_MODEL = `claude-opus-4-7`
- AUTHOR_MODEL = `claude-sonnet-4-6`
- OUTPUT_DIR = `master_supporting_docs/supporting_papers/stress_tests`

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

All regexes below are PCRE-compatible extended regexes (Python `re`-compatible), multiline mode. Apply DOTALL (`(?s)` or `re.DOTALL`) when matching Patterns 1–5, which capture multi-line text with `.+?` lookaheads; do NOT apply DOTALL to the single-line field anchors in Pattern 2 (`JUDGMENT`, `NEXT`, `SEVERITY`), as those use `$` end-of-line anchors. Whitespace around field values must be trimmed on capture.

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
^QUESTION:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
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
closest_prior_work: Closest Prior Work[[:space:]]*\n((?:\|.+\|\n)+)
```

For `closest_prior_work`, split each table row on `|` (strip pipes and whitespace), skip the header row and separator row, build a `{paper, year, venue, overlap, key_difference}` object per remaining row.

If any field fails to parse, leave it `null`. Do NOT fail the whole run — the raw report is kept in `raw_report_md` regardless.

### Cross-reference (updated 2026-04-22 evening for the transcript-relay Phase 3 step numbering)

| Pattern | Used in tasks |
|---------|---------------|
| 1. Primary question (Format A) | T8 Step 3.5 (round 1 of any non-Lens-7 lens) |
| 2. Judgment + decision (Format B) | T8 Step 3.5 (rounds 2..depth and any `close_lens_mode` turn), T9 Step 3.6 (terminal Reviewer, round 3), T11 Step 3.8 (severity extraction) |
| 3. Lens 7 initial (Format C — QUESTION + THEMATIC_QUERY) | T9 Step 3.6 (round 1) |
| 4. Lens 7 confrontation (Format C — CONFRONTATION or JUDGMENT+SEVERITY) | T9 Step 3.6 (round 2) |
| 5. Author answer (ANSWER + CITATIONS) | T8 Step 3.5 (every Author turn), T9 Step 3.6 (rounds 1 and 2 Author turns) |
| 6. Classification triple | T4 Step 2.3 |
| 7. novelty-check | T5 Step 2.6 |

## Defer-tool preamble

Before Phase 0, the Moderator must load two deferred tools via ToolSearch:

```
ToolSearch(query="select:Agent,TodoWrite", max_results=2)
```

These are required: `Agent` spawns fresh Reviewer and Author subagents synchronously at every round of every lens (no `SendMessage` continuity is used — see §Architecture Amendment); `TodoWrite` tracks lens progress.

## Known thematic notebooks (auto-suggest table)

| Notebook name | ID | Keywords that trigger auto-suggest |
|---|---|---|
| ML for Recurrent Events | `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` | survival, recurrent event, competing risk, hazard, censoring, pseudo-observation, landmark, time-to-event, frailty, counting process |
| Interpretable AI | `fea2207b-7ec1-463c-b73f-58c0c4febb41` | interpretability, explainability, feature importance, SHAP, LIME, partial dependence, counterfactual explanation |
| Machine Learning Fundamentals | `c3aab8e1-5c4b-43ec-bafc-ae3745a7c493` | neural network, deep learning, supervised learning, regularization, cross-validation, boosting, bagging |
| Survival Analysis Fundamentals | `3faa5656-280d-4ffc-ae2d-5487075bc94e` | Cox proportional hazards, Kaplan-Meier, log-rank, Nelson-Aalen, accelerated failure time, Weibull, exponential |

## Instructions

Follow the phase-by-phase instructions below. Phases 2 through 6 depend on state persisted after each lens, so Phase 3 must be resumable from `state.json`.

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
  "transcript": [],
  "moderator_assessments": [],
  "compaction_history": [],
  "spawn_count": 0,
  "spawn_budget": 80,
  "wall_clock_start": "<ISO 8601 — set exactly once when Phase 0 begins>",
  "wall_clock_budget_s": 1800,
  "abort_reason": null,
  "moderator_own_context_est_chars": 0,
  "run_status": "in_progress",
  "started_at": "<ISO 8601>",
  "completed_at": null
}
```

**Schema note (amended 2026-04-22):** The fields `reviewer_subagent`, `author_subagent`, and `reseed_history` that appeared in pre-amendment drafts are **removed**. Under the transcript-relay architecture there are no persistent subagent handles; `transcript` is the full turn-by-turn record (array of reviewer/author/moderator records per §Architecture Amendment), `moderator_assessments` is a flat index of the per-round Moderator entries for Phase 4 synthesis, and `compaction_history` replaces the old reseed-history field.

**Run-budget fields** (`spawn_count`, `spawn_budget`, `wall_clock_start`, `wall_clock_budget_s`, `abort_reason`, `moderator_own_context_est_chars`) are declared and documented in T11 Step 3.8.5; `wall_clock_start` is captured once here in Phase 0 and is not reset on resume. Full enforcement semantics live in T7 Step 3.4 (budget gate at lens-loop top) and T10 (Moderator own-context soft budget).

### End of Phase 1

By the end of Phase 1, the Moderator has a populated state file with notebook IDs and paper metadata. Nothing has been queried yet.
## Phase 2 — Reviewer spawn, classification, novelty-check, plan confirmation

Phase 2 has three sub-phases that run concurrently where possible:
- **2a:** Spawn Reviewer; Reviewer classifies the paper + extracts headline + lists novelty claims.
- **2b:** Moderator fires `novelty-check` sub-call (running in the background via `Skill` tool).
- **2c:** Moderator builds the lens plan from the weight matrix and prompts user to confirm.

### Step 2.1: Load reviewer prompt template

Read `.claude/skills/paper-stress-test/agents/reviewer.md` with the `Read` tool. Store its contents as `REVIEWER_PROMPT`.

### Step 2.2: One-shot Reviewer classification spawn

**Amended 2026-04-22:** Phase 2a's Reviewer spawn is now a single synchronous `Agent` call whose tool result IS the classification. No `agent_id` is persisted; no follow-up is sent. The persona is re-spawned fresh per round during Phase 3 (see Tasks 8 and 9).

Call `Agent` with:

```
classification_text = Agent(
  description:       "paper-stress-test classification",
  subagent_type:     "general-purpose",
  model:             "opus",
  run_in_background: False,
  prompt: REVIEWER_PROMPT
    .replace("{{PAPER_TITLE}}", state.paper.title)
    .replace("{{PAPER_AUTHORS}}", state.paper.authors.join(", "))
    .replace("{{PAPER_YEAR}}", state.paper.year)
    .replace("{{DISPOSABLE_NOTEBOOK_ID}}", state.notebooks.disposable.id)
    .replace("{{THEMATIC_NOTEBOOK_ID}}", state.notebooks.thematic.id ?? "null")
    .replace("{{LENS_ID}}", "n/a — classification only")
    .replace("{{LENS_NAME}}", "classification")
    .replace("{{LENS_DESCRIPTION}}", "one-shot paper-type classification before the lens loop")
    .replace("{{LENS_DEPTH}}", "0")
    .replace("{{ROUND}}", "0")
    .replace("{{REQUIRED_OUTPUT}}", "classification + headline + novelty claims (see prompt below)")
    .replace("{{MODERATOR_STEER_BLOCK}}", "")
    .replace("{{TRANSCRIPT_BLOCK}}", "(no transcript yet — this is the pre-debate classification pass)")
    + "\n\n## This spawn: paper classification (one-shot, synchronous)\n\nQuery the disposable notebook (ID: " + state.notebooks.disposable.id + ") three times via mcp__notebooklm__notebook_query:\n\n1. 'Classify this paper as exactly one of: predictive-ML, new-estimator, applied-empirical, causal-inference, review-survey. Return the label plus one sentence of justification, nothing else.'\n2. 'State the paper's headline contribution in one sentence, quoting the exact wording from abstract or conclusion.'\n3. 'List the 3 to 5 most important technical claims the paper positions as novel. Format as a numbered list; be specific, avoid generic phrasing like 'novel approach'.'\n\nReturn all three answers concatenated, one per paragraph, with clear headings. Do NOT query anything else. You will NOT be called again in this spawn — treat this as a single-turn task."
)
```

The returned `classification_text` string is the entire output for this spawn. Proceed to Step 2.3 to parse it. No subagent handle is retained.

If `type_override` was specified: skip query 1 and use the override; the prompt instructs the subagent to run only queries 2 and 3.

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
- If `edit`: enter edit loop (see Step 2.11).

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
- `novelty_check` block (possibly still `running`; moderator re-checks at Phase 3 start, no blocking)
- `lens_plan` (confirmed by user)
- Empty `transcript`, `moderator_assessments`, `compaction_history` — all populated during Phase 3.

No subagent handles are persisted; the Phase 2a classification call was one-shot, and Phase 3 spawns fresh Reviewer and Author subagents per round (see §Architecture Amendment).
<!-- Phase 3 instructions added in Tasks 7, 8, 9, 10, 11 -->
<!-- Phase 4 instructions added in Task 12 -->
<!-- Phase 5 instructions added in Task 13 -->
<!-- Phase 6 instructions added in Task 14 -->
<!-- Error handling + resumability added in Task 18 -->
