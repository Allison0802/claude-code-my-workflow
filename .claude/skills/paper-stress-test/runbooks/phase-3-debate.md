# Phase 3 — Adversarial debate (flat sequential dispatch)

**Preconditions (from Phase 2):** `lens_plan` confirmed; `notebooks` populated; novelty-check dispatched (background).

**Postconditions:**

- `state.lenses_completed` has one record per active lens.
- `state.transcript` contains every turn across all lenses, flat-concatenated.
- `state.moderator_assessments` populated with per-round per-lens assessments.
- Gates G-3a, G-3b, G-3c, G-3-schema, G-3-model, G-3-notebook, G-3-mod-content have passed (else run aborts to partial-mode briefing).
- Gate G-5a (disposition) is not checked here — deferred to Phase 6.

---

## Architecture: flat, single-level dispatch

**The top-level Moderator (this skill's execution context) is the sole dispatcher.** For each active lens, the Moderator calls `Agent(Reviewer)` and `Agent(Author)` directly, round by round, reads the returned text in its own context, writes canonical turn records, and persists state after each lens closes.

**No group moderators. No nested subagents. No partial state files.** The 3×3 parallel architecture of the Apr-23 skill version was retired on 2026-04-24 when authoritative Claude Code documentation confirmed:

> Subagents cannot spawn other subagents. This is an architectural restriction, not a permissions issue. Even if you add `tools: Agent` to a custom subagent's frontmatter, the Agent tool is stripped at runtime.

The top-level skill has `Agent` in its `allowed-tools`; subagents it spawns do not. Any workflow that required a subagent to spawn further subagents has been redesigned to flat dispatch.

---

## Anti-rationalization table (do NOT take these shortcuts)

Hollow runs arise when the Moderator substitutes these framings for the actual debate loop. Each row is a spec violation.

| Rationalization | Why it's wrong |
|---|---|
| "I can infer severity from Phase 2a classification; no Reviewer spawn needed." | Severity must come from a Reviewer JUDGMENT emitted in an Agent spawn, per `parsing/transcript-patterns.md` §2. Classification in Phase 2a produces only classification/headline/novelty. |
| "I'll write the briefing first, then backfill state.json at the end." | state.json is the source of truth. Briefing is DERIVED from state.json in Phase 5. |
| "The transcript belongs in `transcripts/*.md`, not `state.transcript`." | Both. state.transcript is machine-readable truth; `transcripts/*.md` is a rendered view produced in Step 5.2. |
| "The briefing is the deliverable; state.json is bookkeeping." | state.json IS the deliverable. Partial-mode briefing reads it; hollow state.json → garbage briefing. |
| "I can shortcut by having the Moderator synthesize Reviewer/Author content directly without spawning subagents." | This is the v1 hollow-run pattern. Every Reviewer and Author turn MUST come from an `Agent(...)` call with `role` labeled honestly and `model` matching `^(opus\|sonnet\|haiku)(-...)?$`. Gates G-3-model and G-3-schema reject anything else. |
| "If Lens 7's Reviewer spawn fails, the Moderator can run the thematic query itself." | No. Invariant I-5: moderator holds no notebook. Reparse once; if still malformed, mark lens `severity: "skipped"`. |

## MUST-NOTs (hard spec violations)

1. **MUST dispatch Reviewer and Author via `Agent` within the Moderator's own context.** No nested subagents (the runtime strips `Agent` from subagents anyway).
2. **MUST NOT run the per-lens debate "mentally" — every turn is an Agent spawn.** Severity from classification inference is a drift pattern.
3. **MUST persist state.json after each lens closes** so aborts are recoverable.
4. **MUST run aggregate gates before exiting Phase 3.** Any failure → partial-mode briefing.
5. **MUST NOT hold the thematic notebook in any moderator turn (I-5).** Reviewer does thematic queries in Lens 7; moderator `notebooks_granted` is always `[]`.

---

## Phase 3 entry — capture `wall_clock_start`

If `state.wall_clock_start == null`: set to `now_iso()` and persist. This excludes idle Phase-2 plan-confirmation time from the budget. On resume it is NOT reset.

---

## Step 3.1 — First novelty-check collection point (non-blocking)

No poll, no sleep. Check in order:

1. Has a completion notification for `state.novelty_check.runner_agent_id` arrived? → parse per `parsing/transcript-patterns.md` §7, set `status="completed"` + fields.
2. Not completed: `elapsed = now - novelty_check.started_at`.
   - `elapsed > 300` → set `status = "failed"`, `completed_at = now`, `raw_report_md = null`.
   - else → leave `running`. Second check point is at Lens 7.

---

## Step 3.2 — Load persona templates once

```
REVIEWER_PERSONA = Read(".claude/skills/paper-stress-test/agents/reviewer.md")
AUTHOR_PERSONA   = Read(".claude/skills/paper-stress-test/agents/author.md")
```

---

## Step 3.3 — Initialize transcript buffers

```
state.transcript            = []
state.compaction_history    = []
state.moderator_assessments = []
```

**Canonical turn_record shape** (must match `schema/state.schema.json#/definitions/turn_record`):

```json
{
  "role": "reviewer|author|moderator",
  "round": <int >= 1>,
  "content": "<verbatim turn text>",
  "timestamp_iso": "2026-04-24T...Z",
  "lens_id": <0..8>,
  "model": "opus|sonnet|haiku",
  "notebooks_granted": ["<id>", ...]
}
```

Moderator reasoning, signal, and decision are concatenated INTO the `content` field of a moderator turn. The canonical schema allows no extras.

---

## Step 3.4 — Per-lens debate (the main loop)

```
active_lenses = [l for l in state.lens_plan if l.depth > 0]

for lens in sorted(active_lenses, key=lambda l: l.lens_id):

    check_budgets_before_lens()          # see §Step 3.5 below
    running_ctx = maybe_compact(state.transcript)  # see runbooks/phase-3-compaction.md

    if lens.lens_id == 7:
        lens_record = run_lens_7(lens, running_ctx)        # see runbooks/phase-3-lens7.md
    else:
        lens_record = run_standard_lens(lens, running_ctx) # §Per-lens function below

    state.lenses_completed.append(lens_record)
    state.transcript       += lens_record.transcript_slice

    persist_state_json()                 # fsync state.json after each lens
```

`sorted by lens_id` is a canonical order, not a dependency — lenses are independent. Ordering just makes resume deterministic.

---

## Step 3.5 — Budget enforcement

**Constants (from SKILL.md):**

```
SPAWN_BUDGET                       = 80
WALL_CLOCK_BUDGET_SECONDS          = 1800
MODERATOR_CONTEXT_SOFT_LIMIT_CHARS = 180_000
MODERATOR_CONTEXT_ABORT_LIMIT_CHARS = 220_000
```

**`check_budgets_before_lens()`** — called at the top of each lens iteration:

```python
def check_budgets_before_lens():
    if state.spawn_count >= state.spawn_budget:
        abort_run("spawn_budget_exhausted")

    elapsed = now_seconds() - iso_to_seconds(state.wall_clock_start)
    if elapsed > state.wall_clock_budget_s:
        abort_run("wall_clock_budget_exhausted")

    if state.moderator_own_context_est_chars > MODERATOR_CONTEXT_ABORT_LIMIT_CHARS:
        abort_run("moderator_context_overflow")
```

**`abort_run(reason, detail=None)`:**

1. Set `state.abort_reason = f"{reason}: {detail}"` if detail else `reason`.
2. Set `state.run_status = "aborted"`.
3. Set `state.completed_at = now_iso()`.
4. Persist canonical state.json.
5. Invoke `runbooks/phase-5-artifacts.md` with `partial=True`.
6. Invoke `runbooks/phase-6-cleanup.md` with `aborted=True`.
7. Print user-facing abort message and exit.

**I-4 guard:** phase-6-cleanup must resolve `notebooks.disposable.disposition` even on abort. Running aborted with `disposition: "pending"` violates I-4 and is caught by gate G-5a at final persistence.

---

## Step 3.6 — Per-lens function `run_standard_lens(lens, running_ctx)`

Local state:

```
lens_transcript         = []
latest_moderator_entry  = None
severity                = None
```

Per-round loop, `for round in 1..lens.depth`:

### 1. Spawn fresh Reviewer (Opus)

```
reviewer_prompt = build_reviewer_prompt(
  persona        = REVIEWER_PERSONA,
  paper_context  = state.paper,
  notebook_ids   = {"disposable": state.notebooks.disposable.id, "thematic": null},  # standard lens: no thematic
  lens           = lens,
  round          = round,
  transcript     = running_ctx + lens_transcript,
  moderator_steer= (latest_moderator_entry.steer if decision=="inject_steer" else None),
  close_lens_mode= (latest_moderator_entry and latest_moderator_entry.decision == "close_lens"),
)
reviewer_text = Agent(
  description   = "paper-stress-test reviewer (lens {lens_id}, round {round})",
  subagent_type = "general-purpose",
  model         = "opus",
  prompt        = reviewer_prompt,
  run_in_background = False,
)
state.spawn_count += 1
```

**I-5 enforcement:** for non-Lens-7 lenses, `thematic` is `null` — the Reviewer never sees the thematic notebook. Gate G-3-notebook enforces this when state.json is validated.

Parse per `parsing/transcript-patterns.md`:

- round 1, no close_lens → §1 (Primary question)
- round > 1, no close_lens → §2 (Judgment + decision)
- close_lens_mode → §2 FINAL only

Append canonical `turn_record` with `role="reviewer"`, `model="opus"`, `notebooks_granted=[disposable.id]`.

### 2. Early exit if FINAL

If `parsed.next == "FINAL"` OR close_lens_mode was true:

- `severity = parsed.severity` (fallback table below if missing)
- Skip Author and Moderator
- Break loop

### 3. Spawn fresh Author (Sonnet)

```
author_prompt = build_author_prompt(
  persona=AUTHOR_PERSONA,
  paper_context=state.paper,
  disposable_nb_id=state.notebooks.disposable.id,
  transcript=running_ctx + lens_transcript,
  reviewer_question=parsed.question_or_followup,
)
author_text = Agent(
  description   = "paper-stress-test author (lens {lens_id}, round {round})",
  subagent_type = "general-purpose",
  model         = "sonnet",
  prompt        = author_prompt,
  run_in_background = False,
)
state.spawn_count += 1
```

Parse per §5 (Author answer). Append canonical `turn_record` with `role="author"`, `model="sonnet"`, `notebooks_granted=[disposable.id]` (never thematic — I-5 / G-3-notebook).

### 4. Moderator read / reason / decide (in-context; no spawn)

- **Read** the round's two new turns.
- **Write reasoning** (2–5 sentences).
- **Classify** `progressing | stalling | converging`.
- **Decide** `continue | inject_steer | close_lens`.

Append canonical `turn_record` with `role="moderator"`, `model="opus"`, `notebooks_granted=[]` (moderator holds no notebook). `content` contains reasoning + signal + decision + steer:

```
Signal: progressing. Decision: continue.
Reasoning: The Reviewer probed X; Author cited Y and acknowledged Z; substance advanced because ...
```

Also append a `moderator_assessments` entry `{lens_id, round, content, timestamp_iso}`.

Set `latest_moderator_entry` to this entry.

### 5. Act on close_lens

If `decision == "close_lens"` and `round < lens.depth`: next iteration runs in `close_lens_mode`, forcing FINAL.

If `decision == "close_lens"` and `round == lens.depth`: spawn one more terminal Reviewer ignoring depth exhaustion; parse SEVERITY; mark terminal; break.

### 6. Post-loop FINAL fallback

After the loop, if severity still unset: spawn one terminal Reviewer with close_lens_mode=true. Parse SEVERITY; fall back to mapping below if missing.

### 7. Return `lens_record`

```json
{
  "lens_id": <id>,
  "name": <name>,
  "severity": <final>,
  "one_line_finding": "<from terminal Reviewer REASONING or distilled>",
  "evidence": "present|absent|partial|unavailable",
  "author_best_defense": "<non-empty or null>",
  "summary_for_compaction": "<≤ 3 sentences>",
  "moderator_signals": [<non-empty strings; signal labels or analytical notes>],
  "transcript_slice": <lens_transcript>,
  "why_it_didnt_hold": "<required if severity != clean>"
}
```

### Severity-from-judgment fallback

| Final judgment | Severity |
|---|---|
| `cited`     | `clean` |
| `handwaved` | `minor` |
| `evaded`    | `major` |

---

## Step 3.7 — Aggregate gate check after all lenses

After the lens loop completes, before returning to SKILL.md:

```bash
python3 scripts/validate_state.py ${state_path}
python3 scripts/enforce_schema.py  ${state_path}
```

Both must exit 0. Any failure → `abort_run("aggregate_gate_failed", detail=<gate + lens>)`. Partial-mode Phase 5 still runs before termination.

---

## Further reading

- `runbooks/phase-3-compaction.md` — transcript compaction + Moderator own-context budget
- `runbooks/phase-3-lens7.md` — Lens 7 (positioning) with Reviewer-owned thematic notebook
- `parsing/transcript-patterns.md` — all 8 regex patterns + reparse protocol
- `schema/state.schema.json` — canonical turn_record and lens_record shape

---

## Exit state

state.json now contains `lenses_completed` (one record per active lens), `transcript` (flat turn-record list), `moderator_assessments`. Aggregate gates have passed. Ready for Phase 4.

Return to SKILL.md, which loads `runbooks/phase-4-synthesis.md`.
