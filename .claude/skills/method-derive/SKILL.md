---
name: method-derive
description: 'Derive new statistical estimators end-to-end: freeze the estimand, write the full mathematical derivation, run an iterative GPT-5.4 review loop until the math is sound, implement the estimator in R, verify it via Monte Carlo pilot (bias ≈ 0, SE ratio ≈ 1, nominal coverage), and generate SLURM job files for a full simulation study. Use whenever the user says "derive this estimator", "show this is unbiased", "prove the variance formula", "design a simulation for this method", "write a simulation script", "check my math on this", or needs to go from a theoretical method idea to working, verified R simulation code. Also triggers on: identification arguments, pseudo-observation regularity, IPW validity, sandwich/jackknife variance, asymptotic normality, DGP design, Monte Carlo performance checks, or any request that combines statistical theory with simulation verification.'
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch, Agent, mcp__codex__codex, mcp__codex__codex-reply, mcp__notebooklm__notebook_query
---

# Method Derive: Estimand-Anchored Derivation and Simulation Verification

Derive and verify: **$ARGUMENTS**

## Overview

Use this skill when a new statistical method needs to be mathematically grounded and computationally verified. The goal is not a bloated theoretical treatise. The goal is a **clean estimand anchor → sound derivation → verified R simulation → SLURM-ready job files** package, all internally consistent.

Three principles govern this skill:

1. **The estimand is immutable.** Freeze it in Phase 0 and carry it verbatim through every revision.
2. **The smallest sufficient assumption set wins.** State only what the derivation requires — no more.
3. **Theory and simulation must cohere.** If the math claims bias = 0, the DGP must test that exact claim under the exact model.

```
Input (ESTIMAND + proposed METHOD)
  -> Phase 0 (Claude):      Freeze Estimand Anchor
  -> Phase 1 (Claude):      Full mathematical derivation
  -> Phase 2 (Codex/GPT):   Statistical math review (Round 1)
  -> Phase 3 (Claude):      Anchor check + correctness check -> revise
  -> Phase 4 (Codex):       Re-evaluate revised derivation (same thread)
  -> [Repeat Phase 3-4 until OVERALL SCORE >= 9 or MAX_ROUNDS reached]
  -> Phase 5 (Claude):      Write R simulation script
  -> Phase 6 (domain-reviewer agent): Code and design review
  -> Phase 7 (Claude + Bash): Pilot run + Monte Carlo verification
  -> Phase 8 (Claude):      SLURM job files
  -> Phase 9:               Final report and summary
```

## Constants

- **REVIEWER_MODEL = `gpt-5.4`**
- **MAX_ROUNDS = 5**
- **SCORE_THRESHOLD = 9**
- **OUTPUT_DIR = `derive-logs/`**
- **PILOT_REPS = 500** — replications for the pilot run
- **PILOT_N = 200** — sample size for the pilot run
- **BIAS_THRESHOLD = 0.05** — max acceptable |relative bias| = |bias| / |truth|
- **SE_RATIO_RANGE = [0.90, 1.10]** — acceptable mean(SE_hat) / SD(theta_hat)
- **COVERAGE_NOMINAL = 0.95**
- **COVERAGE_PILOT_RANGE = [0.91, 0.99]** — Monte Carlo tolerance at B = 500
- **REVIEWER_BACKEND = `auto`** — Which reviewer to use for the math review loop (Phase 2 & Phase 4). Values: `auto` (detect Codex MCP at startup, fall back to Claude subagent), `codex` (force Codex MCP), `subagent` (force Claude subagent). See `.claude/rules/codex-fallback-protocol.md`. Phase 6's `domain-reviewer` agent is unaffected.
- **USER_FOCUS = `""`** — Free-text user directive that biases the math reviewer's attention (e.g., "scrutinize the sandwich variance derivation most heavily"). When non-empty, injected verbatim into **every** round's reviewer prompt (Phase 2 Round 1 through Phase 4 Round MAX_ROUNDS) so the user's focus persists across the full loop. Set via arguments (see parsing below) or omit for default reviewer behavior.

> Override constants via argument if needed, e.g. `-- pilot_n: 100, pilot_reps: 200, reviewer: subagent, focus: "scrutinize the sandwich variance derivation most heavily"`.

### Argument Parsing for USER_FOCUS

`$ARGUMENTS` may contain a mix of (a) the estimand/method specification, (b) recognized parameters (`pilot_n:`, `pilot_reps:`, `reviewer:`, `focus:`, etc.), and (c) free-text directives. Parse as follows:

