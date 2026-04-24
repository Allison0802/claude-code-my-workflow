# Phase 2 — Classification, novelty-check dispatch, lens-plan confirmation

**Preconditions (from Phase 1):** state.json initialized, notebooks resolved.

**Postconditions:**
- `detected_type` set to one of the 5 enum values; `classification_source` set.
- `headline_claim` and `novelty_claims[]` populated.
- `novelty_check` either completed, running in background, or `skipped`.
- `lens_plan` is a 9-element array, user-confirmed.

Phase 2 has three sub-phases that overlap:
- **2a:** One-shot Reviewer classification spawn.
- **2b:** Background novelty-check dispatch (non-blocking).
- **2c:** Build lens plan from the weight matrix, prompt user.

---

## Step 2.1 — Load Reviewer prompt template

Read `.claude/skills/paper-stress-test/agents/reviewer.md`; store as `REVIEWER_PROMPT`.

---

## Step 2.2 — One-shot Reviewer classification spawn

Single synchronous `Agent` call. No `agent_id` persisted. Phase 3 respawns fresh Reviewers per round.

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
    .replace("{{REQUIRED_OUTPUT}}", "classification + headline + novelty claims")
    .replace("{{MODERATOR_STEER_BLOCK}}", "")
    .replace("{{TRANSCRIPT_BLOCK}}", "(no transcript yet — this is the pre-debate classification pass)")
    + CLASSIFICATION_INSTRUCTIONS
)
```

`CLASSIFICATION_INSTRUCTIONS` is:

```
## This spawn: paper classification (one-shot, synchronous)

Query the disposable notebook (ID: ${DISPOSABLE}) three times via mcp__notebooklm__notebook_query:

1. "Classify this paper as exactly one of: predictive-ML, new-estimator, applied-empirical,
   causal-inference, review-survey. Return the label plus one sentence of justification."
2. "State the paper's headline contribution in one sentence, quoting from abstract or conclusion."
3. "List the 3 to 5 most important technical claims the paper positions as novel.
   Format as a numbered list; be specific; avoid generic phrasing like 'novel approach'."

