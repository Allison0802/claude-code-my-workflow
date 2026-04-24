# Phase 3 (Lens 7) — Positioning lens with Reviewer-owned thematic notebook

**Preconditions:** Group 2 is executing `phase-3-debate.md`'s per-lens loop for lens_id=7. Novelty-check result (or timeout/skip status) has been collected.

**Postconditions:**
- One closed lens_record for lens 7, shape matches `schema/state.schema.json#/definitions/lens_record`.
- All turn records conform to canonical `turn_record` (no legacy roles, no `turn` field, no proxies).
- **Invariant I-5 holds**: only Reviewer turns include the thematic notebook id in `notebooks_granted`; Author turns never do.

**This is NOT a straight port of the v1 Lens 7 path.** The v1 path had the moderator impersonate the Author via `moderator_notebook_proxy`. That path is deleted. In v2 the Reviewer owns the thematic-notebook query; the Author answers only from the paper (via the disposable notebook).

---

## Architecture

Lens 7 is the one lens where a subagent is granted two notebooks. The Reviewer needs external literature context to challenge the paper's positioning claims; the Author, as always, answers only from the paper.

```
Reviewer subagent (opus)      Author subagent (sonnet)
  ├─ notebooks_granted:         ├─ notebooks_granted:
  │    [disposable, thematic]   │    [disposable]   ← never thematic (I-5)
  │                             │
  ├─ queries thematic via       ├─ queries paper only
  │    mcp__notebooklm__        │
  │    notebook_query           │
  └─ reports in single turn     └─ reports in single turn
       content field                content field
```

The Moderator (the top-level skill context) — like any moderator in the 9-lens loop — is not a notebook holder. It only reads turns and writes an assessment.

**No `moderator_thematic_query` role. No `moderator_notebook_proxy` model. If any appears, gate G-3-notebook fails the run.**

### Moderator notebook-access prohibition (hard rule)

The moderator MUST NOT call `mcp__notebooklm__notebook_query` on the thematic notebook. Not even once. Not even "just to sanity-check the Reviewer's finding." Not even to synthesize multiple thematic findings across lenses.

The reasons, in order of importance:

1. **The query informs the question.** The Reviewer needs to run the query *themselves* so that the adversarial question is driven by what the Reviewer found — not rubber-stamped from moderator findings.
2. **Role coherence.** Reviewer = prosecution (external evidence). Author = defense (paper evidence). Moderator = judge (weighs presented evidence, introduces nothing). A judge that queries evidence on its own authority is a category error.
3. **Drift prevention.** The v1 hollow-run started with "just this once" carve-outs for the moderator. Keep the invariant absolute.

Enforcement: gate G-3-notebook rejects any moderator turn with `notebooks_granted` non-empty. If the Reviewer's output is malformed (`THEMATIC_FINDINGS:` missing or garbage), run the Reparse protocol once — **do NOT have the moderator fill in the findings**. If reparse fails twice, mark the lens `severity: "skipped"` with `evidence: "unavailable"`, per the failure-mode rules below.

The moderator's assessment turn at the end of round 1 has `notebooks_granted: []` and records only the signal + decision + reasoning (same shape as every other moderator turn in the skill).

---

## Degradation table (novelty-check status)

Behavior adapts to whether the background novelty-check returned in time:

| novelty_check.status | Lens 7 behavior |
|---|---|
| `completed` | Full triangulation: novelty-check results are included in the Reviewer's prompt as "external novelty signal"; thematic query happens; Author defends. |
| `running` or `failed` (timed out) | Partial triangulation: no external novelty signal. Reviewer proceeds with thematic notebook only. Briefing (Phase 5) notes "novelty pending". |
| `skipped` | As `running/failed`, plus briefing lists lens as not triangulated. |
| `failed` (errored spawn) | Same as `running/failed`. |

The degradation never falls back to proxy-author — I-1 is absolute.

---

## Per-round loop (replaces phase-3-debate.md §3.5 for lens 7 only)

### Round 1 — Reviewer question + thematic findings (single Reviewer turn)

Substitute into `REVIEWER_PERSONA`:

```
{{LENS_ID}}         = 7
{{LENS_NAME}}       = positioning
{{LENS_DESCRIPTION}}= Positioning vs. prior work (triangulation).
                      You have access to BOTH notebooks:
                        - Disposable ({{DISPOSABLE_NOTEBOOK_ID}}) — contains this paper.
                        - Thematic   ({{THEMATIC_NOTEBOOK_ID}}) — contains the relevant prior-art corpus.
                      Query the thematic notebook via mcp__notebooklm__notebook_query to
                      check whether the paper's claimed novelty survives comparison with
                      the downstream literature. Report findings in your turn.
{{NOTEBOOKS_GRANTED}}= [{{DISPOSABLE_NOTEBOOK_ID}}, {{THEMATIC_NOTEBOOK_ID}}]
{{NOVELTY_CHECK_BLOCK}}= <see below — populated only if status == "completed">
```

If `novelty_check.status == "completed"`, append to the prompt:

```
## External novelty-check signal (informational)

Score: {overall_score}/10
Recommendation: {recommendation}
Key differentiator: {key_differentiator}

Closest prior work:
- {paper1} ({year1}, {venue1}): overlap = {overlap1}; key difference = {key_difference1}
- {paper2} ...

Use this as input to your positioning challenge. You may agree with or push back
against the novelty-check's verdict based on your own thematic-notebook findings.
```

**Required output format** (parsed per `parsing/transcript-patterns.md` §3):