1. Extract the estimand/method specification (the `ESTIMAND: … | METHOD: …` block or equivalent).
2. Extract recognized parameters by their `key:` prefix.
3. **Anything left over — including any free-text natural-language directive (e.g., "focus on the variance step") — is treated as `USER_FOCUS`.** Concatenate and trim whitespace.
4. If the user explicitly provides `focus: "..."`, that value takes precedence over any free-text leftovers.
5. Log the parsed `USER_FOCUS` value (or `"(none)"`) to `derive-logs/score-history.md` under a "Configuration" block so the user can verify it was captured.

**Reviewer fallback & NotebookLM:** The math review loop (Phase 2 & Phase 4) respects `REVIEWER_BACKEND`. Under `auto` (default), probe Codex MCP once at startup; if unavailable, fall back to a Claude subagent reviewer with `model: "opus"` (explicit — never omit). Log `"Reviewer backend: codex"` or `"Reviewer backend: subagent (Codex MCP unavailable)"` to `derive-logs/score-history.md`. Before implementing CRITICAL/MAJOR changes from reviews, consult NotebookLM. Phase 6's `domain-reviewer` agent is unaffected by `REVIEWER_BACKEND`. See `.claude/rules/codex-fallback-protocol.md` for full protocol.

## State Persistence (Checkpoint Recovery)

Persist to `derive-logs/DERIVE_STATE.json` after each phase boundary:

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

| Field | Values |
|-------|--------|
| `phase` | `"anchor"` / `"derivation"` / `"math-review"` / `"revision"` / `"simulation"` / `"code-review"` / `"pilot"` / `"slurm"` / `"done"` |
| `round` | 0–MAX_ROUNDS |
| `threadId` | Codex: reviewer thread ID for `codex-reply` continuity. Subagent: `null`; Round N-1 review text is stored in `derive-logs/round-N-1-math-review.md` for Round N context. |
| `reviewer_backend` | `"codex"` / `"subagent"` — records which backend was used. Logged alongside every round. |
| `user_focus` | Verbatim `USER_FOCUS` string, or `""` if none. Persisted so checkpoint recovery re-injects the same focus into subsequent rounds. |
| `last_score` | Most recent overall score |
| `last_verdict` | `CORRECT` / `REVISE` / `REDERIVE` |
| `status` | `"in_progress"` / `"completed"` |

**Checkpoint recovery:** On startup, check for `derive-logs/DERIVE_STATE.json`.
- Absent, `"completed"`, or timestamp > 24 hours old → **fresh start** (delete stale file if present).
- Present and `"in_progress"` within 24 hours → **resume**: read existing round files, recover `threadId`, log `"Checkpoint found. Resuming after phase: {phase}, round: {round}."` then jump to the next phase.

## Output Structure

```
derive-logs/
├── DERIVE_STATE.json
├── round-0-derivation.md
├── round-1-math-review.md
├── round-1-revision.md
├── ...
├── MATH_REVIEW_SUMMARY.md
├── FINAL_DERIVATION.md
├── simulation.R
├── pilot_results.md
├── run_full.slurm
├── run_instructions.md
├── DERIVATION_REPORT.md
└── score-history.md
```

Every `round-N-revision.md` must contain a **full revised derivation**, not just incremental diffs.

---

## Workflow

### Phase 0: Freeze the Estimand Anchor

Before any derivation, extract and lock the immutable core. Copy this block verbatim into every derivation and revision round.

Write:

- **Target estimand**: The quantity being estimated, defined precisely with notation (e.g., $\theta = E[\hat{S}(t \mid X)]$).
- **Model**: The probability model and data-generating structure assumed (distributions, hazard form, frailty, correlation structure, censoring mechanism).
- **Identifying assumptions**: Every condition required to go from observed data to the estimand (independent censoring, positivity, MAR vs. MCAR, no unmeasured confounding, etc.).
- **Non-goals**: Properties explicitly *not* claimed (efficiency, robustness to MNAR, finite-sample exactness, etc.).
- **Success condition**: What a valid derivation looks like, and what a passing simulation looks like.

If reviewer feedback would change the estimand being derived, flag that as **drift** and push back.

**Checkpoint:** Write `DERIVE_STATE.json` with `"phase": "anchor", "round": 0, "status": "in_progress"`.

---

### Phase 1: Mathematical Derivation

Write the full derivation in `derive-logs/round-0-derivation.md`.