Return all three answers concatenated, one per paragraph, with clear headings. Do NOT query
anything else. You will NOT be called again in this spawn.
```

If `type_override` was specified: the prompt instructs the subagent to skip query 1 and use the override; run only queries 2 and 3.

---

## Step 2.3 — Parse Reviewer's classification response

Use **`parsing/transcript-patterns.md` §6 (Classification triple-query response)**. Extract `detected_type`, `headline_claim`, `novelty_claims[]`. Reparse once on mismatch per the Reparse protocol; otherwise fall through to Step 2.4.

---

## Step 2.4 — Validate `detected_type` (no silent defaults)

Must match `["predictive-ML", "new-estimator", "applied-empirical", "causal-inference", "review-survey"]` exactly.

**Never silently default.** The weight matrix is asymmetric; a misrouted paper skips the wrong lenses.

1. Enum-match exact → accept, set `classification_source = "reviewer"`.
2. Ambiguous or off-enum → reprompt once:

   > Your classification must be EXACTLY one label from: predictive-ML, new-estimator, applied-empirical, causal-inference, review-survey. If the paper spans two types, pick the one most central to the headline contribution, and include your reasoning for the tradeoff.

3. If the second attempt is still ambiguous → hand to user:

   > I couldn't confidently classify this paper. The Reviewer's responses were:
   > Attempt 1: `<response>`
   > Attempt 2: `<response>`
   > Please pick one: [1] predictive-ML [2] new-estimator [3] applied-empirical [4] causal-inference [5] review-survey

4. Record choice; if user picked, set `classification_source = "user_override"`.

5. If the Reviewer mentioned ambiguity, surface it at plan confirmation (Step 2.10) with:

   > ⚠️ Classification was ambiguous between `<A>` and `<B>`. Plan uses `<detected_type>`. Change via `[T]` in edit mode.

---

## Step 2.5 — Fire novelty-check as a background Agent

If `invocation.skip_novelty == true`: set `novelty_check.status = "skipped"` and skip 2.5–2.8.

Otherwise, dispatch:

```
Agent(
  description: "novelty-check runner for paper-stress-test",
  subagent_type: "general-purpose",
  model: "sonnet",
  run_in_background: true,
  prompt: "Invoke the `novelty-check` skill with the following input, then return the skill's complete output markdown report. Do nothing else.\n\n---\n\nStress-test context — verify whether this paper's headline claim is genuinely novel.\n\nPaper: <authors> (<year>). <title>\n\nHeadline claim: <headline>\n\nCore novelty claims:\n- <claim 1>\n- <claim 2>\n...\n\nReturn the standard novelty-check Phase D report verbatim."
)
```

Why not `Skill` foreground: `Skill` blocks with no timeout. Background Agent can be abandoned on wall-clock.

Record:
```json
"novelty_check": {
  "status": "running",
  "runner_agent_id": "<returned id>",
  "started_at": "<ISO now>",
  "completed_at": null
}
```

Call returns immediately. Moderator proceeds to Step 2.9 while runner works in background.

---

## Step 2.6 — Collect novelty result (lazy, at point of use)

Do NOT poll. Check at two fixed points:

1. Start of Phase 3 (before first group dispatch).
2. Start of Lens 7 (before building the novelty seed).

When the runner's notification arrives, parse per **`parsing/transcript-patterns.md` §7**. Populate `novelty_check.status = "completed"`, plus `overall_score`, `recommendation`, `key_differentiator`, `closest_prior_work[]`, `raw_report_md`.

---

## Step 2.7 — Enforce the timeout

At each check point, `elapsed = now - novelty_check.started_at`. Constants: `NOVELTY_CHECK_TIMEOUT_SECONDS = 300`.

- Completed → use regardless of elapsed.
- Not completed and `elapsed > 300` → set `status = "failed"`, `completed_at = now`, `raw_report_md = null`. **Do NOT attempt to kill the runner.** Late output is ignored.
- Not completed and `elapsed ≤ 300` → status stays `"running"`. Lens 7 degrades per its runbook's degradation table.

---

## Step 2.8 — Handle runner failure

- Spawn errored → `status = "failed"`, error in `raw_report_md`.
- Completed but output malformed → `status = "failed"`, keep raw text in `raw_report_md`.

In all non-completed cases, Lens 7 runbook falls back to its degradation table.

---

## Step 2.9 — Build lens plan from weight matrix

**Lens metadata** (hard-coded):

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

**Weight matrix:**

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

**Weight → depth** given invocation depth `D`:
```
heavy  -> D
medium -> max(1, D-1)
light  -> 1
skip   -> 0
```

Build `lens_plan[]` as a 9-element array of `{lens_id, name, weight, depth}`. Skipped lenses are included with `depth: 0` so users see them during edit.

---

## Step 2.10 — Display plan and prompt

```
Paper-type-aware lens plan (depth=<D>, detected type=<type>)

 # | Lens               | Weight  | Queries | Action
 0 | data               | medium  |    1    | RUN
 1 | estimand           | heavy   |    2    | RUN
 ...
 8 | reproducibility    | medium  |    1    | RUN

Total active queries: ~<N> (Reviewer + Author × depth)
Concurrent novelty-check: <status>

Proceed? [Y/n/edit]
```

- `invocation.human_checkpoint == false` → auto-proceed as `Y`. Print `[checkpoint skipped — --no-checkpoint active]`.
- `Y` or empty → save plan to state.json, exit to Phase 3.
- `n` → abort cleanly. Delete disposable notebook. Do NOT save state.json.
- `edit` → Step 2.11.

---

## Step 2.11 — Edit loop

```
Edit what?
  [T] Change detected paper type (currently: <detected_type>)
  [0-8] Change weight of lens N
  [done] finish editing
```

**`T`:** show Reviewer's classification justification, prompt for new type from the 5-enum. Update `detected_type` and rebuild lens_plan via Step 2.9.

**`N` (0–8):** show current weight; prompt `[heavy | medium | light | skip]`. Update that lens's weight and recompute its depth per the mapping.

**`done`:** redisplay plan, return to Step 2.10's Y/n/edit prompt.

---

## Exit state

state.json now contains: `detected_type`, `classification_source`, `headline_claim`, `novelty_claims`, `novelty_check` block, `lens_plan`. Empty `transcript`, `moderator_assessments`, `compaction_history`, `lenses_completed` — all populated during Phase 3.

Return to SKILL.md, which loads `runbooks/phase-3-debate.md`.
