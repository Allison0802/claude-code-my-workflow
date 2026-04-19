---
name: auto-paper-improvement-loop
description: "Autonomously improve a generated paper via external review → implement fixes → recompile, for 2 rounds. Use when user says \"改论文\", \"improve paper\", \"论文润色循环\", \"auto improve\", or wants to iteratively polish a generated paper."
argument-hint: [paper-directory]
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Agent, mcp__codex__codex, mcp__codex__codex-reply, mcp__notebooklm__notebook_query
---

# Auto Paper Improvement Loop: Review → Fix → Recompile

Autonomously improve the paper at: **$ARGUMENTS**

## Context

This skill is designed to run **after** Workflow 3 (`/paper-plan` → `/paper-figure` → `/paper-write` → `/paper-compile`). It takes a compiled paper and iteratively improves it through external LLM review.

Unlike `/auto-review-loop` (which iterates on **research** — running experiments, collecting data, rewriting narrative), this skill iterates on **paper writing quality** — fixing theoretical inconsistencies, softening overclaims, tightening simulation design, and improving presentation.

**Domain context:** Papers in this project are biostatistics methodology papers — they present new statistical estimators or methods for survival/recurrent event data. Key venues: *Biometrics*, *Biostatistics*, *Statistics in Medicine*, *JASA*, *JRSS-B*, *Annals of Applied Statistics*. The reviewer persona, review criteria, and fix patterns below are calibrated for methodology papers, not ML conference papers.

## Constants

- **MAX_ROUNDS = 2** — Two rounds of review→fix→recompile. Round 1 catches structural issues (assumption gaps, simulation design flaws); Round 2 catches presentation and coverage issues.
- **REVIEWER_MODEL = `gpt-5.4`** — Model used via Codex MCP for paper review (ignored when using subagent backend).
- **REVIEWER_BACKEND = `auto`** — Which reviewer to use. Values: `auto` (detect Codex MCP, fall back to subagent), `codex` (force Codex MCP), `subagent` (force Claude subagent). See **Reviewer Backend** section below.
- **REVIEW_LOG = `PAPER_IMPROVEMENT_LOG.md`** — Cumulative log of all rounds, stored in paper directory.
- **HUMAN_CHECKPOINT = false** — When `true`, pause after each round's review and present score + weaknesses to the user. The user can approve fixes, provide custom modification instructions, skip specific fixes, or stop early. When `false` (default), runs fully autonomously.
- **FLOW_PREPASS = true** — When `true` (default), spawn a logic flow pre-pass subagent before **every** review round (Round 1 through Round MAX_ROUNDS) to produce a section-level and paragraph-level reverse outline. Output is injected into the reviewer prompt as structural scaffolding. When `false`, skip the pre-pass for all rounds; reviewer prompts are byte-identical to current behavior.
- **NOTEBOOKLM_NOTEBOOKS** — Two NotebookLM notebooks consulted during fix implementation for domain accuracy:
  - `0bf80af5-8b8d-423d-b7ef-94b13ad48f7b` — ML for Recurrent Events (pseudo-observation theory, recurrent event methodology, competing risks, C-index)
  - `fea2207b-7ec1-463c-b73f-58c0c4febb41` — Interpretable AI (ML model assumptions, interpretability claims, method comparisons)

> 💡 Override: `/auto-paper-improvement-loop "paper/" — human checkpoint: true, reviewer: subagent, flow prepass: false`

**Reviewer fallback & NotebookLM:** When Codex MCP is unavailable, this skill falls back to a Claude subagent reviewer (same biostatistics associate-editor persona). Before implementing CRITICAL/MAJOR fixes, consult NotebookLM for domain accuracy. See `.claude/rules/codex-fallback-protocol.md` for full protocol.

## Inputs

1. **Compiled paper** — `paper/main.pdf` + LaTeX source files
2. **All section `.tex` files** — concatenated for review prompt

## State Persistence (Compact Recovery)

If the context window fills up mid-loop, Claude Code auto-compacts. To recover, this skill writes `PAPER_IMPROVEMENT_STATE.json` after each round:

```json
{
  "current_round": 1,
  "threadId": "019ce736-...",
  "reviewer_backend": "codex",
  "last_score": 6,
  "status": "in_progress",
  "timestamp": "2026-04-04T21:00:00"
}
```

> `threadId` is only populated when `reviewer_backend` is `"codex"`. When `"subagent"`, threadId is `null` and the Round 1 review text is stored in the improvement log for Round 2 context.