#### 1.1 Estimator Definition
- Define the estimator explicitly: formula, algorithm, or recursive rule.
- State which quantities are observed vs. estimated from data.
- Identify any plug-in components (e.g., estimated survival function $\hat{S}$, estimated propensity score $\hat{\pi}$).

#### 1.2 Identification Argument
- Show the estimand is identified from the observed-data distribution under the stated assumptions.
- For pseudo-observation-based methods: verify or cite von Mises differentiability conditions (Graw et al., 2009).
- For IPW estimators: show the re-weighting argument and verify positivity.
- For landmark or conditional methods: define the conditioning event and verify it is well-defined.

#### 1.3 Unbiasedness or Consistency
- Derive $E[\hat{\theta}] = \theta$ under the model, showing each expectation step.
- For large-sample consistency: state the convergence argument (LLN, M-estimation, U-statistic theory).
- Flag explicitly if only asymptotic unbiasedness holds (finite-sample bias exists).

#### 1.4 Variance and Standard Error
- Derive $\text{Var}(\hat{\theta})$.
- Show how this variance is estimated from data (sandwich estimator, jackknife, bootstrap).
- Verify the SE estimator is consistent. Note if the variance depends on hard-to-estimate quantities.
- Account for data structure: clustering, recurrence, censoring, plug-in components.

#### 1.5 Asymptotic Distribution (if claimed)
- State the asymptotic normality result and its regularity conditions.
- Cite the relevant theorem (CLT, functional delta method, M-estimation theory).
- Note which regularity conditions are verifiable in simulation vs. assumed.

Use this structure in `round-0-derivation.md`:

```markdown
# Derivation: [Estimand Name]

## Estimand Anchor
[Copy verbatim from Phase 0]

## Estimator Definition
[Formal definition]

## Identification Argument
[...]

## Unbiasedness / Consistency
[Show E[theta_hat] = theta step by step]

## Variance and SE
[Derive Var(theta_hat) and show how SE_hat is computed]

## Asymptotic Distribution
[State claim, cite theorem, note regularity conditions]

## Open Questions / Provisional Steps
[List any steps that rely on unverified assumptions]
```

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "derivation"`.

---

### Phase 2: External Math Review (Round 1)

**Branch by `REVIEWER_BACKEND`.** Both branches use the same `REVIEWER_PROMPT` (defined below, with the optional `## User Focus (priority)` block prepended when `USER_FOCUS` is non-empty).

#### If backend = `codex`

Send the full derivation to GPT-5.4:

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

#### If backend = `subagent`

Spawn a Claude subagent with the **same persona and prompt** as the Codex branch. `model: "opus"` is REQUIRED — never omit it (the `Agent` tool inherits Sonnet from the parent otherwise):

```
Agent:
  description: "method-derive math review round 1"
  model: "opus"
  prompt: |
    [REVIEWER_PROMPT below — same text as Codex branch]
```

For `subagent` backend, `threadId = null`; Round N (N ≥ 2) will re-read this file for context.

#### USER_FOCUS injection (shared by both backends)

If `USER_FOCUS` is non-empty, prepend a `## User Focus (priority)` block immediately **before** the `=== DERIVATION ===` line inside REVIEWER_PROMPT:

```
## User Focus (priority)
[USER_FOCUS verbatim — omit this entire block if USER_FOCUS is empty]

Treat this focus as the highest-priority review lens for this round. Score the derivation primarily on how well it satisfies this focus (weight the 7-dimension scoring accordingly), while still flagging any CRITICAL mathematical errors you observe in other dimensions.
```

If `USER_FOCUS` is empty, omit the entire block — the prompt is byte-identical to the pre-change version.

#### REVIEWER_PROMPT (shared by both backends)

The prompt body — persona, 7-dimension scoring rubric, verdict rules, output format — is unchanged from prior versions. It is the text that already appears above in the Codex branch after the `prompt: |` line.

**CRITICAL (Codex branch only): Save the `threadId`** from the Codex call for all later rounds. For `subagent` backend, skip this — Round N ≥ 2 re-reads `derive-logs/round-N-1-math-review.md` instead.

Save the full raw response from whichever backend was used to `derive-logs/round-1-math-review.md` inside a `<details>` block.

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "math-review", "round": 1, "threadId": "<saved-or-null>", "reviewer_backend": "<codex|subagent>", "user_focus": "<USER_FOCUS verbatim>", "last_score": <parsed>, "last_verdict": "<parsed>"`.

---

### Phase 3: Parse Feedback and Revise

#### Step 3.1: Parse the Review

Extract all 7 dimension scores, overall score, verdict, hidden assumptions, drift warning, and action items ranked by priority.

Update `derive-logs/score-history.md`:

```markdown
# Score Evolution

