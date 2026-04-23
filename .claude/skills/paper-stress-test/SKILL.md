---
name: paper-stress-test
description: Upload a paper to NotebookLM, run an automated adversarial debate between an Opus Reviewer subagent and a Sonnet Author-surrogate subagent (with concurrent novelty-check sub-call), and produce a structured briefing with cite/build-on/flag/skip recommendation. Use when the user says "stress test this paper", "adversarial read of this paper", "brief me on this paper", "help me read this paper", "is this paper's claim real", or wants deep single-paper interrogation rather than surface-level summary. Not for reviewing the user's own manuscripts (use review-paper) or multi-paper synthesis (use lit-review).
argument-hint: "<paper-path-or-arxiv-id> [--depth N] [--type T] [--cross-check NB] [--skip-novelty] [--no-checkpoint] [--resume <slug>]"
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Agent, mcp__notebooklm__notebook_create, mcp__notebooklm__notebook_delete, mcp__notebooklm__notebook_list, mcp__notebooklm__source_add, mcp__notebooklm__notebook_query
---

# Paper Stress-Test

Adversarial single-paper interrogation: **$ARGUMENTS**

## Arguments

**Positional (required):**

- `<paper-path-or-arxiv-id>` — The paper to stress-test. Accepts:
  - Absolute path to a `.pdf`
  - Relative path to a `.pdf` (resolved against CWD)
  - Bare filename in `master_supporting_docs/supporting_papers/`
  - arXiv ID matching `^[0-9]{4}\.[0-9]{4,5}(v[0-9]+)?$` (auto-downloaded to `/tmp/arxiv-<id>.pdf`)
  - Full `http(s)://` URL to a PDF (auto-downloaded to `/tmp/paper-<timestamp>.pdf`)
  - Resolution rules: Phase 0, "Input resolution" table.

**Optional flags:**

| Flag | Type | Default | Effect |
|------|------|---------|--------|
| `--depth N` | integer | 2 | Aggressiveness of the adversarial debate. Maps to per-lens rounds via the weight table: `heavy → N`, `medium → max(1, N-1)`, `light → 1`, `skip → 0`. Higher `N` = more Reviewer↔Author exchanges per lens (and ~linear growth in total `Agent` spawns). |
| `--type T` | enum | auto-detected | Override the Reviewer's paper-type classification. One of: `predictive-ML`, `new-estimator`, `applied-empirical`, `causal-inference`, `review-survey`. Paper type drives per-lens weights (see Step 2.9 table), so this re-shapes the lens plan. |
| `--cross-check NB` | string | auto-suggest | Pin the thematic cross-check notebook used by Lens 7 (positioning/triangulation). Matches against notebook name or ID from the "Known thematic notebooks" table. If omitted, keywords from the paper's abstract are matched against the same table; ambiguous matches prompt the user. |
| `--skip-novelty` | boolean | false | Do not spawn the concurrent `novelty-check` sub-call in Phase 2 (see Step 2.5). Saves tokens when the prior-art landscape is already known; the briefing's novelty section will show `status: skipped`. |
| `--no-checkpoint` | boolean | false | Skip the Phase 2 human-in-the-loop plan-confirmation prompt; auto-proceed as if the user answered `Y` (Step 2.10). Useful for unattended runs. |
| `--resume <slug>` | string | — | Resume an aborted or interrupted run from its saved `state.json`. `<slug>` is the `<firstauthor>_<year>_<shorttitle>_<YYYY-MM-DD>` identifier printed when the run started. Re-uses the existing disposable notebook, lens plan, and completed-lens records; restarts at the next incomplete lens in Phase 3. |

All parsed flag values are persisted under `state.invocation` (Step 1.4); the runtime constants block below (`REVIEWER_MODEL`, `AUTHOR_MODEL`, `COMPACTION_THRESHOLD_CHARS`, `NOVELTY_CHECK_TIMEOUT_SECONDS`, etc.) is **not** runtime-configurable — edit SKILL.md to change those.

## Overview

This skill uploads a paper to a disposable NotebookLM notebook, then runs a structured adversarial debate across nine lenses weighted by detected paper type. Each round of each lens spawns a fresh Opus Reviewer (hostile Biostatistics referee) and a fresh Sonnet Author-surrogate (defends the paper using only paper-internal evidence retrieved via NotebookLM); the Moderator holds the running transcript and writes a read-reasoning-and-decision entry after every (Reviewer, Author) exchange, which steers the next round. A concurrent sub-call to the `novelty-check` skill provides external novelty verification. The output is a structured briefing with per-lens severity, top-5 killer questions, sub-project relevance, and a cite/build-on/flag/skip recommendation.

Spec reference: `quality_reports/specs/2026-04-22_paper-stress-test-design.md`.

> ### ⚠ Hollow-run red flags
>
> If **ANY** of these is true after Phase 3 completes, the skill has failed silently — do NOT proceed to Phase 4:
>
> - `state.transcript` is still `[]` after a lens has been marked complete.
> - `state.spawn_count` is still `0` after Phase 2a classification (classification itself spawns a Reviewer).
> - `len(state.moderator_assessments)` grows slower than `len(state.lenses_completed)`.
> - Any record in `state.lenses_completed` contains only `{lens_id, name, severity}` — the six content fields (`one_line_finding`, `evidence`, `author_best_defense`, `why_it_didnt_hold`, `summary_for_compaction`, `transcript_slice`) are absent or empty.
> - You wrote the Phase 5 briefing before all active lens debates finished.
> - `state.synthesis.recommendation` is anything other than `"cite" | "build-on" | "flag" | "skip"`.
> - `state.notebooks.disposable.disposition` is `null` or `"pending"` when `state.run_status` is `"completed"`.
>
> **Each gate below (G-3a, G-3b, G-3c, G-4a, G-5a) enforces one of these invariants.** A hollow run is a silent spec violation, not an alternative completion path. The post-hoc validator at `scripts/validate_state.py` re-checks the same invariants for audit.

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

> **Section references.** `T<N>` citations in this document are historical task IDs from the v1 implementation plan; they co-refer to the phase/step cited on the same line (e.g., "T11 Step 3.8.5" and "Step 3.8.5" are the same location). In new text, cite phase.step only — `T`-numbers are kept where they already appear for diff minimalism.

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

#### 8. Group-agent return payload (Phase 3 parallel dispatch)

Each of the three parallel group moderators (see §Phase 3, `agents/group_moderator.md`) returns a **single JSON object** as its final text, no prose preamble, no markdown fences. The Moderator parses every group return with this schema:

```
^\s*\{[\s\S]*"group_id"\s*:\s*([0-2])[\s\S]*"lens_records"\s*:\s*\[[\s\S]*\][\s\S]*"partial_state_path"\s*:\s*"([^"]+)"[\s\S]*\}\s*$
```

Validation (all MUST pass, otherwise treat the group as errored and re-dispatch once):

- Top-level parses as a JSON object with required keys: `group_id` ∈ {0,1,2}; `lens_records` (array, 0–3 entries); `local_gate_results` (object with `g3a_local` and `g3b_local` sub-objects each having boolean `passed`); `partial_state_path` (string, absolute path, file exists on disk); `group_spawn_count` (int ≥ 0); `aborted` (bool); `abort_reason` (string or null).
- For each entry in `lens_records`, all 9 keys from §G-3b (lens record schema) are present with correct types.
- If `aborted == false`, `len(lens_records) == 3`. If `aborted == true`, `abort_reason` is non-null.
- The file at `partial_state_path` exists, parses as JSON, and has the same `group_id` and `lens_records` as the return payload (consistency check).