```
QUESTION: <positioning challenge the Reviewer wants the Author to answer>

THEMATIC_FINDINGS: <what thematic-notebook query returned — include verbatim
quote from the notebook result, paper-identifier, and brief synthesis of what
this means for the paper's positioning claim>
```

Spawn the Reviewer:

```
reviewer_text = Agent(
  description       = "paper-stress-test reviewer (lens 7, round 1)",
  subagent_type     = "general-purpose",
  model             = "opus",
  prompt            = reviewer_prompt,
  run_in_background = False,
)
```

Parse per §3. Record a single canonical `turn_record`:

```json
{
  "role": "reviewer",
  "round": 1,
  "content": "<full concatenated output: QUESTION block + THEMATIC_FINDINGS block>",
  "timestamp_iso": "<iso>",
  "lens_id": 7,
  "model": "opus",
  "notebooks_granted": ["<disposable_id>", "<thematic_id>"]
}
```

### Round 1 — Author defense (Sonnet, paper only)

Substitute into `AUTHOR_PERSONA`:

```
{{NOTEBOOKS_GRANTED}} = [{{DISPOSABLE_NOTEBOOK_ID}}]    # thematic is NOT passed
{{REVIEWER_QUESTION}} = <parsed QUESTION from above — NOT THEMATIC_FINDINGS>
```

**I-5 enforcement:** the Author's prompt MUST NOT reference or pass in the thematic notebook id or the thematic findings block. The Author defends only what the paper itself says; the Reviewer's thematic findings are the Reviewer's evidence, not the Author's. Gate G-3d-bis rejects any run where `thematic_id ∈ author.notebooks_granted`.

```
author_text = Agent(
  description       = "paper-stress-test author (lens 7, round 1)",
  subagent_type     = "general-purpose",
  model             = "sonnet",
  prompt            = author_prompt,
  run_in_background = False,
)
```

Parse per §5 (Author answer). Record canonical `turn_record`:

```json
{
  "role": "author",
  "round": 1,
  "content": "<ANSWER block + CITATIONS block>",
  "timestamp_iso": "<iso>",
  "lens_id": 7,
  "model": "sonnet",
  "notebooks_granted": ["<disposable_id>"]
}
```

### Round 1 — Moderator read + decide

In-context; no spawn. Read the two turns. Write reasoning. Classify signal. Decide:
- `close_lens` if the Reviewer's thematic findings are mild and the Author's defense is cited with direct quotes (severity likely `clean`) — no round 2 needed.
- `continue` to round 2 otherwise.

Append canonical `turn_record` with `role="moderator"`, `model="opus"`, `notebooks_granted=[]` (moderator holds no notebook). Also append to `state.moderator_assessments`.

### Round 2 — Confrontation (only if round 1 didn't close)

Build a confrontation prompt for the Reviewer:

```
{{LENS_ID}} = 7
{{CONFRONTATION_MODE}} = true
{{PRIOR_TRANSCRIPT}} = <round-1 reviewer turn + round-1 author turn>
{{NOTEBOOKS_GRANTED}} = [{{DISPOSABLE_NOTEBOOK_ID}}, {{THEMATIC_NOTEBOOK_ID}}]  # still both
```

The Reviewer may choose either path, per `parsing/transcript-patterns.md` §4:

- **CONFRONTATION path:** the Reviewer pushes back one more time on positioning. Output contains a single `CONFRONTATION:` field.
- **Early-close path:** the Reviewer concedes the Author's defense held up. Output contains `JUDGMENT: cited` + `SEVERITY: clean`.

Parse per §4. Record canonical `turn_record` with `role="reviewer"`, `model="opus"`, `notebooks_granted=[disposable, thematic]`, and `content` = full matched text.

If the Reviewer took the confrontation path, one more Author turn follows (same I-5 rules), then one more Moderator turn closing with severity. If early-close, severity is extracted directly from the Reviewer turn and the lens closes with 3 turns total (Reviewer, Author, Reviewer).

### Severity determination

Same rules as standard lenses (see `phase-3-debate.md` §Severity-from-judgment fallback). Applies to whichever terminal Reviewer turn carried the SEVERITY field.

---

## Failure modes — no proxy, always `skipped`

**If the Reviewer subagent spawn fails** (runtime error, unparseable output after reparse, etc.):

```json
{
  "lens_id": 7,
  "name": "positioning",
  "severity": "skipped",
  "one_line_finding": "Lens 7 skipped: Reviewer subagent failed to produce a parseable positioning turn.",
  "evidence": "unavailable",
  "author_best_defense": null,
  "summary_for_compaction": "Lens 7 skipped due to Reviewer spawn failure. No thematic triangulation performed.",
  "moderator_signals": ["stalling"],
  "transcript_slice": [ /* whatever turns were captured, conforming to turn_record */ ],
  "why_it_didnt_hold": "Subagent infrastructure failure; not a finding about the paper."
}
```

**If the Author subagent spawn fails:** same shape, with the Reviewer's round-1 turn preserved in `transcript_slice`. `severity = "skipped"`.

**Proxying is forbidden.** The v1 fallback of having the moderator speak as the Author is removed. Gate G-3d-bis enforces this.

Phase 4 synthesis treats `severity = "skipped"` lenses specially: they appear in the briefing under a "Skipped lenses" section, with the `why_it_didnt_hold` explanation.

---

## Exit

The lens record is appended to `state.lenses_completed` directly by the Moderator, and `state.transcript` is extended with the lens's `transcript_slice`. `state.json` is persisted after the lens closes. No merge step — flat dispatch.