| Round | Estimand Fidelity | Assumption Sufficiency | Math Correctness | ID Completeness | Variance/SE | Sim Coherence | Regularity | Overall | Verdict |
|-------|-------------------|------------------------|------------------|-----------------|-------------|---------------|------------|---------|---------|
| 1     | X | X | X | X | X | X | X | X | REVISE |
```

**STOP CONDITION**: If overall score >= SCORE_THRESHOLD, verdict is CORRECT, no hidden assumptions remain, and no drift warning — skip to Phase 5.

#### Step 3.2: Revise with an Anchor Check and a Correctness Check

Before changing anything:

1. Copy the **Estimand Anchor verbatim**.
2. Write an **Anchor Check**:
   - What is the target estimand?
   - Does the revision still target it exactly?
   - Which reviewer suggestions would change the estimand (drift)?
3. Write a **Correctness Check**:
   - Which errors or gaps are confirmed valid?
   - Which reviewer suggestions are unnecessary additions or wrong?
   - Does fixing the identified errors require restructuring the argument or just clarifying steps?

Then process reviewer feedback:

- **Valid math error**: correct it, show the corrected step explicitly.
- **Missing assumption**: add it with a justification for why it is necessary.
- **Debatable step**: revise and explain reasoning with a reference or worked argument.
- **Wrong or over-cautious**: push back with the corrected argument.

Bias revisions toward: a tighter assumption set, cleaner expectation algebra, and an SE formula that accounts for all sources of variance.

Save to `derive-logs/round-N-revision.md`:

```markdown
# Round N Revision

## Estimand Anchor
[Copy verbatim]

## Anchor Check
- Estimand being derived: [state it]
- Revision preserves this: [yes / modified — explain]
- Suggestions rejected as drift: [list]

## Correctness Check
- Errors confirmed and fixed: [list with corrected steps]
- Reviewer feedback rejected: [list with reasoning]

## Changes Made
### 1. [Section changed]
- Reviewer said: ...
- Action: ...
- Corrected step: [show equation or argument]

## Revised Derivation
[Full derivation from Estimand Anchor through Asymptotic Distribution]
```

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "revision", "round": N`.

---

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

Save the response from whichever backend was used to `derive-logs/round-N-math-review.md`.

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "math-review", "round": N, "reviewer_backend": "<codex|subagent>", "user_focus": "<USER_FOCUS verbatim>"`.

Return to Phase 3 until overall >= SCORE_THRESHOLD and verdict is CORRECT, or MAX_ROUNDS reached.

---

### Phase 5: R Simulation Script

Once the derivation is locked, write `derive-logs/simulation.R`.

The script must contain four sections, following project R conventions:

#### 5.1 Header and Parameters
```r
# simulation.R — [Estimand Name]
# Last Updated: YYYY-MM-DD
# set.seed at top; parameterize n, n_reps, scenarios

set.seed(YYYYMMDD)
RNGkind("L'Ecuyer-CMRG")  # required for parallel reproducibility
```

Declare all scenario parameters at the top (n, censoring rate, effect sizes, etc.). Use `here::here()` for all file paths.

#### 5.2 Data-Generating Process (DGP)
- Instantiates the exact model and assumptions from the Estimand Anchor.
- DGP function parameters match the scenario table; every assumption in the derivation maps to a line of code.

#### 5.3 Estimator and SE Implementation
- Directly implements the estimator formula from `FINAL_DERIVATION.md`.
- Computes both the point estimate and the SE estimate using the variance formula.
- Variable names mirror mathematical notation where possible (e.g., `theta_hat`, `se_hat`).

#### 5.4 Performance Metrics (per replication, summarized across B)
Compute and output for each scenario:

| Metric | Formula | Target |
|--------|---------|--------|
| Bias | mean(theta_hat) - theta_true | ≈ 0 |
| Relative Bias (%) | 100 × bias / \|theta_true\| | < BIAS_THRESHOLD |
| Empirical SE | sd(theta_hat) | — |
| Mean SE Estimate | mean(se_hat) | ≈ Empirical SE |
| SE Ratio | mean(se_hat) / sd(theta_hat) | in SE_RATIO_RANGE |
| RMSE | sqrt(mean((theta_hat - theta_true)²)) | — |
| Coverage (95% CI) | mean(\|theta_hat - theta_true\| / se_hat ≤ z_{0.025}) | in COVERAGE_PILOT_RANGE |

Add other metrics as appropriate (type I error rate, power, convergence frequency).

#### 5.5 Scenarios
Cover:
- At least one scenario under the exact assumed model (verify correct case).
- At least one scenario with a key assumption violated or stressed (stress test).
- Varying n (small, moderate, large) to assess convergence rate.

Write results as a CSV and print a formatted summary table. Use `parallel::mclapply` for replication loop.

**Note**: The `formula-derivation` and `proof-writer` skills can be invoked within this phase if a specific formula or sub-proof needs to be worked out in detail before coding.

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "simulation"`.

