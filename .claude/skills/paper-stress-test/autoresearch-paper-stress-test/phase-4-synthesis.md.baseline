# Phase 4 — Synthesis

**Preconditions:** state.json has `lenses_completed` populated, all aggregate gates passed.

**Postconditions:** `state.synthesis` populated with `verdict`, `top_killer_questions[≤5]`, `subproject_relevance{}`, `recommendation ∈ {cite, build-on, flag, skip}`, and `recommendation_rationale`.

---

## Step 4.1 — Read CLAUDE.md for sub-project context

Read the parent `CLAUDE.md` from the repo root. Extract the active sub-projects' names, focuses, and constraints. This drives Step 4.3 (sub-project relevance).

If `CLAUDE.md` references specific sub-project CLAUDE.md files (e.g., `Missing Types/CLAUDE.md`, `comparisons/CLAUDE.md`), read those too.

---

## Step 4.2 — Compose top killer questions

Rank the top 5 (at most) questions by combined severity + impact:

1. Sort `lenses_completed` by severity: `critical` → `major` → `minor`. Skip `clean` and `skipped`.
2. For each non-clean/non-skipped lens, extract its `one_line_finding` as the basis for a killer question.
3. For each question, produce a `{question, lens_id, lens_name, severity, why_it_matters}` record. `why_it_matters` is one sentence on downstream stakes (citation risk, replication risk, etc.).
4. Cap at 5. If more than 5 critical+major findings exist, note the overflow in the verdict prose.

---

## Step 4.3 — Sub-project relevance

For each active sub-project in CLAUDE.md, compose:

```
{
  "applies": "<Yes/Partial/No + reason>",
  "data_match": "<DGP and setting comparison vs. the sub-project's>",
  "warning": "<which lens findings are most relevant to the sub-project's own work>",
  "missing_comparator": "<is this paper a candidate baseline for the sub-project; if not, why not>"
}
```

This section guides the sub-project teams on how (or whether) to cite/use the paper.

---

## Step 4.4 — Compose verdict + recommendation

**Verdict prose** (2–4 sentences): synthesize across lenses. Lead with what the paper does well (clean lenses), then what fails (major/critical). End with the one line that summarizes whether the paper is trustworthy for its claimed scope.

**Recommendation** — mechanical rule based on severity tally across `lenses_completed`:

| Severity tally | Recommendation |
|---|---|
| `critical ≥ 1` OR `major ≥ 5` | `skip` |
| `major ≥ 3` | `flag` |
| `major ≥ 1` OR `minor ≥ 5` | `build-on` (use with caveats) |
| else (mostly `clean`) | `cite` |

Override: the Moderator may escalate one step more severe than the table if the synthesis sees a pattern not captured by per-lens severities (e.g., three minors about the same unaddressed issue). Never downgrade below the table.

**Recommendation rationale** (1–3 sentences): name the severity tally explicitly and justify the rule invocation.

---

## Exit

`state.synthesis` complete. Persist state.json. Return to SKILL.md, which loads `runbooks/phase-5-artifacts.md`.
