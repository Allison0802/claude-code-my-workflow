# Phase 6 — Cleanup + optional promote-to-thematic

**Preconditions:** Briefing and transcripts written; `state.json` schema-validates. `notebooks.disposable.disposition` is still `"pending"`.

**Postconditions (invariant I-4):**
- `notebooks.disposable.disposition ∈ {deleted, kept, promoted}` — never `pending`.
- `run_status` transitions to `completed` (or stays `aborted` if called from abort_run).
- `completed_at` set.

Gate G-3f (disposition resolved at completion) is checked at the end of this runbook and is the FINAL pass before state.json is considered canonical.

---

## Step 6.1 — Inline chat summary

Print a compact summary to the user:

```
Stress-test complete: <paper title>
Recommendation: <recommendation>  (severity tally: critical=N, major=N, minor=N, clean=N, skipped=N)

Top 3 killer questions:
  1. [Lens <id>/<name>, <severity>] <question>
  2. ...
  3. ...

Briefing:   ${OUT_ROOT}/briefing/${FULL_SLUG}_briefing.md
Transcripts: ${OUT_ROOT}/transcripts/${FULL_SLUG}_transcripts.md
State:      ${OUT_ROOT}/state/${FULL_SLUG}_state.json
```

On abort mode, prepend `⚠️ PARTIAL — aborted: <reason>`.

---

## Step 6.2 — Decide default disposition

Default is keyed off recommendation:

| Recommendation | Default disposition |
|---|---|
| `cite`, `build-on` | `promoted` (paper worth keeping in the thematic notebook) |
| `flag`             | `kept`     (keep disposable for later re-review; not promoted) |
| `skip`             | `deleted`  (no reason to keep the notebook) |

Partial/aborted runs default to `deleted` regardless of recommendation.

If `notebooks.thematic.id == null` (user skipped cross-check in Phase 1), the `promoted` option is unavailable and default falls back to `kept`.

---

## Step 6.3 — Prompt user

If `invocation.human_checkpoint == false`, skip the prompt and apply the default directly.

Otherwise:

```
Disposable NotebookLM notebook for this paper:
  ${notebooks.disposable.name}
  (id: ${notebooks.disposable.id})

What should happen to it? (default: <default>)
  [D] Delete
  [K] Keep disposable (no promotion)
  [P] Promote sources to thematic notebook '${notebooks.thematic.name}'
```

Input `D`, `K`, `P`, or empty (→ default).

---

## Step 6.4 — Execute chosen action

### `[D]` Delete

```
mcp__notebooklm__notebook_delete(notebook_id=notebooks.disposable.id)
```

On error, retry once. On second failure, keep the notebook, print a warning, set disposition to `kept`:
```
⚠️ Failed to delete disposable notebook ${id}. Leaving it in place. disposition=kept.
```

On success: `notebooks.disposable.disposition = "deleted"`, `promoted_to = null`.

### `[K]` Keep

```
notebooks.disposable.disposition = "kept"
notebooks.disposable.promoted_to = null
```

### `[P]` Promote

For each source in the disposable notebook, add it to the thematic notebook:

```
sources = mcp__notebooklm__source_list_drive(notebook_id=notebooks.disposable.id)  # or appropriate lister
for src in sources:
    mcp__notebooklm__source_add(
      notebook_id=notebooks.thematic.id,
      source_type=src.type,
      ...
    )
```

Then delete the disposable notebook (same call as `[D]`; failure → warning, disposition="kept", promoted_to still recorded with sources copied).

On success: `notebooks.disposable.disposition = "promoted"`, `promoted_to = notebooks.thematic.id`.

---

## Step 6.5 — Clean up /tmp download artifacts

If `paper.source` starts with `/tmp/arxiv-` or `/tmp/paper-`: delete the downloaded PDF. Bash:

```bash
# Only if paper source was arXiv or URL
case "$PAPER_SOURCE" in
  /tmp/arxiv-* | /tmp/paper-*) rm -f -- "$PAPER_SOURCE" ;;
esac
```

Skip silently if the file doesn't exist.

---

## Step 6.6 — Finalize state

```
state.run_status = "completed"   (or leave "aborted" if abort path)
state.completed_at = now_iso()
```

Persist state.json.

Run `scripts/validate_state.py` one last time with gate G-3f enabled (disposition resolved). Failure at this point is a skill bug.

---

## Step 6.7 — Final print

```
Disposable notebook: <disposition> (<name>)
Total spawns: <state.spawn_count>/<state.spawn_budget>
Wall clock: <elapsed>s / <budget>s
Run complete.
```

Return to SKILL.md. End of run.