**On startup**: if `PAPER_IMPROVEMENT_STATE.json` exists with `"status": "in_progress"` AND `timestamp` is within 24 hours, read it + `PAPER_IMPROVEMENT_LOG.md` to recover context, then resume from the next round. Otherwise (file absent, `"status": "completed"`, or older than 24 hours), start fresh.

**After each round**: overwrite the state file. **On completion**: set `"status": "completed"`.

## Workflow

### Step 0: Preserve Original

```bash
cp paper/main.pdf paper/main_round0_original.pdf
```

### Step 1: Collect Paper Text

Concatenate all section files into a single text block for the review prompt:

```bash
# Collect all sections in order
for f in paper/sections/*.tex; do
    echo "% === $(basename $f) ==="
    cat "$f"
done > /tmp/paper_full_text.txt
```

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

**Branch by `REVIEWER_BACKEND`:**

#### If backend = `codex`

Send the full paper text to GPT-5.4 xhigh using the **biostatistics methodology** reviewer persona:

```
mcp__codex__codex:
  model: gpt-5.4
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [REVIEWER_PROMPT below]
```

Save the threadId for Round 2.

#### If backend = `subagent`

Spawn a Claude subagent with the same persona and review instructions:

```
Agent:
  description: "Paper review round 1"
  model: "opus"
  prompt: |
    [REVIEWER_PROMPT below]
```

Save the full review response text for Round 2 context.

#### REVIEWER_PROMPT (shared by both backends)

```
You are a senior associate editor at Biometrics with expertise in survival analysis,
recurrent events, competing risks, and semiparametric efficiency theory.
Review the following biostatistics methodology paper.

## Full Paper Text:
[paste concatenated sections]

## Review Instructions

Provide a structured review covering ALL of the following:

### 1. Overall Score (1–10)
Where: 5 = major revision, 6 = minor revision, 7 = accept with minor changes, 8 = accept.
Typical range for a novel, technically sound method paper submitted to Biometrics: 6–7.

### 2. Summary (3–4 sentences)
What does the paper do? What is the key methodological contribution?

### 3. Strengths (bullet list, ranked)

### 4. Weaknesses (bullet list, ranked: CRITICAL > MAJOR > MINOR)

For each CRITICAL or MAJOR weakness, provide:
- The specific problem
- Why it matters for validity or reproducibility
- A concrete, actionable fix

### 5. Statistical Rigor Checklist
Evaluate each dimension (OK / Needs work / Missing):

**Estimand & identification:**
- [ ] Estimand is precisely defined (population quantity, not just "estimate something")
- [ ] Identifiability conditions are stated and justified
- [ ] Causal vs. predictive framing is consistent throughout

**Asymptotic theory:**
- [ ] Regularity conditions are stated (are they verifiable in practice?)
- [ ] Consistency result: is the rate stated? Under what norm?
- [ ] Asymptotic normality: influence function or sandwich estimator referenced?
- [ ] Is the convergence rate optimal (semiparametric efficiency bound)?
- [ ] Are results valid under censoring / competing risks / recurrence?

**Simulation study:**
- [ ] Scenarios cover all key operating conditions (sample size × censoring × correlation × complexity)
- [ ] Data-generating process is fully specified and reproducible (seed, package, parameters)
- [ ] Performance metrics are appropriate: bias, empirical SE, ASE, coverage (for CIs), type I error (for tests), time-specific C-index (for predictive methods)
- [ ] Competing methods are fairly tuned (same hyperparameter search, same data)
- [ ] Table captions fully describe what is shown (no reliance on text for decoding)
- [ ] Monte Carlo SE reported for key metrics
- [ ] Number of replications is justified

**Real data analysis:**
- [ ] Clinical context explained for non-specialist readers
- [ ] Data availability / access statement included
- [ ] Results interpreted substantively, not just "model fits better"
- [ ] Sensitivity analysis for key assumptions

**Software & reproducibility:**
- [ ] R package or code repository mentioned
- [ ] All simulation parameters listed (sufficient to replicate)

### 6. Notation & Presentation
- Notation introduced before first use?
- Conflicts between symbols (e.g., same letter for two things)?
- Tables/figures referenced in order? Captions self-contained?

### 7. Missing References
Key methodological predecessors, competing methods, or applications papers that must be cited.

### 8. Verdict
Ready for submission to Biometrics/Biostatistics/Statistics in Medicine?
- Yes (minor polish only) / Almost (1–2 substantive issues) / No (major gaps)
```