---

### Phase 6: Code Review (domain-reviewer agent)

Invoke the `domain-reviewer` agent via the Agent tool on `derive-logs/simulation.R`.

The agent reviews through its 5 lenses. For this script the highest-priority lenses are:

- **Lens 1 (Statistical Correctness)**: Does the estimator code match the derivation? Is the SE computation correct?
- **Lens 2 (Simulation Design)**: Does the DGP instantiate the model assumptions? Are seeds correct for parallel RNG? Are scenarios adequate?

Apply all CRITICAL and MAJOR findings before proceeding to Phase 7. Save the review report to `quality_reports/simulation_code_review_[date].md`.

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "code-review"`.

---

### Phase 7: Pilot Run and Verification

Run the pilot using PILOT_N and PILOT_REPS. Either set a `--pilot` flag in the script or temporarily set parameters at the top, then restore.

```bash
Rscript derive-logs/simulation.R
```

Capture stdout/stderr. Save results to `derive-logs/pilot_results.md`.

#### Verification Criteria

| Metric | Pass Criterion |
|--------|---------------|
| Relative Bias | < BIAS_THRESHOLD (5%) in every scenario |
| SE Ratio | in SE_RATIO_RANGE [0.90, 1.10] in every scenario |
| Coverage (95% CI) | in COVERAGE_PILOT_RANGE [0.91, 0.99] in every scenario |
| Runtime | Script completes without errors or warnings |

**If any criterion fails**, diagnose before acting:

- **Code bug** (wrong formula, indexing error, wrong n): fix `simulation.R` and re-run pilot. Max 3 rounds.
- **Theoretical issue** (bias structurally non-zero, SE formula inconsistent): return to Phase 3 — the derivation needs correction, not just the code.
- After 3 failed pilot rounds, surface the failure to the user with a diagnosis before continuing.

Save `derive-logs/pilot_results.md`:

```markdown
# Pilot Results
**Date**: YYYY-MM-DD
**Pilot N**: [n], **Pilot Reps**: [B]

## Results by Scenario

| Scenario | Bias | Rel. Bias (%) | Emp. SE | Mean SE | SE Ratio | RMSE | Coverage | Pass? |
|----------|------|---------------|---------|---------|----------|------|----------|-------|

## Verification Verdict: PASS / FAIL

## Issues Found
[If any]

## Diagnosis
[Code bug / Derivation error / Edge case / None]
```

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "pilot"`.

---

### Phase 8: SLURM Job Files

Generate `derive-logs/run_full.slurm` for UNC Longleaf. Base array size, cores, memory, and wall time on the pilot timing.

```bash
#!/bin/bash
#SBATCH --job-name=sim_[estimand_shortname]
#SBATCH --array=1-[N_SCENARIOS]
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=[CORES]
#SBATCH --mem=[MEM]GB
#SBATCH --time=[HH:MM:SS]
#SBATCH --output=logs/slurm_%A_%a.out
#SBATCH --error=logs/slurm_%A_%a.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=[user@email.edu]

module load r/4.4.0
mkdir -p logs results

Rscript derive-logs/simulation.R --scenario $SLURM_ARRAY_TASK_ID
```

Also write `derive-logs/run_instructions.md`:

```markdown
# Run Instructions

## Submit
sbatch derive-logs/run_full.slurm

## Monitor
squeue -u $USER
sacct -j [JOBID] --format=JobID,State,ExitCode,Elapsed

## Collect Results
# [describe how to aggregate output CSVs after all array tasks finish]

## Analyze Results
/analyze-results derive-logs/results/
```

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "slurm"`.

---

### Phase 9: Final Report

#### 9.1 `derive-logs/MATH_REVIEW_SUMMARY.md`

High-level round-by-round record: what was wrong each round, what changed, what was resolved.

Include: Estimand Anchor (verbatim), round-by-round resolution table, final status (estimand preserved / assumption set minimal / derivation sound).

#### 9.2 `derive-logs/FINAL_DERIVATION.md`

Clean final derivation only — no review chatter, no revision history.

If the final verdict is not CORRECT, still write the best current version and flag remaining concerns.

#### 9.3 `derive-logs/DERIVATION_REPORT.md`

Full report: score evolution table, round-by-round change log, pushback/drift log, pilot verification summary, remaining weaknesses (honest), raw reviewer responses in `<details>` blocks, next steps.

#### 9.4 Present Summary

```
Method derivation complete after N rounds.

