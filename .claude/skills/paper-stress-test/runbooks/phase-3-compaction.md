# Phase 3 (cont.) — Transcript compaction + Moderator own-context budget

**When:** invoked from inside each group-agent after each lens closes, and at the top-level Moderator before each Phase-3 dispatch.

**Why:** per-group context can bloat when lenses debate at depth 2+; the Moderator's own context can drift over time from accumulated persona prompts, notifications, and group returns. Both budgets are soft (they steer the flow) until they're hard (they abort the run).

---

## Step 3.7 — Transcript compaction

### Constants

```
COMPACTION_THRESHOLD_TOKENS = 6000      # ≈ 1.5 lenses at depth 2
DIGEST_MAX_CHARS            = 2000      # one-paragraph summary per lens
```

### Function `maybe_compact(transcript) -> running_ctx`

Called by each group-agent after writing the closed lens record.

1. Estimate tokens of `transcript` (chars/4 heuristic).
2. If `tokens < COMPACTION_THRESHOLD_TOKENS`: return `transcript` unchanged as `running_ctx`.
3. Else: produce a per-lens digest for every **closed** lens (latest 1–2 lenses are kept verbatim):
   ```
   Lens N (<name>, severity=<sev>): <one_line_finding>.
   Reviewer's best follow-up: "<trimmed>". Author's best defense: "<trimmed>".
   Moderator closed as <converging|progressing|stalling>.
   ```
   Truncate each digest to `DIGEST_MAX_CHARS`.
4. Append an entry to `state.compaction_history`:
   ```json
   {"at": "<iso>", "lenses_digested": [N, N+1, ...], "tokens_before": <int>, "tokens_after": <int>}
   ```
5. Return `running_ctx` = concatenation of all digests + latest 1–2 verbatim lenses.

### Where `running_ctx` is used

Passed into subsequent `build_reviewer_prompt` and `build_author_prompt` calls for later lenses in the same group. The subagent sees prior-lens context at a constant cost, regardless of how many lenses have closed.

### Invariants

- Compaction never alters `state.lenses_completed` or `state.transcript` on disk. Those remain verbatim.
- Compaction runs only inside group-agents, never in the top-level Moderator.
- `compaction_history` is an audit trail — validator checks it monotonically grows if any compaction fired.

---

## Step 3.7.5 — Moderator own-context soft budget

### Constants

```
MODERATOR_CONTEXT_SOFT_LIMIT_CHARS = 180_000   # ~45K tokens — well under 200K but leaves headroom
MODERATOR_CONTEXT_ABORT_LIMIT_CHARS = 220_000  # hard abort: unsafe to continue
```

### Tracked estimator

`state.moderator_own_context_est_chars` is incremented by the Moderator after every tool-use result, group return, or user message. Roughly: the byte-count of the tool result, clipped to what the Moderator actually incorporates.

### Enforcement

Before each Phase-3 dispatch AND at the end of each phase:

```python
if state.moderator_own_context_est_chars > MODERATOR_CONTEXT_ABORT_LIMIT_CHARS:
    abort_run("moderator_context_overflow", detail=f"est={est} > abort_limit={abort_limit}")

elif state.moderator_own_context_est_chars > MODERATOR_CONTEXT_SOFT_LIMIT_CHARS:
    # warn but continue — next phase is still safe
    print(f"[moderator context approaching limit: {est}/{abort_limit}]")
```

### User-facing message on abort

```
Aborting: the Moderator's own context has exceeded the safe operating budget
({est} chars > {abort_limit}). Partial state has been written to
${state_path}. Resume with:

  /paper-stress-test <paper-ref> --resume

The resume will start a fresh Moderator context and reload state from disk.
```

Partial-mode Phase 5 runs before termination (briefing marks incomplete lenses as `"evidence": "unavailable"`).

---

## Exit

Runbook returns to phase-3-debate flow.