### Step 2b: Human Checkpoint (if enabled)

**Skip if `HUMAN_CHECKPOINT = false`.**

Present the review results and wait for user input:

```
📋 Round N review complete.

Score: X/10 — [verdict]
Key weaknesses (by severity):
1. [CRITICAL] ...
2. [MAJOR] ...
3. [MINOR] ...

Reply "go" to implement all fixes, give custom instructions, "skip 2" to skip specific fixes, or "stop" to end.
```

Parse user response: approve / custom instructions / skip / stop.

### Step 3: Implement Round 1 Fixes

Parse the review and implement fixes by severity:

**Priority order:**
1. CRITICAL fixes (estimand misspecification, missing regularity conditions, broken simulation design)
2. MAJOR fixes (overclaims, missing coverage metrics, notation conflicts, missing references)
3. MINOR fixes (if time permits: caption gaps, phrasing, style)

#### NotebookLM consultation (before each CRITICAL/MAJOR fix)

Before implementing a CRITICAL or MAJOR fix, query both NotebookLM notebooks to ground the fix in established theory:

```
mcp__notebooklm__notebook_query:
  notebook_id: "0bf80af5-8b8d-423d-b7ef-94b13ad48f7b"
  query: "[targeted question derived from the reviewer's criticism and proposed fix]"

mcp__notebooklm__notebook_query:
  notebook_id: "fea2207b-7ec1-463c-b73f-58c0c4febb41"
  query: "[targeted question about ML methodology or interpretability claims]"
```

Use the notebook response to:
- Verify the proposed fix is theoretically sound
- Find correct citations and formal statements (e.g., exact regularity conditions from Andersen et al.)
- Avoid introducing new errors while fixing old ones
- Ground any softened claims in what the notebooks confirm about the method's properties

If NotebookLM is unavailable, skip silently and proceed with fixes using available knowledge. Log: `"NotebookLM unavailable — fixes applied without notebook consultation"`.

When a notebook query informs a fix, note it in the improvement log: `"Fix grounded in NotebookLM: [notebook name] — [key finding]"`.

**Biostatistics methodology fix patterns:**

| Issue | Fix Pattern |
|-------|-------------|
| Estimand vaguely defined | Add formal notation: "Let μ(t; x) = E[N(t) \| X = x] where N(t) is the cumulative event count at time t for a subject with covariate vector x" |
| Identifiability not stated | Add "Identification relies on (i) no unmeasured confounding, (ii) coarsening-at-random, (iii) positivity" |
| Regularity conditions absent | Add an "Assumption" environment listing smoothness, boundedness, and rate conditions; note which are verifiable |
| Asymptotic rate missing | Add "…at rate n^{-1/2} under Assumption X" to theorem statement |
| Overclaim: "our method is consistent" without proof sketch | Soften to "Consistency follows under Assumptions 1–3, which hold in our simulation settings; formal proof is deferred to the Supplement" |
| Overclaim: "outperforms all methods" | Soften to "achieves lower MSE than Cox and RF under the complex frailty scenarios considered" |
| Simulation: censoring not specified | Add "Censoring times were drawn from Exponential(λ_c) with λ_c chosen to yield approximately 30% administrative censoring" |
| Simulation: competing methods not tuned | Add "All methods used 5-fold CV on training data for hyperparameter selection; details in Supplement S2" |
| Coverage not reported (interval estimator) | Add coverage column to simulation table; add ASE vs. empirical SE comparison |
| Time-specific C-index not averaged correctly | Clarify whether using IBS (integrated Brier score) or mean C-index; add weighting scheme |
| Missing seed / reproducibility info | Add "All simulations used set.seed(YYYYMMDD) and are available at [repo]" |
| Real data: no sensitivity analysis | Add paragraph: "To assess robustness to the proportional hazards assumption, we re-fit using a stratified model…" |
| Notation conflict (e.g., λ for hazard and for tuning) | Rename one globally; add Notation paragraph after introduction |
| Self-contained table captions | Rewrite to include: method abbreviations, n, number of replications, metric definition, and what bold means |
| Theory-practice gap | Add "Assumption X may not hold in practice when… In our simulation settings, we verify it holds by…" |
| Missing software statement | Add to Discussion: "An R package implementing the proposed method is available at…" |

### Step 4: Recompile Round 1