Final score: X/10 (Verdict: CORRECT / REVISE / REDERIVE)

Estimand anchor:   [preserved / drift corrected / concern remains]
Assumption set:    [minimal / one added / concern remains]
Pilot verification: [PASS / FAIL]

Key corrections:
- [Correction 1]
- [Correction 2]

Remaining concerns:
- [If any]

Files:
  derive-logs/FINAL_DERIVATION.md
  derive-logs/simulation.R
  derive-logs/pilot_results.md
  derive-logs/run_full.slurm
  derive-logs/DERIVATION_REPORT.md

Suggested next step: /run-experiment
```

**Checkpoint:** Update `DERIVE_STATE.json` with `"phase": "done", "status": "completed"`.

---

## Key Rules

- **Large file handling**: If Write fails due to size, retry immediately with `Bash` (`cat << 'EOF' > file`). Do this silently.
- **Estimand first, every round.** Carry the anchor verbatim — never paraphrase it.
- **Show every step.** "It follows that..." is not acceptable — write the algebra.
- **Minimal assumptions win.** Do not add a condition that is not needed by any derivation step.
- **Theory and code must match.** Variable names in R should mirror mathematical notation.
- **Pilot before SLURM.** Never generate a SLURM submission without a passing pilot.
- **Distinguish code bugs from theory errors.** A bias failure in the pilot is not automatically a theory problem — diagnose carefully.
- **ALWAYS use `config: {"model_reasoning_effort": "xhigh"}`** for all Codex calls.
- **Subagent reviewer requires `model: "opus"`** — the `Agent` tool inherits Sonnet from the parent if `model` is omitted. Always pass `model: "opus"` explicitly for every `Agent` call used as a reviewer fallback in Phase 2 and Phase 4.
- **Log the reviewer backend** — record which backend was used (`codex` or `subagent`) in both `DERIVE_STATE.json` and `derive-logs/score-history.md` for every round.
- **USER_FOCUS persists across rounds and compacts.** It is re-injected into the reviewer prompt in every Phase 2 and Phase 4 call, and it is persisted in `DERIVE_STATE.json` so checkpoint recovery re-injects the same focus.
- **Codex branch: save `threadId` from Phase 2** and use `mcp__codex__codex-reply` for all subsequent rounds. **Subagent branch: `threadId = null`**; Round N ≥ 2 re-reads `derive-logs/round-N-1-math-review.md` for prior context instead.
- **R conventions**: `set.seed(YYYYMMDD)`, `RNGkind("L'Ecuyer-CMRG")` for parallel, `here::here()` for all paths, Okabe-Ito palette for figures, 300 DPI white-background PNG/PDF outputs.
- **Do not fabricate results.** Pilot results are real; describe only what was actually run.

---

## Composing with Other Skills

This skill bridges theory and full-scale simulation:

```
/formula-derivation "scattered notes"    -> coherent derivation structure (single-pass, no code)
/proof-writer "specific claim"           -> rigorous proof of one theorem (single-pass, no code)

/method-derive "ESTIMAND: ... | METHOD: ..."   <- you are here
  Outputs: FINAL_DERIVATION.md, simulation.R, pilot_results.md, run_full.slurm

/run-experiment derive-logs/run_full.slurm    -> submit and monitor the full SLURM run
/analyze-results derive-logs/results/         -> summarize Monte Carlo results
/paper-write methods                          -> integrate FINAL_DERIVATION.md into manuscript
```

Typical flow:

1. `/formula-derivation` or `/proof-writer` can be called *within* Phase 1 or 5 for a specific sub-step that needs careful organization or proof.
2. `/method-derive` locks the theory and produces verified simulation code.
3. `/run-experiment` submits and monitors the full SLURM array.
4. `/analyze-results` summarizes bias/coverage tables across all scenarios.
5. `/paper-write` drafts the methods section using `FINAL_DERIVATION.md` as source.