Out-of-order arrival: the Moderator buffers payloads by `group_id` in a dict and does NOT begin merge/synthesis until `len(received) == 3` (or until all un-received groups have exhausted their retry budget, in which case G-3a-aggregate catches the hollow-run).

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
| 8. Group-agent return payload | Phase 3 Step 3.4 (parallel dispatch), Step 3.8 (merge) |

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
- Parsed flags: `depth`, `type_override`, `cross_check_override`, `skip_novelty`, `human_checkpoint`
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
    "skip_novelty": <parsed boolean>,
    "human_checkpoint": <parsed boolean, default true>
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
  "wall_clock_start": null,
  "wall_clock_budget_s": 1800,
  "abort_reason": null,
  "moderator_own_context_est_chars": 0,
  "run_status": "in_progress",
  "started_at": "<ISO 8601>",
  "completed_at": null
}
```

**Schema note (amended 2026-04-22):** The fields `reviewer_subagent`, `author_subagent`, and `reseed_history` that appeared in pre-amendment drafts are **removed**. Under the transcript-relay architecture there are no persistent subagent handles; `transcript` is the full turn-by-turn record (array of reviewer/author/moderator records per §Architecture Amendment), `moderator_assessments` is a flat index of the per-round Moderator entries for Phase 4 synthesis, and `compaction_history` replaces the old reseed-history field.

**Run-budget fields** (`spawn_count`, `spawn_budget`, `wall_clock_start`, `wall_clock_budget_s`, `abort_reason`, `moderator_own_context_est_chars`) are declared and documented in T11 Step 3.8.5; `wall_clock_start` is initialized as `null` here and set once at the start of Phase 3 (after plan confirmation) — this ensures idle wait time at the plan checkpoint is excluded from the budget. It is not reset on resume. Full enforcement semantics live in T7 Step 3.4 (budget gate at lens-loop top) and T10 (Moderator own-context soft budget).

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

If `invocation.human_checkpoint == false`: skip the prompt entirely — auto-proceed as if user answered `Y`. Print `[checkpoint skipped — --no-checkpoint active]` to chat and continue to Phase 3.

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
## Phase 3 — Adversarial debate loop (parallel 3×3 group dispatch)

> **Architecture at a glance.** The Moderator (the skill itself) does NOT iterate the 9 lenses. It dispatches **3 parallel group-agents** via a single assistant message containing 3 concurrent `Agent` tool calls. Each group-agent (`agents/group_moderator.md`) owns 3 pre-assigned lenses, runs the per-lens Reviewer↔Author debate inside its own context, writes an atomic partial state file, and returns a JSON payload (Parsing contract §8). The Moderator buffers the 3 returns by `group_id`, merges partial state files, re-runs G-3a/G-3b at aggregate level, and proceeds to Phase 4. **Steps 3.5 and 3.6 describe the per-lens debate loop that now runs inside each group-agent, not in the Moderator's own context.**

> **Anti-rationalization table — do NOT take these shortcuts.** Hollow runs (all lenses "completed" with empty state) arise when Moderator substitutes these framings for the actual debate loop. Each one is a spec violation.
>
> | Rationalization | Why it's wrong |
> |---|---|
> | "I can infer severity from Phase 2a classification output; no Reviewer spawn needed." | Severity must come from a Reviewer JUDGMENT emitted in an Agent spawn, per **Parsing contract §2** and Step 3.8 step 1. Classification in Phase 2a produces only `detected_type`, `headline_claim`, `novelty_claims` — not per-lens severities. |
> | "I'll write the briefing first, then backfill state.json at the end." | `state.json` is the source of truth and MUST be persisted per-group (Step 3.8). The briefing is DERIVED from state.json in Phase 5, never vice-versa. |
> | "The transcript belongs in `transcripts/*.md`, not in `state.transcript`." | Both. `state.transcript` is the machine-readable truth used by compaction (Step 3.7), resume (Resumability), and validator (Self-check). `transcripts/*.md` is a human-readable render produced in Step 5.2 from `state.lenses_completed[*].transcript_slice`. |
> | "The briefing is the deliverable; state.json is bookkeeping." | state.json is the deliverable. Partial-mode briefing (Step 5.1) reads from state.json when Phase 4 never ran; if state.json is hollow, partial-mode produces garbage. |
> | "I'll dispatch the 3 groups one at a time to stay under the spawn budget." | Sequential dispatch saves zero tokens (total spawn count is identical). Phase 3's purpose is wall-clock reduction via parallelism. The MUST-NOTs below make this a hard violation. |
> | "One group-agent failed — I'll re-run the other two sequentially in the Moderator to be safe." | Silent degradation to sequential is the exact hollow-run pattern the gates exist to catch. Re-dispatch the failed group (see Step 3.4 retry). Never run lens debates in the Moderator's own context. |
> | "I'll run the 9 lenses as 9 parallel Agent calls instead — more parallelism is better." | The architecture is 3×3 by design. 9-way fan-out triples persona-prompt tokens, fragments budget gates, and breaks the group_moderator.md contract. |
> | "I can compact each group-agent's transcript before merging to save memory." | Compaction happens in Step 3.7 AFTER merge, operated by the Moderator. Group-agents return verbatim transcript_slice entries; mid-flight compaction corrupts the audit trail. |

**MUST-NOTs for Phase 3 (hard spec violations, not preferences):**

1. **MUST dispatch all 3 group-agents in a single assistant message** containing 3 concurrent `Agent` tool_use blocks (Step 3.4 step 3). Sequential dispatch is a spec violation.
2. **MUST NOT await any group-agent result before dispatching the next.** The scheduler spawns all 3, then buffers returns.
3. **MUST NOT process lens records for Phase 4 until all 3 partial state files exist on disk AND the aggregate G-3a/G-3b gates pass** (Step 3.8 merge).
4. **MUST NOT run per-lens Reviewer or Author spawns in the Moderator's own context.** All per-lens debate happens inside group-agents. The Moderator orchestrates; it does not debate.
5. **MUST NOT write to the canonical `${FULL_SLUG}_state.json`** from within a group-agent. Group-agents write only to their own `${FULL_SLUG}_group_${N}.json` partial.

### Phase 3 start: Capture wall_clock_start

If `state.wall_clock_start` is `null`: set `state.wall_clock_start = now_iso()` and persist to `state.json`. This is the moment from which `wall_clock_budget_s` is measured — idle time at the Phase 2 plan confirmation prompt is intentionally excluded.

On resume: `wall_clock_start` is already set and is not reset. The budget continues counting from the original start time.

### Step 3.1: First novelty-check collection point (non-blocking)

This is the **first of two novelty-check check points** (T5 Step 2.6). Do NOT poll, sleep, or wait for the runner agent — per the harness convention, completion arrives as an asynchronous notification surfaced in the Moderator's context.

Check, in this order:

1. Has a background-agent completion notification for `state.novelty_check.runner_agent_id` arrived in the conversation so far? If YES: parse the runner's output per Parsing contract §7, update `state.novelty_check` to `status="completed"` with the parsed fields, `completed_at = now`. Continue Phase 3.
2. If NO notification yet: compute `elapsed = now - state.novelty_check.started_at`.
   - If `elapsed > NOVELTY_CHECK_TIMEOUT_SECONDS` (300): set `status = "timed_out"`, `completed_at = now`, `raw_report_md = null`. Continue. The runner will complete later on its own; its late output is discarded.
   - Otherwise: leave `status = "running"`. Continue Phase 3 immediately — Lens 7 will re-check at its start (T9 Step 9.1.1 in the amended layout).

No sleep, no polling. The second check point at Lens 7 catches results that arrive between this point and Lens 7.

### Step 3.2: Load persona templates once

Read all three persona files with the `Read` tool and keep them in Moderator memory:

```
REVIEWER_PERSONA        = Read(".claude/skills/paper-stress-test/agents/reviewer.md")
AUTHOR_PERSONA          = Read(".claude/skills/paper-stress-test/agents/author.md")
GROUP_MODERATOR_PERSONA = Read(".claude/skills/paper-stress-test/agents/group_moderator.md")
```

The Moderator passes `GROUP_MODERATOR_PERSONA` (with substitutions) as the prompt to each of the 3 group-agent spawns in Step 3.4. The group-agents in turn substitute and pass `REVIEWER_PERSONA` and `AUTHOR_PERSONA` to their own nested `Agent` calls. These are all stateless templates; there is no persistent subagent anywhere in this architecture.

### Step 3.3: Initialize transcript and moderator-assessment buffer

```
state.transcript              = []     # array of turn records (reviewer | author | moderator)
state.compaction_history      = []     # populated by Task 10 when threshold crossed
state.moderator_assessments   = []     # flat index of all moderator entries, for Phase 4 synthesis
```

Turn record shapes:

```json
// Reviewer turn
{"lens_id": N, "role": "reviewer", "round": R, "text": "...", "parsed": {...}, "terminal": false, "timestamp": "..."}

// Author turn
{"lens_id": N, "role": "author",   "round": R, "text": "...", "citations": [...], "timestamp": "..."}

// Moderator per-round entry (see §Moderator transcript entry schema in Architecture Amendment)
{"lens_id": N, "role": "moderator","round": R,
 "reasoning": "...", "signal": "progressing|stalling|converging",
 "decision":  "continue|inject_steer|close_lens", "steer": "..." | null,
 "timestamp": "..."}
```

Persist to disk after every lens completes (Task 11).

### Step 3.4: Parallel group-agent dispatch

**The Moderator does NOT iterate lenses.** It partitions the active lens plan into 3 groups of 3, dispatches all 3 group-agents in a **single assistant message** containing 3 concurrent `Agent` tool calls, buffers the JSON returns by `group_id`, then proceeds to Step 3.8 (merge).

**Group assignment.** Take `active = [l for l in state.lens_plan if l.depth > 0]` and partition by fixed lens_id bands:

```python
group_A = [l for l in active if l.lens_id in (0, 1, 2)]   # statistical / identification
group_B = [l for l in active if l.lens_id in (3, 4, 5)]   # ML / generalization
group_C = [l for l in active if l.lens_id in (6, 7, 8)]   # validity / positioning (lens 7 thematic)
```

If a band is empty (e.g., user skipped all 3 lenses in one band via `--type`), the Moderator still dispatches a group-agent with `lens_ids_assigned = []`; that agent returns immediately with `lens_records = []` and `local_gate_results.g3a_local.passed = true`. This keeps the receive-3 invariant uniform.

**Budget partitioning.** Per-group budgets:

- `GROUP_SPAWN_BUDGET = 3 + sum(2 * l.depth for l in group)` (see Step 3.8.5 updated formula).
- `GROUP_WALL_BUDGET_SECONDS = state.wall_clock_budget_s * 0.9 / 3` if we assume 90% of the remaining budget is spent in Phase 3 split roughly evenly; the 0.9 leaves headroom for merge + Phase 4/5.

**Dispatch (single assistant message, 3 concurrent Agent calls).** For each of the 3 groups, build the group_moderator.md prompt by substituting:

- `PAPER_TITLE`, `PAPER_AUTHORS`, `PAPER_YEAR`, `DISPOSABLE_NOTEBOOK_ID`, `THEMATIC_NOTEBOOK_ID` (from `state`).
- `GROUP_ID` (0 | 1 | 2), `GROUP_LENSES_JSON` (the 3-entry array; may be 0- or 2-entry if band is sparse), `OUT_ROOT`, `FULL_SLUG`.
- `GROUP_SPAWN_BUDGET`, `GROUP_WALL_BUDGET_SECONDS`, `NOVELTY_CHECK_JSON` (for Group C only — the Moderator passes `null` to Groups A and B).

Then issue the parallel dispatch via a single message with 3 `Agent` tool calls:

```python
# In a SINGLE assistant turn, emit three concurrent Agent tool calls.
dispatches = [
    Agent(subagent_type="general-purpose",
          description=f"stress-test group {gid}",
          prompt=group_prompt_for(gid, groups[gid])),
    for gid in (0, 1, 2)
]
# No awaiting between calls. The runtime executes them concurrently.
```

Buffer returns into `group_returns[group_id]` as each arrives. Do NOT begin merge or Phase 4 until `len(group_returns) == 3`.

**Parsing returns.** Each group return is parsed per **Parsing contract §8**. If parsing fails, re-dispatch that single group once (keep the other 2 returns). On second failure: record `state.groups[gid].status = "errored"`, abort to partial-mode briefing via Phase 5 with `partial=True`. The aggregate G-3a/G-3b gates at Step 3.8 will catch silent hollow returns regardless.

**Budget enforcement at dispatch time.** Before the 3-way dispatch, the Moderator performs ONE budget gate against the aggregate ceiling:

```python
check_budgets_before_dispatch()   # checks spawn_budget, wall_clock_budget_s, moderator_own_context_est_chars
```

Per-lens budget checks happen INSIDE each group-agent (they wrap their own Reviewer/Author spawns). The Moderator no longer calls `check_budgets_before_lens` — there is no outer lens loop.

**Spawn wrapper.** The Moderator's `spawn_agent(...)` wrapper (T11 Step 3.8.5) still wraps the 3 group-agent spawns and the Phase 2a classification call. Group-agents are responsible for counting their own internal spawns and returning `group_spawn_count`; the Moderator folds these into `state.spawn_count` at merge time (Step 3.8).

**Resume behavior.** On resume, Step 3.4 first globs `${OUT_ROOT}/state/${FULL_SLUG}_group_*.json`. For each group, if the partial exists AND `len(lens_records) == len(lens_ids_assigned)` AND `aborted == false`, treat it as complete and skip dispatch. Dispatch only the missing/incomplete groups in a single message (1, 2, or 3 concurrent calls depending on what's missing).

### Step 3.4.5: GATE G-3a — hollow-run invariants (local + aggregate)

Under parallel dispatch, G-3a fires at **two levels** (defense-in-depth):

**G-3a-local.** Runs inside each group-agent between its 3 lenses (see `agents/group_moderator.md` §Local gates). The group-agent checks, for every completed lens in its own group: `transcript_slice` length ≥ 3; `one_line_finding`, `author_best_defense`, `summary_for_compaction` non-empty; `group_spawn_count ≥ 1` after the first completed lens; `len(local_moderator_assessments) >= len(completed_lenses_in_group)`. On failure the group-agent sets `aborted=true`, writes its partial with whatever it has, and returns.

**G-3a-aggregate.** Runs in the Moderator **after merging all 3 partial state files** at Step 3.8, before Phase 4 synthesis. Predicate (all must hold; any `False` → `abort_run("hollow_run_detected", detail=<which>)`):

1. `state.wall_clock_start is not None` — Phase 3 start was reached.
2. `state.lenses_completed` is the union of the 3 groups' `lens_records` (no duplicates; all 9 distinct lens_ids present on normal completion).
3. For every `prior ∈ state.lenses_completed`:
   - `prior.transcript_slice` has `length >= 3` (Reviewer initial + Author answer + terminal Reviewer at minimum).
   - `prior.one_line_finding`, `prior.author_best_defense`, `prior.summary_for_compaction` are all non-empty strings (not `None`, not `""`, not `"not provided"` when severity ≠ `"errored"`).
4. Aggregate spawn accounting:
   - `state.spawn_count >= 3 + sum(l.group_spawn_count for l in group_returns)` — 3 group-agent dispatches plus every spawn they counted.
   - `len(state.moderator_assessments) >= len(state.lenses_completed)` — every completed lens must have contributed at least one moderator assessment entry (these are the per-group local assessments, concatenated on merge).

Abort behavior identical to Step 3.8.5's `abort_run`: writes partial briefing via Phase 5 with `partial=True`, persists `state.json`, terminates without Phase 4. The abort message names the exact invariant and the group_id(s) responsible so the user can diagnose which group produced hollow output. Resume via `--resume <slug>` re-dispatches the offending group(s); see §Resumability.

**Rationale.** G-3a-local catches the hollow-run pattern inside the group (the group-agent trying to advance without actually debating). G-3a-aggregate catches silent hollow returns from a group whose local gate was bypassed or corrupted, and also catches missing-lens errors (a group returning fewer records than assigned). Defense-in-depth is cheap: ~10 Python lines in `validate_state.py` and ~20 lines of prose here.

### Step 3.5: Standard lens debate (all lenses except 7)

> **Execution context.** The per-lens debate loop described below now runs **inside each group-agent**, not in the top-level Moderator. The Moderator itself never calls `run_standard_lens` — the group-agent (`agents/group_moderator.md`) does. This section remains the canonical specification of the loop for group-agents to follow. References to "Moderator" in this step mean the group-agent acting as a local moderator for its assigned lenses.

Function `run_standard_lens(lens, running_ctx)` — fresh `Agent` spawns per round, with a Moderator read-and-decide step after each (Reviewer, Author) exchange.

Local state inside the function:

```
lens_transcript       = []      # this lens's turns only; appended to state.transcript at end
latest_moderator_entry = None   # feeds the next round's Reviewer prompt
severity              = None    # set when the lens resolves
```

Per-round loop (`for round in 1..lens.depth`):

**1. Build and spawn fresh Reviewer (Opus).**

```
reviewer_prompt = build_reviewer_prompt(
    persona         = REVIEWER_PERSONA,
    paper_context   = state.paper,             # title/authors/year
    notebook_ids    = {
        "disposable": state.notebooks.disposable.id,
        "thematic":   state.notebooks.thematic.id,   # read-only for Lens 7 only
    },
    lens            = lens,                    # lens_id, name, description, depth
    round           = round,
    transcript      = running_ctx + lens_transcript,
    moderator_steer = (latest_moderator_entry.steer
                       if latest_moderator_entry and
                          latest_moderator_entry.decision == "inject_steer"
                       else None),
    close_lens_mode = (latest_moderator_entry is not None and
                       latest_moderator_entry.decision == "close_lens"),
)

reviewer_text = Agent(
    description       = "paper-stress-test reviewer (round " + round + ")",
    subagent_type     = "general-purpose",
    model             = "opus",
    prompt            = reviewer_prompt,
    run_in_background = False,
)
```

Parse `reviewer_text` per **Parsing contract** — which subsection depends on round:

- `round == 1` AND no prior Moderator `close_lens` → Parsing contract §1 (Format A: Primary question).
- `round > 1` AND not `close_lens_mode` → Parsing contract §2 (Format B: Judgment + decision, may be FOLLOWUP or FINAL).
- `close_lens_mode == True` → Parsing contract §2 Format B, FINAL only (Reviewer is instructed in the prompt to emit no new question).

Append to `lens_transcript`:

```json
{"lens_id": lens.lens_id, "role": "reviewer", "round": round,
 "text": reviewer_text, "parsed": <parsed fields>,
 "terminal": <true if FINAL or close_lens_mode>, "timestamp": "..."}
```

**2. Early exit if Reviewer returned FINAL.**

If `parsed.next == "FINAL"` OR `close_lens_mode == True`:

- `severity = parsed.severity` (use Severity-from-judgment fallback table below if missing).
- Skip Author turn; skip Moderator assessment.
- Break out of the per-round loop.

**3. Build and spawn fresh Author (Sonnet).**

```
author_prompt = build_author_prompt(
    persona           = AUTHOR_PERSONA,
    paper_context     = state.paper,
    disposable_nb_id  = state.notebooks.disposable.id,
    transcript        = running_ctx + lens_transcript,
    reviewer_question = parsed.question_or_followup,
)

author_text = Agent(
    description       = "paper-stress-test author (lens " + lens.lens_id + ", round " + round + ")",
    subagent_type     = "general-purpose",
    model             = "sonnet",
    prompt            = author_prompt,
    run_in_background = False,
)
```

Parse `author_text` per **Parsing contract §5 (Author answer turn)**. Append:

```json
{"lens_id": lens.lens_id, "role": "author", "round": round,
 "text": author_text, "citations": <extracted>, "timestamp": "..."}
```

**4. Moderator read / reason / decide (NEW — required by amendment).**

The Moderator (main Claude) performs these four actions in-context. No subagent spawn.

a. **Read** the round's two new turns (`lens_transcript[-2:]`) in the context of the full `lens_transcript` so far.

b. **Write reasoning paragraph** (2–5 sentences): what the Reviewer probed, what the Author cited or conceded, whether substance was advanced. Be plain and specific; avoid hedged summaries.

c. **Classify the debate state** as exactly one of `progressing | stalling | converging` per the definitions in §Per-round Moderator behavior of the Architecture Amendment.

d. **Choose a decision** as exactly one of:

- `continue` — transcript alone is steer enough; the next Reviewer spawn will build its own follow-up. Typical for `progressing`.
- `inject_steer` — craft a **single sentence** in field `steer` that will be prepended to the next round's Reviewer prompt as `## Moderator directive for this round`. Use when `stalling` (pivot to a new angle) or when `progressing` is drifting off-lens (re-anchor).
- `close_lens` — cut the lens off next round. Set `severity` on the subsequent terminal Reviewer turn. Use when `converging`, or when the remaining depth budget cannot plausibly add information.

Append the Moderator entry:

```json
{"lens_id": lens.lens_id, "role": "moderator", "round": round,
 "reasoning": "<paragraph>",
 "signal":    "progressing|stalling|converging",
 "decision":  "continue|inject_steer|close_lens",
 "steer":     "<one sentence>" | null,
 "timestamp": "..."}
```

Also append to `state.moderator_assessments` (flat index, used by Phase 4 synthesis).

Set `latest_moderator_entry = <the entry just appended>`.

**5. Act on `close_lens` decision.**

If `latest_moderator_entry.decision == "close_lens"` and there is remaining depth (`round < lens.depth`):

- Advance to the next round, which the per-round loop's top-of-iteration logic will run in `close_lens_mode` (the Reviewer prompt will forbid new questions and demand FINAL). Severity is set from that terminal Reviewer turn.

If the decision is `close_lens` but `round == lens.depth` (no depth left), force severity now: spawn one more Reviewer with `close_lens_mode=True` (ignoring depth exhaustion — this is the terminal turn), parse SEVERITY, append as `terminal: true`, break.

**6. Post-loop: force FINAL if depth ran out without resolution.**

After the per-round loop ends, if `severity` is still unset:

- Spawn one terminal Reviewer with `close_lens_mode=True` and depth-exhausted phrasing in the prompt.
- Parse SEVERITY; if missing or malformed, fall back to the Severity-from-judgment mapping below.

**7. Return `LensExchange` record.**

```json
{
  "lens_id":          lens.lens_id,
  "turns_used":       <count of Author turns in lens_transcript>,
  "severity":         <final severity>,
  "moderator_signals":[<signal-by-round array: "progressing","stalling",...>],
  "transcript_slice": <lens_transcript>
}
```

### Severity-from-judgment fallback (if Reviewer's SEVERITY is missing)

| Final judgment | Severity |
|----------------|----------|
| `cited`        | `clean`  |
| `handwaved`    | `minor`  |
| `evaded`       | `major`  |
| `conceded`     | `critical` |

Used only when the terminal Reviewer turn omits or malforms its SEVERITY line.

### Step 3.6: Lens 7 triangulation (positioning vs. prior work)

> **Execution context.** This loop runs **inside Group C's group-agent**, not in the top-level Moderator. The top-level Moderator passes the `THEMATIC_NOTEBOOK_ID` and (if available) the novelty-check top-3 as substitution variables into Group C's prompt. Group C executes the thematic query via `mcp__notebooklm__notebook_query` itself when it reaches lens 7. Group A and Group B never execute this step. References to "Moderator" below mean the Group C agent acting as a local moderator.

Function `run_lens_7(lens, running_ctx)` — fresh `Agent` spawns per round with Moderator-driven thematic retrieval and three-source confrontation. Structure: **(Q1 + thematic query) → Author defense → Moderator read/decide → Confrontation Reviewer → Author final defense → Terminal Reviewer**. The Moderator's read-and-decide step runs after every (Reviewer, Author) exchange, same as in Task 8. Lens 7 is terminal by design — depth is fixed at 3 Author turns maximum regardless of the planned `lens.depth`.

Lens 7 differs from the standard lens in THREE ways:

1. The first Reviewer prompt embeds the novelty-check summary INLINE (no separate seeding step).
2. The first Reviewer reply emits **both** `QUESTION` and `THEMATIC_QUERY` (Parsing contract §3). The Moderator — not the Reviewer — runs the thematic `notebook_query`.
3. The confrontation-round Reviewer prompt receives THREE sources: Author's Q1 defense + thematic evidence + novelty-check top-3 (Parsing contract §4).

Local state inside the function:

```
lens_transcript        = []
latest_moderator_entry = None
severity               = None
```

**Step 9.1.1: Late-arrival novelty-check re-collection.**

If `state.novelty_check.status == "running"`, re-check the notification queue exactly as in Step 3.1 once more — this is the second of the two collection points. Update `state.novelty_check` accordingly. Do not poll or sleep.

**Step 9.1.2: Build the novelty-seed block (one of four forms).**

```
if state.novelty_check.status == "completed":
    novelty_seed = (
        "## novelty-check report summary\n\n"
        "Overall score: " + state.novelty_check.overall_score + "/10\n"
        "Recommendation: " + state.novelty_check.recommendation + "\n"
        "Key differentiator: " + state.novelty_check.key_differentiator + "\n\n"
        "## Closest prior work (top 3)\n\n" + format_top3(state.novelty_check.closest_prior_work)
    )
elif state.novelty_check.status in {"errored", "timed_out", "skipped"}:
    novelty_seed = "## novelty-check: " + state.novelty_check.status + " — no external data available for this lens"
else:
    novelty_seed = "## novelty-check: still running at Lens 7 start — treat as unavailable"
```

**Step 9.1.3: Round 1 — Reviewer Q1 + thematic query.**

Build the first Reviewer prompt. Unlike a standard lens, the prompt contains the `novelty_seed` inline:

```
reviewer_prompt_r1 = build_lens7_reviewer_prompt(
    persona        = REVIEWER_PERSONA,
    paper_context  = state.paper,
    notebook_ids   = {"disposable": state.notebooks.disposable.id,
                      "thematic":   state.notebooks.thematic.id},
    lens           = lens,
    round          = 1,
    transcript     = running_ctx,
    novelty_seed   = novelty_seed,
    # Reviewer persona's Format C (initial Lens 7 turn) expects both outputs:
    require_output = "QUESTION + THEMATIC_QUERY",
)

reviewer_text_r1 = Agent(
    description="paper-stress-test reviewer (lens 7, round 1)",
    subagent_type="general-purpose", model="opus",
    prompt=reviewer_prompt_r1, run_in_background=False,
)

parsed_r1 = parse per Parsing contract §3   # extracts QUESTION and THEMATIC_QUERY
lens_transcript.append({"lens_id": 7, "role": "reviewer", "round": 1,
                        "text": reviewer_text_r1, "parsed": parsed_r1, "timestamp": now()})
```

**Step 9.1.4: Moderator queries the thematic notebook.**

```
if state.notebooks.thematic.id is not None and parsed_r1.thematic_query:
    thematic_evidence = mcp__notebooklm__notebook_query(
        notebook_id=state.notebooks.thematic.id,
        query=parsed_r1.thematic_query,
    )
else:
    thematic_evidence = None   # thematic was not resolved in Phase 1 (user chose [5])
```

**Step 9.1.5: Author defense for Q1.**

```
author_prompt_r1 = build_author_prompt(
    persona           = AUTHOR_PERSONA,
    paper_context     = state.paper,
    disposable_nb_id  = state.notebooks.disposable.id,
    transcript        = running_ctx + lens_transcript,
    reviewer_question = parsed_r1.question,
)

author_text_r1 = Agent(
    description="paper-stress-test author (lens 7, round 1)",
    subagent_type="general-purpose", model="sonnet",
    prompt=author_prompt_r1, run_in_background=False,
)

lens_transcript.append({"lens_id": 7, "role": "author", "round": 1,
                        "text": author_text_r1,
                        "citations": extract_citations(author_text_r1),
                        "timestamp": now()})
```

**Step 9.1.6: Moderator read / reason / decide after round 1.** Identical behavior to Task 8 Step 4; append moderator entry to `lens_transcript` and `state.moderator_assessments`. Set `latest_moderator_entry`.

If `latest_moderator_entry.decision == "close_lens"`: skip directly to Step 9.1.9 (terminal Reviewer) with `close_lens_mode=True`.

**Step 9.1.7: Round 2 — Confrontation Reviewer (three-source).**

Build a confrontation prompt that stacks three sources. Respect the degradation table below if any source is missing.

```
confrontation_prompt = build_lens7_confrontation_prompt(
    persona           = REVIEWER_PERSONA,
    paper_context     = state.paper,
    lens              = lens,
    round             = 2,
    transcript        = running_ctx + lens_transcript,
    author_defense    = author_text_r1,
    thematic_evidence = thematic_evidence,            # may be None
    novelty_top3      = state.novelty_check.closest_prior_work[:3]
                         if state.novelty_check.status == "completed" else None,
    moderator_steer   = (latest_moderator_entry.steer
                         if latest_moderator_entry.decision == "inject_steer"
                         else None),
    # Reviewer emits Format C (confrontation turn): CONFRONTATION OR JUDGMENT:cited/SEVERITY:clean
    require_output    = "CONFRONTATION or JUDGMENT+SEVERITY",
)

confrontation_text = Agent(
    description="paper-stress-test reviewer (lens 7, round 2, confrontation)",
    subagent_type="general-purpose", model="opus",
    prompt=confrontation_prompt, run_in_background=False,
)

parsed_r2 = parse per Parsing contract §4
lens_transcript.append({"lens_id": 7, "role": "reviewer", "round": 2,
                        "text": confrontation_text, "parsed": parsed_r2, "timestamp": now()})
```

**Step 9.1.8: Branch on confrontation output.**

If `parsed_r2` is `JUDGMENT: cited + SEVERITY: clean` (Author already differentiated): set `severity = "clean"`, mark that reviewer turn `terminal: true`, jump to Step 9.1.10.

If `parsed_r2.confrontation` is present: proceed to Author's final defense.

```
author_prompt_r2 = build_author_prompt(
    persona           = AUTHOR_PERSONA,
    paper_context     = state.paper,
    disposable_nb_id  = state.notebooks.disposable.id,
    transcript        = running_ctx + lens_transcript,
    reviewer_question = parsed_r2.confrontation,
)

author_text_r2 = Agent(
    description="paper-stress-test author (lens 7, round 2, rebuttal)",
    subagent_type="general-purpose", model="sonnet",
    prompt=author_prompt_r2, run_in_background=False,
)

lens_transcript.append({"lens_id": 7, "role": "author", "round": 2,
                        "text": author_text_r2,
                        "citations": extract_citations(author_text_r2),
                        "timestamp": now()})
```

**Step 9.1.9: Moderator read / reason / decide after round 2.** Same four-step pattern as Task 8 Step 4. Append moderator entry. Set `latest_moderator_entry`.

**Step 9.1.10: Terminal Reviewer (round 3).**

Spawn the terminal Reviewer with `close_lens_mode=True`. No further Author turn.

```
terminal_prompt = build_reviewer_prompt(
    persona         = REVIEWER_PERSONA,
    paper_context   = state.paper,
    notebook_ids    = {...},
    lens            = lens,
    round           = 3,
    transcript      = running_ctx + lens_transcript,
    moderator_steer = (latest_moderator_entry.steer
                       if latest_moderator_entry and latest_moderator_entry.decision == "inject_steer"
                       else None),
    close_lens_mode = True,     # forces Format B, FINAL only — JUDGMENT + SEVERITY
)

terminal_text = Agent(
    description="paper-stress-test reviewer (lens 7, round 3, terminal)",
    subagent_type="general-purpose", model="opus",
    prompt=terminal_prompt, run_in_background=False,
)

parsed_terminal = parse per Parsing contract §2
severity = parsed_terminal.severity or severity_from_judgment(parsed_terminal.judgment)
lens_transcript.append({"lens_id": 7, "role": "reviewer", "round": 3,
                        "text": terminal_text, "parsed": parsed_terminal,
                        "terminal": True, "timestamp": now()})
```

**Step 9.1.11: Return `LensExchange` record.**

```json
{
  "lens_id":           7,
  "turns_used":        <count of Author turns>,
  "severity":          <final severity>,
  "moderator_signals": [<signals by round>],
  "thematic_evidence_ref": {"used": <bool>, "notebook_id": ...},
  "transcript_slice":  <lens_transcript>
}
```

### Lens 7 degradation rules

| novelty-check status | thematic notebook | Sources at confrontation | Behavior |
|----------------------|-------------------|--------------------------|----------|
| completed            | resolved          | 3 (Author defense + thematic + novelty top-3) | Full triangulation as above. |
| completed            | null              | 2 (Author defense + novelty top-3)            | Skip Steps 9.1.3 `THEMATIC_QUERY`, 9.1.4 notebook_query; confrontation uses novelty top-3 only. Flag `thematic_evidence=None` in the LensExchange. |
| errored / timed_out / skipped | resolved | 2 (Author defense + thematic)                  | Set `novelty_seed` to its "unavailable" form; confrontation uses thematic only. |
| errored / timed_out / skipped | null    | 1 (Author defense only)                        | Lens 7 degrades to a standard lens run (call `run_standard_lens(lens, running_ctx)` and append a caveat `single_source=true` to the LensExchange). |

In the last row, the Moderator's read/reason/decide still applies per Task 8; the LensExchange's `single_source` flag is rendered in the briefing as a caveat.

### Step 3.7: Transcript compaction

Before each new lens (after a compaction check in Step 3.4), the Moderator examines the running transcript and compacts it if it has grown past `COMPACTION_THRESHOLD`. The returned `running_ctx` is what gets embedded in the next lens's Reviewer and Author prompts.

#### Constants

- `COMPACTION_THRESHOLD_CHARS = 80000` — default ~20K tokens at the char/4 heuristic.
- `MIN_LENSES_COMPACTED = 1` — never compact zero lenses; if only the current lens exists, skip compaction.

#### Function: `maybe_compact(transcript) -> running_ctx`

```
def maybe_compact(transcript):
    serialized = serialize_transcript(transcript)         # JSON Lines or similar plain text
    if len(serialized) < COMPACTION_THRESHOLD_CHARS:
        return transcript   # nothing to do

    completed_lens_ids = sorted({t["lens_id"] for t in transcript if t.get("terminal", False)})
    if len(completed_lens_ids) < MIN_LENSES_COMPACTED:
        return transcript   # don't compact the very first lens

    # 1. Summarize each completed lens to 1–2 sentences
    summary_bullets = []
    for lid in completed_lens_ids:
        lens_slice = [t for t in transcript if t["lens_id"] == lid]
        lens_meta  = find_lens_meta(lid)                  # name + description
        severity   = find_severity(lid)                   # from state.lenses_completed
        decisive   = find_decisive_exchange(lens_slice)   # last Reviewer judgment + Author cited passage, or the close_lens trigger

        summary_bullets.append(
            f"- Lens {lid} ({lens_meta.name}) — severity: {severity}. "
            f"Decisive exchange: {summarize_exchange(decisive, max_sentences=2)}"
        )

    # 2. Keep the current (in-flight or unresolved) lens verbatim
    current_lens_turns = [t for t in transcript if t["lens_id"] not in completed_lens_ids]

    # 3. Build running_ctx: header + bullets + current-lens verbatim
    running_ctx = [
        {"role": "moderator_note",
         "text": "## Transcript compaction applied — " + str(len(completed_lens_ids)) +
                 " completed lenses summarized below; current lens retained verbatim."},
        {"role": "moderator_summary",
         "text": "\n".join(summary_bullets)},
    ] + current_lens_turns

    # 4. Record the compaction event
    state.compaction_history.append({
        "at_lens":     current_lens_turns[0]["lens_id"] if current_lens_turns else None,
        "before_size": len(serialized),
        "after_size":  len(serialize_transcript(running_ctx)),
        "lenses_collapsed": completed_lens_ids,
        "timestamp":   now_iso(),
    })

    # 5. User-visible log
    emit_user_message(
        f"Compacting transcript at lens "
        f"{current_lens_turns[0]['lens_id'] if current_lens_turns else '(none)'}"
        f" — {len(completed_lens_ids)} previous lens(es) summarized, current lens retained verbatim."
    )

    return running_ctx
```

**Note on invariants:**

- `state.transcript` is NEVER mutated by compaction. The full transcript is preserved on disk for the final briefing (Task 13). `maybe_compact` only builds a compacted `running_ctx` to hand into the *next* lens's subagent prompts.
- Compaction fires before a new lens, never mid-lens. The in-flight lens's rounds always see full verbatim history of that lens.
- Moderator per-round entries (role: `moderator`) from completed lenses are rolled into the summary bullets by `summarize_exchange` (they are not retained verbatim). Moderator entries from the current lens are kept verbatim.

### Step 3.7.5: Moderator own-context soft budget

Transcript compaction shrinks the prompts that are sent INTO fresh subagent spawns. It does not shrink Main Claude's own conversation context, which accumulates every `Agent` tool result across ~50–65 per-run spawns. After a long run the Moderator's own context window can approach its ceiling independently of whatever compaction did for the subagents.

This is a distinct concern from `maybe_compact(transcript)` and is handled separately here.

#### Constants

- `MODERATOR_OWN_CONTEXT_SOFT_LIMIT_CHARS = 1600000` — default ~400K tokens at the char/4 heuristic. This is a soft limit: on hitting it we do not try to rescue the run mid-lens; we save state, write a partial briefing, and instruct the user to resume.
- `MODERATOR_OWN_CONTEXT_PAD_FRAC = 0.2` — buffer fraction reserved for the partial-briefing + cleanup steps after abort (so that crossing the soft limit doesn't prevent us from saving safely).

#### Tracked estimator

`state.moderator_own_context_est_chars` accumulates the length of every `Agent` tool result the Moderator has received during this run. The `spawn_agent` wrapper (defined in T11 Step 3.8.5) increments this field on every spawn; no other increment site exists.

The estimate is intentionally coarse. It undercounts (conversation metadata, Moderator's own output tokens, NotebookLM tool results are not included) but is monotone and cheap to compute. The soft limit is set low enough that a 10–20% undercount still leaves headroom before the harness's own ceiling.

#### Enforcement

Enforcement happens at the **top of each lens iteration**, folded into `check_budgets_before_lens(lens)` (T11 Step 3.8.5). If `state.moderator_own_context_est_chars >= MODERATOR_OWN_CONTEXT_SOFT_LIMIT_CHARS`, `check_budgets_before_lens` calls `abort_run(reason="moderator_context_exceeded", …)`, which writes a partial briefing and terminates cleanly.

**Why check only at lens boundaries, not mid-lens?** Because aborting mid-lens leaves a half-debated lens with no severity, and the extra ~3–6 spawns to finish a lens once started are bounded. The soft limit is sized generously enough that finishing the in-flight lens after a budget crossing is safe.

#### User-facing instruction on abort

The abort message (from T11 `abort_run`) points the user to resume via T18:

> ⚠️ Paper stress-test aborted — moderator_context_exceeded. Moderator context at <N> chars (≈<N/4> tokens) ≥ soft limit <L>. Partial briefing at `<path>`. Resume with the skill's `--resume <slug>` option; the resumed Moderator starts with a fresh context and rebuilds `running_ctx` from `state.transcript` via `maybe_compact()`.

On resume (T18), `state.moderator_own_context_est_chars` is **reset to 0** (new session = new Moderator context), and the resumed run continues from the first incomplete lens with a clean context budget. The wall-clock and spawn-count budgets are NOT reset by default (a runaway spawn loop should stay aborted even across a resume attempt), but may be raised by the user manually editing `state.spawn_budget` / `state.wall_clock_budget_s` before resume if the abort was legitimate-but-underbudgeted.

### Step 3.8: Merge group partials, assign severity, persist canonical state

> **Execution split.** Under parallel dispatch, severity assignment and per-lens record composition (substeps 1–3 below) happen **inside each group-agent** for its 3 lenses, as part of building its partial state file. The top-level Moderator's job at this step is (A) parse the 3 Pattern-8 JSON returns, (B) load and merge the 3 partial state files, (C) re-run G-3b aggregate, (D) atomically write the canonical state.json.

**Group-agent responsibilities (steps 1–3 below, performed 3 times inside each group-agent):** For each completed `LensExchange` the group-agent accumulates:

1. **If the terminal Reviewer turn returned a `SEVERITY:` line** (parsed per **Parsing contract §2**): use that directly.

2. **Else:** infer from the final JUDGMENT via the mapping:

   ```
   cited     -> clean
   handwaved -> minor
   evaded    -> major
   conceded  -> critical
   ```

3. **Compose the lens record.**

   > **⚠ MANDATORY FIELDS — copy this structure literally.** Nine keys are required; do NOT omit any. If content is truly absent, write an explicit `null` (for conditional keys) or `"not provided"` (for evidence when the Author said so) — an ABSENT KEY is a spec violation that GATE G-3b (step 6 below) will catch. `why_it_didnt_hold` is the only conditionally-omitted key (present only when `severity != "clean"`).

   ```json
   {
     "lens_id": lens.lens_id,
     "name": lens.name,
     "severity": <final severity>,
     "one_line_finding": <Moderator synthesizes from the terminal Reviewer JUDGMENT + REASONING>,
     "evidence": <Author's citation text if provided; "absent" if author said 'paper does not address this'>,
     "author_best_defense": <Author's final answer text>,
     "why_it_didnt_hold": <Reviewer's final REASONING, only if severity != "clean">,
     "summary_for_compaction": <Moderator writes 2-3 sentence summary immediately — used by T10 transcript compaction to collapse this lens when the running context grows past COMPACTION_THRESHOLD_CHARS>,
     "moderator_signals": <exchange.moderator_signals — per-round signal array: "progressing" | "stalling" | "converging">,
     "transcript_slice": <exchange.transcript_slice — all reviewer/author/moderator turns for this lens>
   }
   ```

   Moderator generates `one_line_finding` and `summary_for_compaction` by reading the exchange — these are NOT asked of either subagent. `summary_for_compaction` is what T10's `summarize_exchange` function returns when this lens is later rolled into the compacted `running_ctx`; storing it at lens-close time avoids re-summarizing on every subsequent compaction.

4. **Group-agent writes its partial state file** (NOT the canonical state.json). Atomic: `<group_partial>.tmp` → `mv`:

   ```bash
   <write group state to ${FULL_SLUG}_group_${N}.json.tmp>
   mv ${FULL_SLUG}_group_${N}.json.tmp ${FULL_SLUG}_group_${N}.json
   ```

   Schema: see `agents/group_moderator.md` §Partial state file schema. The canonical `state.json` is NEVER written from inside a group-agent.

5. **Group-agent emits local user-visible progress** (optional, to the group-agent's own return notes, not shared across groups):

   > [group N] Lens <M> (<name>) complete — severity: <severity>

6. **GATE G-3b-local — per-lens record validation inside group-agent.** Immediately after writing the partial in step 4 and before moving to the next lens in the group, verify the just-added record in memory. All must hold:

   - All nine required keys are present: `lens_id`, `name`, `severity`, `one_line_finding`, `evidence`, `author_best_defense`, `summary_for_compaction`, `moderator_signals`, `transcript_slice`. Plus `why_it_didnt_hold` when `severity != "clean"`.
   - `severity ∈ {"critical", "major", "minor", "clean", "errored"}`.
   - `transcript_slice` is a list with `length >= 3` (Reviewer initial + Author answer + terminal Reviewer at minimum; standard lenses typically have 4–6 entries, Lens 7 has 3 minimum).
   - `one_line_finding`, `author_best_defense`, `summary_for_compaction` are non-empty strings (not `None`, not `""`).
   - `moderator_signals` is a non-empty list.

   If any check fails inside the group-agent: mark the record `severity = "errored"`, set `why_it_didnt_hold = "G-3b-local failure: <which field>"`, and continue to the next lens. The aggregate gate (below) will catch errored-dominant groups.

---

**Top-level Moderator responsibilities (merge + aggregate gates):**

7. **Parse 3 Pattern-8 returns.** For each of the 3 group-agent results, apply Parsing contract §8. On parse failure, re-dispatch that single group once (Step 3.4). On second failure, record `state.groups[gid].status = "errored"` and proceed to Step 7.4 (partial briefing).

8. **Merge partial state files.** Load each `${FULL_SLUG}_group_${N}.json` from disk; verify `group_id` matches the Pattern-8 payload (consistency). Concatenate `lens_records` from groups 0, 1, 2 in `lens_id` order (0..8) into `state.lenses_completed[]`. Concatenate `group_transcript` entries in group_id order into `state.transcript[]`. Concatenate `local_moderator_assessments` (from each partial) into `state.moderator_assessments[]`.

9. **Fold spawn accounting.** `state.spawn_count = sum(g.group_spawn_count for g in returns) + 3` (+3 for the group-agent dispatches themselves).

10. **Atomically write the canonical state.json.** Use `<file>.tmp` → `mv`:

    ```bash
    cp state.json state.json.bak         # if already exists
    <write merged state to state.json.tmp>
    mv state.json.tmp state.json
    ```

    On write failure: retry once. Second failure → abort; the `.bak` preserves last good state.

11. **GATE G-3b-aggregate.** Re-run the per-record G-3b validation above against every record in `state.lenses_completed[]` after merge. Any failed record triggers `abort_run("lens_record_incomplete", detail=f"lens {lens_id} (group {origin_gid}): <which field>")` → Phase 5 with `partial=True`.

12. **GATE G-3a-aggregate.** Run §Step 3.4.5 G-3a-aggregate predicate against merged state. On failure: `abort_run("hollow_run_detected", detail=<which>)` → Phase 5 with `partial=True`.

13. **User-visible progress message:**

    > All 3 groups returned. Merged 9 lens records. Severity distribution: <critical/major/minor/clean tally>.

### Step 3.8.5: Run budget and abort fields

Worst-case spawn count for a depth-N run is ~9 lenses × (1 initial + 1 Author + 1 terminal) + up to ~3 retries per lens ≈ 50–65 `Agent` spawns. Worst-case wall clock approaches 30 minutes on slow NotebookLM. Without a hard abort mechanism, a hung lens or a runaway Moderator-steer loop can silently blow through both. The following fields in `state.json` close that hole.

**Schema additions to `state.json` (declared here; initialized in Phase 1 Step 1.4; incremented/enforced in Phase 3):**

```json
{
  ...
  "spawn_count":                  0,
  "spawn_budget":                 80,
  "wall_clock_start":             "<ISO 8601 — set once at Phase 0>",
  "wall_clock_budget_s":          1800,
  "abort_reason":                 null,
  "moderator_own_context_est_chars": 0
}
```

| Field | Meaning |
|-------|---------|
| `spawn_count` | Incremented by **1 on every `Agent(...)` call** across all phases (classification spawn, novelty-check runner, every per-round Reviewer and Author spawn). |
| `spawn_budget` | Hard ceiling. Default `80` (≈25% headroom over the ~65-spawn worst case). Configurable per-run by an eventual `--spawn-budget` arg (out of scope for v1). |
| `wall_clock_start` | ISO 8601 timestamp set once at the start of Phase 3 (after plan confirmation), ensuring idle wait at the plan checkpoint is excluded from the budget. Not reset on resume — a resumed run continues counting against the original budget. |
| `wall_clock_budget_s` | Default `1800` seconds = 30 minutes. |
| `abort_reason` | `null` for healthy runs. Set to one of `spawn_budget_exceeded`, `wall_clock_exceeded`, `moderator_context_exceeded`, or `fatal_error` on abort. |
| `moderator_own_context_est_chars` | Running estimate of cumulative characters Main Claude has ingested from `Agent` tool results (one contribution per spawn). See Step 3.7.5. |

**Enforcement (at the top of each lens iteration in Step 3.4):**

```
def check_budgets_before_lens(lens):
    elapsed_s = (now() - parse_iso(state.wall_clock_start)).total_seconds()
    if state.spawn_count >= state.spawn_budget:
        abort_run(reason="spawn_budget_exceeded",
                  detail=f"{state.spawn_count} spawns ≥ budget {state.spawn_budget}")
    if elapsed_s >= state.wall_clock_budget_s:
        abort_run(reason="wall_clock_exceeded",
                  detail=f"{elapsed_s:.0f}s ≥ budget {state.wall_clock_budget_s}s")
    if state.moderator_own_context_est_chars >= MODERATOR_OWN_CONTEXT_SOFT_LIMIT_CHARS:
        abort_run(reason="moderator_context_exceeded",
                  detail=f"{state.moderator_own_context_est_chars} ≥ limit {MODERATOR_OWN_CONTEXT_SOFT_LIMIT_CHARS}")
```

**`abort_run(reason, detail)` behavior:**

1. Set `state.abort_reason = reason`, `state.run_status = "aborted"`, `state.completed_at = now_iso()`.
2. Synthesize a **partial briefing** via the Phase 5 path with the `partial=True` flag: render whatever lenses are in `state.lenses_completed`, label the top-of-briefing status as `PARTIAL — aborted: <reason>`, fill `{{TOP_KILLER_QUESTIONS}}` / `{{RECOMMENDATION}}` with the string `N/A — run aborted before Phase 4 synthesis; see per-lens findings below`, and include the abort `detail` string prominently under the TL;DR.
3. Persist `state.json` atomically (same pattern as Step 3.8 step 4).
4. Emit user-visible:

   > ⚠️ **Paper stress-test aborted** — <reason>. <detail>. Partial briefing at `<path>`. Resume with the skill's `--resume <slug>` option (see error-handling section) to continue from lens <next_lens_id>.

5. Terminate the skill cleanly (do NOT run Phase 4 / 6 on an aborted run; Phase 5's partial-briefing writer IS invoked above).

**Spawn counter wrapper (required implementation pattern):**

> **MANDATE.** `spawn_agent` is the ONLY sanctioned path from Moderator to `Agent` in Phase 2a and Phase 3. Calling `Agent(...)` directly is a spec violation — GATE G-3a catches it at the next lens boundary (via `state.spawn_count >= 1`) and GATE G-3c catches it at end-of-Phase-3. If you catch yourself about to write `Agent(...)` directly, substitute `spawn_agent(...)` — same arguments, same return value. The wrapper exists because this substitution is the thing most often skipped under time pressure; skipping it is what produced the Lin 2021 hollow run (`spawn_count: 0` with 9 "completed" lenses).

Every `Agent(...)` call in Phase 3 (and Phase 2a's classification call) MUST go through `spawn_agent(...)` so the budget counters cannot be forgotten at a call site:

```
def spawn_agent(**kwargs):
    state.spawn_count += 1
    result = Agent(**kwargs)
    state.moderator_own_context_est_chars += len(result)
    return result
```

This is a drop-in wrapper and does not alter semantics.

### End of Phase 3

All active lenses are complete. `state.lenses_completed[]` has one entry per active lens. `state.transcript[]` has all turns (or the full uncompacted record on disk; compacted copies are in-memory only). No persistent subagents exist — every Reviewer and Author turn was a fresh synchronous `Agent` spawn.

**GATE G-3c — end-of-Phase-3 integrity.** Before emitting "Phase 3 complete" and entering Phase 4, assert all four hold:

1. `len(state.lenses_completed) == len([l for l in state.lens_plan if l.depth > 0])` — every active lens has a record.
2. `state.spawn_count >= 3 + sum(2 * l.depth for l in state.lens_plan if l.depth > 0)` — floor, not ceiling; 3 group-agent dispatches plus each depth unit requiring ≥1 Reviewer + ≥1 Author spawn inside its owning group. Lin 2021's `spawn_count: 0` fails this trivially. Old formula (pre-parallel, sequential Reviewer): `spawn_count >= 2 * sum(l.depth ...)` — kept here for diffing against legacy state files.
3. `len(state.moderator_assessments) >= len(state.lenses_completed)` — at least one moderator read/reasoning/decision entry per completed lens.
4. `len(state.transcript) >= sum(len(l.transcript_slice) for l in state.lenses_completed)` — transcript contains every turn from every lens slice.

If any fails → `abort_run("phase3_integrity_failed", detail=<which invariant>)`. Do NOT proceed to Phase 4 until all four hold. This is the latest point at which a hollow run can be surfaced before it pollutes Phase 4 synthesis with garbage.

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

**GATE G-4a — synthesis schema.** Before writing `state.synthesis` below:

- `RECOMMENDATION_ENUM = {"cite", "build-on", "flag", "skip"}`. If `recommendation` is anything else (including `"build-on-with-flags"`, `"strong-build-on"`, `"build-on-with-caveats"`, or any hyphenated variant), **re-run** the decision rule above and pick a valid value. The rule is total — it always yields exactly one of the four.
- Field name is `verdict`, NOT `tldr_verdict`. There is no `tldr_verdict` key anywhere in the spec; the Phase 5 template placeholder is `{{VERDICT}}` (see Step 5.1).
- All five synthesis keys below are REQUIRED: `verdict`, `top_killer_questions`, `subproject_relevance`, `recommendation`, `recommendation_rationale`. `top_killer_questions` is an array (`[]` when truly empty, never a pointer string like `"See briefing § Top 5 killer questions"`). `subproject_relevance` is an object, never a pointer string.

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
## Phase 5 — Write artifacts

Phase 5 has two invocation modes:

- **Normal** (`partial=False`, default) — called at end of Phase 4 on a healthy run. All sections of the briefing are rendered.
- **Partial** (`partial=True`) — called by `abort_run` (Step 3.8.5) when a run-budget was exceeded. The briefing is rendered with whatever data is available (mostly Phase 3 lens records, no Phase 4 synthesis), and a PARTIAL banner at the top.

### Step 5.1: Render briefing

Read `.claude/skills/paper-stress-test/templates/briefing.md`. For each placeholder `{{...}}`, substitute the matching value from state.json.

**Partial-mode substitution rules (when invoked with `partial=True`):**

- `{{VERDICT}}` → `"PARTIAL — aborted: " + state.abort_reason + ". " + <detail sentence from abort_run>`.
- `{{TOP_KILLER_QUESTIONS}}` → the literal string `"N/A — run aborted before Phase 4 synthesis; see per-lens findings below."`.
- `{{RECOMMENDATION}}` → the literal string `"N/A — synthesis not performed."`.
- `{{SUBPROJECT_RELEVANCE}}` → the literal string `"N/A — synthesis not performed."`.
- `{{NOVELTY_SECTION}}` → render from `state.novelty_check` as usual if available; else literal `"N/A"`.
- `{{SEVERITY_TABLE}}`, `{{PER_LENS_FINDINGS}}`, `{{SKIPPED_LENSES}}` → render from `state.lenses_completed` as usual (whatever lenses actually completed get rendered; uncompleted lenses appear under `{{SKIPPED_LENSES}}` with reason `"run aborted"`).

The briefing filename gets a `-partial` suffix in partial mode: `<slug>_briefing-partial.md` rather than `<slug>_briefing.md`.

**Normal-mode substitution table:**

| Placeholder | Source |
|------------|--------|
| `{{PAPER_TITLE}}` | `state.paper.title` |
| `{{PAPER_AUTHORS}}` | `state.paper.authors.join(", ")` |
| `{{PAPER_YEAR}}` | `state.paper.year` |
| `{{PAPER_SOURCE}}` | `state.paper.source` |
| `{{STRESS_TEST_DATE}}` | today (YYYY-MM-DD) |
| `{{DETECTED_TYPE}}` | `state.detected_type` |
| `{{DEPTH}}` | `state.invocation.depth` |
| `{{REVIEWER_MODEL}}` | `REVIEWER_MODEL` constant from SKILL.md (default `claude-opus-4-7`) — this is the model used for every per-round Reviewer spawn in Phase 3; no subagent handle is persisted under the transcript-relay architecture. |
| `{{AUTHOR_MODEL}}` | `AUTHOR_MODEL` constant from SKILL.md (default `claude-sonnet-4-6`) — model used for every per-round Author spawn in Phase 3. |
| `{{VERDICT}}` | `state.synthesis.verdict` |
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

**GATE G-5a — no early return.** Phase 5 does NOT emit the final user-visible summary and does NOT return control to the user; Phase 6 (Step 6.6) does. If you are composing a final reply without having completed Step 6.1 (inline summary), Steps 6.2–6.4 (notebook disposition — Delete / Keep / Promote), Step 6.5 (/tmp cleanup), and Step 6.6 ("Done" line) — STOP and run Phase 6 first. The run is not complete until `state.notebooks.disposable.disposition ∈ {"deleted", "kept", "promoted"}` — `"pending"` and `null` are both spec violations that would leave the disposable NotebookLM notebook leaking. Only the aborted-run path (Step 3.8.5) is allowed to return control with `run_status = "aborted"` and a Phase-6-skipped state.

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
| Running transcript approaches `COMPACTION_THRESHOLD_CHARS` (80000) | Compact the transcript (Phase 3.7) — summarize completed lenses to their `summary_for_compaction` bullets; current lens remains verbatim. The full `state.transcript` is preserved on disk. |
| `state.spawn_count >= state.spawn_budget` (default 80) | `abort_run("spawn_budget_exceeded", …)` at top of next lens iteration. Write partial briefing (Phase 5 with `partial=True`); instruct user to resume. |
| Wall-clock elapsed ≥ `state.wall_clock_budget_s` (default 1800s) | `abort_run("wall_clock_exceeded", …)` at top of next lens iteration. Same partial-briefing + resume flow. |
| `state.moderator_own_context_est_chars >= MODERATOR_OWN_CONTEXT_SOFT_LIMIT_CHARS` (1_600_000 chars ≈ 400K tokens) | `abort_run("moderator_context_exceeded", …)` at top of next lens iteration. Same flow. Resume starts a fresh Moderator context and rebuilds `running_ctx` via `maybe_compact()` from `state.transcript`. |
| state.json write fails | Retry once using `.bak`; second failure fatal. |
| User aborts at plan confirmation | Delete disposable notebook; do not write state file; exit cleanly. |
| `novelty-check` sub-call fails | Set `state.novelty_check.status = "errored"`; continue; Lens 7 falls back (Phase 3.6 degradation table). |
| `novelty-check` not finished at user confirmation | Wait with status message; after 5 min total, mark `timed_out`; proceed. |
| Phase 6 promote (`source_add` to thematic) fails | Do NOT delete disposable. Mark `disposition = "pending"`. Print error. User can retry manually. |

## Self-check (post-hoc validator)

`scripts/validate_state.py` loads a `<slug>_state.json` and checks gates G-3a, G-3b, G-3c, G-4a, G-5a. Exits `0` on a well-formed run, `1` on any violation, `2` on I/O or JSON error. The validator is NOT invoked at runtime — the runtime gates above enforce equivalents; this exists for:

1. **Post-hoc triage** of legacy runs that completed despite violations (e.g., the Lin 2021 hollow run before G-3a/G-3b existed).
2. **Regression testing** proposed SKILL.md edits against archived failed runs. Any gate that doesn't fire on a known hollow run is a gate whose predicate needs patching.

Invocation:

```bash
python3 .claude/skills/paper-stress-test/scripts/validate_state.py \
  master_supporting_docs/supporting_papers/stress_tests/state/<slug>_state.json
```

Output format: `GATE G-XY FAIL: lens <id> (<name>) <which field>` — one line per violation, followed by the total count. Stdlib-only Python 3; no pytest or extra deps.

## Resumability

Under the **parallel 3×3 group-dispatch architecture**, resumability is **group-level, not per-lens**. Each group-agent writes its own `${FULL_SLUG}_group_${N}.json` partial state file atomically as it finishes each of its 3 lenses. The top-level Moderator merges partials into the canonical `state.json` only after all 3 groups return. If a run is interrupted, resume dispatches only the groups whose partial file is missing or incomplete.

**Resume unit.** "Group N complete" or "Group N missing/incomplete" — per-lens-within-group resume is NOT supported. A partial group is re-run from scratch; its prior partial file is overwritten. This is a deliberate trade-off: group-agents complete in ~5–8 min, so re-running a partial group is cheaper than engineering mid-group checkpointing. **If you lose a 4-hour run to a crash during group C's lens 7, expect to re-run all three of group C's lenses, not just lens 7.**

On resume the next invocation on the same `<paper-ref>` the same day sees the existing `state.json` and any `*_group_*.json` partials and offers:

```
A stress-test with today's slug is already in progress:
  {{FULL_SLUG}}_state.json (run_status: in_progress)
  Partial groups on disk: [0: complete | 1: incomplete (2/3 lenses) | 2: missing]

Choose:
  [R] Resume (re-dispatch incomplete/missing groups: [1, 2]; reuse group 0's partial)
  [S] Start fresh (overwrites state AND all partials; existing briefing untouched if already written)
  [A] Abort
```

### Resume behavior ([R])

1. Load `state.json` fully (it may be empty if no merge ever happened) and glob `${OUT_ROOT}/state/${FULL_SLUG}_group_*.json` to enumerate existing partials.
2. **Clean up stale novelty-check state.** On resume, any background `runner_agent_id` from the prior session has long since expired. Apply:
   - If `state.novelty_check.status == "running"`: set `status = "timed_out"`, `completed_at = <ISO now>`, `raw_report_md = null`.
   - Otherwise: keep as-is.
3. **Apply run-budget reset policy** (see Step 3.7.5 and Step 3.8.5):
   - `state.moderator_own_context_est_chars` → **reset to 0** (new session).
   - `state.spawn_count` → **preserved** (runaway spawn loops should stay aborted across resume).
   - `state.wall_clock_start` → **preserved**.
   - `state.abort_reason` → **cleared to `null`**.
   - To raise a budget: edit `state.spawn_budget` / `state.wall_clock_budget_s` manually before resume.
4. Verify disposable and thematic notebooks still exist via `mcp__notebooklm__notebook_list()`. If missing: abort with error.
5. **Classify each group's partial:**
   - **Complete:** partial exists, parses, has `len(lens_records) == len(lens_ids_assigned)`, `aborted == false`. Treat group as done; skip re-dispatch.
   - **Incomplete:** partial exists but has fewer records than assigned, OR `aborted == true`. Mark for re-dispatch; existing partial will be overwritten.
   - **Missing:** no partial file. Mark for re-dispatch.
6. Load `REVIEWER_PERSONA`, `AUTHOR_PERSONA`, `GROUP_MODERATOR_PERSONA` from disk (Step 3.2).
7. **Re-dispatch only incomplete/missing groups.** Build the group_moderator prompt for each re-dispatched group (same substitutions as a fresh run). Issue them in a single assistant message containing 1–3 concurrent `Agent` tool_use blocks (Step 3.4 parallel dispatch). Groups marked complete are NOT re-dispatched.
8. **Merge.** After all re-dispatched groups return, follow Step 3.8 merge protocol (load all 3 partials — including the ones carried over from the prior session — into the canonical `state.json`). Run G-3a-aggregate and G-3b-aggregate.
9. Continue to Phases 4, 5, 6 normally.
10. Record the resume event in `state.compaction_history`:

    ```json
    {"at_group_resume": <true>, "re_dispatched_groups": [<gid>, ...], "reason": "session resume", "timestamp": "<ISO 8601>"}
    ```

**Non-determinism warning.** Re-dispatched groups produce fresh debate transcripts, not literal replays of their prior attempt. Severity assignments may shift by 1 bucket due to LLM noise. Group partials that were classified as "complete" in step 5 are preserved verbatim, so their outputs remain stable across resume.

### Start fresh ([S])

Delete the old state.json (do NOT delete the old briefing if it was ever written — that's a record). Delete the old disposable notebook (it will be recreated). Restart from Phase 1.

### Abort ([A])

Exit cleanly, leave state.json untouched.