```bash
cd paper
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode main.tex
BIBINPUTS=..:$BIBINPUTS bibtex main
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode main.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode main.tex
cp main.pdf main_round1.pdf
```

Verify: 0 undefined references, 0 undefined citations.

## Round N Loop Body (N = 2 to MAX_ROUNDS)

`N` is the current round number. Execute this section for N = 2, 3, …, MAX_ROUNDS in sequence: re-collect → pre-pass → review → checkpoint → fix → recompile.

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

### Step N.1: Round N Review

**Before this step:** Run Step R.0 (re-collect paper text) then Step 1.5 (logic flow pre-pass, if `FLOW_PREPASS = true`).

**Branch by `REVIEWER_BACKEND`:**

#### If backend = `codex`

Use `mcp__codex__codex-reply` with the saved threadId:

```
mcp__codex__codex-reply:
  threadId: [saved from Round 1]
  model: gpt-5.4
  config: {"model_reasoning_effort": "xhigh"}
  prompt: |
    [ROUND_N_PROMPT below]
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

#### ROUND_N_PROMPT (shared by both backends, applies to all rounds N ≥ 2)

```
[Round N update]

Since your last review, we have implemented:
1. [Fix 1]: [description]
2. [Fix 2]: [description]
...

Please re-score and re-assess using the same structured format:
Score, Summary, Strengths, Weaknesses (CRITICAL/MAJOR/MINOR with fixes),
Statistical Rigor Checklist, Notation, Missing References, Verdict.

Pay particular attention to:
- Whether regularity conditions and the simulation design now align
- Whether all CI/coverage claims are backed by table evidence
- Whether notation is globally consistent
- Whether the real data section adds substantive insight
```

### Step N.2: Human Checkpoint (if enabled)

**Skip if `HUMAN_CHECKPOINT = false`.** Same as Step 2b — present Round N review, wait for user input.

### Step N.3: Implement Round N Fixes

Same process as Step 3, including NotebookLM consultation for CRITICAL/MAJOR fixes. Typical Round N fixes for methodology papers:
- Tighten assumptions (replace "mild regularity conditions" with formal statements)
- Add Monte Carlo SEs to key simulation cells
- Add or strengthen the limitations paragraph (model misspecification, computational cost, extension to clustered data)
- Formalize informal arguments (e.g., "intuitively, pseudo-observations are approximately unbiased" → cite Andersen et al.)
- Ensure every theorem's proof in Supplement matches notation in main text
- Confirm all claimed references exist in `.bib` and are cited in the right location

### Step N.4: Recompile Round N

```bash
cd paper
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode main.tex
BIBINPUTS=..:$BIBINPUTS bibtex main
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode main.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode main.tex
cp main.pdf main_round${N}.pdf
```

### Step 8: Format Check

After the final recompilation, run a format compliance check calibrated to **journal** submission (not conference):

```bash
# 1. Page count (biostatistics journals: typically 25–35 pages double-spaced;
#    check venue-specific guidelines)
PAGES=$(pdfinfo paper/main.pdf | grep Pages | awk '{print $2}')
echo "Pages: $PAGES"

# 2. Overfull hbox warnings
OVERFULL=$(grep -c "Overfull" paper/main.log 2>/dev/null || echo 0)
echo "Overfull hbox warnings: $OVERFULL"
grep "Overfull" paper/main.log 2>/dev/null | head -10

# 3. Underfull hbox
UNDERFULL=$(grep -c "Underfull" paper/main.log 2>/dev/null || echo 0)
echo "Underfull hbox warnings: $UNDERFULL"

# 4. Undefined references and citations
grep -c "LaTeX Warning: Reference.*undefined" paper/main.log 2>/dev/null || echo "0 undefined refs"
grep -c "Citation.*undefined" paper/main.log 2>/dev/null || echo "0 undefined citations"

# 5. Figure/table ordering (must appear in order of first citation)
grep -n "\\\\label{fig:" paper/sections/*.tex | head -20
grep -n "\\\\label{tab:" paper/sections/*.tex | head -20
```

**Auto-fix patterns:**

| Issue | Fix |
|-------|-----|
| Overfull hbox in equation | Wrap in `\resizebox` or split with `\split`/`aligned` |
| Overfull hbox in table | Reduce font (`\small`/`\footnotesize`) or use `\resizebox{\linewidth}{!}{...}` |
| Overfull hbox in text | Rephrase sentence or add `\allowbreak` / `\-` hints |
| Over page limit | Move proofs and extended simulation tables to Supplement |
| Underfull hbox (loose) | Rephrase for better line filling or add `\looseness=-1` |
| Figures out of order | Reorder `\begin{figure}` environments to match first citation order |

If any overfull hbox > 10pt is found, fix it and recompile before documenting.

### Step 9: Document Results

Create `PAPER_IMPROVEMENT_LOG.md` in the paper directory:

```markdown
# Paper Improvement Log

## Configuration
- **Reviewer backend:** codex | subagent
- **NotebookLM:** available | unavailable

## Score Progression

| Round | Score | Verdict | Key Changes |
|-------|-------|---------|-------------|
| Round 0 (original) | X/10 | No/Almost/Yes | Baseline |
| Round 1 | Y/10 | No/Almost/Yes | [summary of fixes] |
| Round 2 | Z/10 | No/Almost/Yes | [summary of fixes] |

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

## PDFs
- `main_round0_original.pdf` — Original generated paper
- `main_round1.pdf` — After Round 1 fixes
- `main_round{k}.pdf` — After Round k fixes, for k = 2 to MAX_ROUNDS
- `main_round{MAX_ROUNDS}.pdf` — Final version
```

### Step 10: Summary

Report to user:
- Score progression table
- Statistical Rigor Checklist delta (which items moved from "Needs work" to "OK")
- Number of CRITICAL/MAJOR/MINOR issues fixed per round
- Final page count
- Remaining issues (if any) — especially any open checklist items

### Feishu Notification (if configured)

After each round's review AND at final completion, check `~/.claude/feishu.json`:
- **After each round**: Send `review_scored` — "Round N: X/10 — [key changes]"
- **After final round**: Send `pipeline_done` — score progression table + final page count
- If config absent or mode `"off"`: skip entirely (no-op)

## Output

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

## Key Rules

- **Large file handling**: If the Write tool fails due to file size, immediately retry using Bash (`cat << 'EOF' > file`) to write in chunks. Do NOT ask the user for permission — just do it silently.
- **Compile command**: Use the project XeLaTeX 3-pass sequence (`xelatex → bibtex → xelatex → xelatex`) with `TEXINPUTS=../Preambles:$TEXINPUTS`, not `latexmk`. This project uses XeLaTeX, not pdfLaTeX.
- **Preserve all PDF versions** — user needs to compare progression
- **Save FULL raw review text** — do not summarize or truncate reviewer responses (whether from Codex or subagent)
- **Use `mcp__codex__codex-reply`** for Round 2 when using Codex backend to maintain conversation context. When using subagent backend, embed Round 1 review in the Round 2 prompt instead.
- **Always recompile after fixes** — verify 0 errors before proceeding
- **Do not fabricate simulation results** — if a simulation gap is identified, note it as a limitation or add a DGP description; never invent numerical outcomes
- **Respect the paper's claims** — soften overclaims, do not add unsupported new claims
- **Global consistency** — when renaming notation or softening claims, check ALL files (abstract, intro, methods, theory, simulation, application, discussion, tables, figure captions, Supplement)
- **Assumption numbers must align** — if Supplement proofs reference "Assumption A3", that label must match the main text exactly
- **NotebookLM before fixes** — query both notebooks before implementing CRITICAL/MAJOR fixes. If unavailable, proceed without and log the skip. Never let notebook unavailability block the loop.
- **Log the reviewer backend** — record which backend was used (`codex` or `subagent`) in both `PAPER_IMPROVEMENT_STATE.json` and `PAPER_IMPROVEMENT_LOG.md`

## Typical Score Progression

Calibrated to a 30-page Biometrics-style methodology paper (recurrent events + pseudo-observations):

| Round | Score | Key Improvements |
|-------|-------|-----------------|
| Round 0 | 4/10 | Estimand informal, regularity conditions absent, simulation censoring unspecified, no coverage reported |
| Round 1 | 6/10 | Formal estimand, Assumptions 1–4 added, censoring DGP specified, coverage column added, notation conflict fixed |
| Round 2 | 7/10 | Monte Carlo SEs added, limitations strengthened, real data sensitivity analysis added, all captions self-contained |

**+3 points in 2 rounds** is typical for a technically correct but loosely written first draft. A score of 7/10 ("minor revision" at Biometrics) is a realistic target for a well-structured methods paper after this loop.
