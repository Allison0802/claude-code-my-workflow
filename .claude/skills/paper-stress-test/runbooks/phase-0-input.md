# Phase 0 — Input resolution and prior-test detection

**Preconditions (from caller):** `$ARGUMENTS` string (raw user invocation).

**Postconditions (what must exist when this runbook returns):**
- `paper.source` set to a local, verified `.pdf` path (downloaded to `/tmp/` if remote).
- `paper.slug` populated and matches pattern `^[a-z0-9_]+_\d{4}-\d{2}-\d{2}$`.
- Output directories exist: `stress_tests/briefing/`, `stress_tests/transcripts/`, `stress_tests/state/`.
- User has been prompted about any prior stress-tests and resume state.
- If resume requested and accepted, remaining runbooks are short-circuited — see §Resume.

---

## Step 0.1 — Parse `$ARGUMENTS` and resolve `<paper-ref>`

Supported `<paper-ref>` forms:

| Form | Detection rule | Resolution |
|------|----------------|-----------|
| Local absolute path | starts with `/` and ends in `.pdf` | verify exists with `test -f`; if not, abort |
| Local relative path | not absolute but contains `.pdf` | resolve against CWD; verify exists |
| `supporting_papers/` filename | bare filename present in `master_supporting_docs/supporting_papers/` | resolve full path |
| arXiv ID | matches `^[0-9]{4}\.[0-9]{4,5}(v[0-9]+)?$` | download to `/tmp/arxiv-<id>.pdf` |
| URL | starts with `http://` or `https://` | `curl -L -o /tmp/paper-<timestamp>.pdf <url>` |

arXiv download:

```bash
ARXIV_ID="2401.12345"
curl -sL -o "/tmp/arxiv-${ARXIV_ID}.pdf" "https://arxiv.org/pdf/${ARXIV_ID}.pdf"
test -s "/tmp/arxiv-${ARXIV_ID}.pdf" || { echo "arXiv download failed"; exit 1; }
```

On download failure, retry once after 5s sleep; on second failure, abort.

---

## Step 0.2 — Generate slug

Slug format: `<firstauthor>_<year>_<shorttitle>_<YYYY-MM-DD>`.

1. Use the `Read` tool on pages 1–2 of the PDF (`pages: "1-2"`).
2. From the rendered text, extract:
   - First author's last name (lowercase, ASCII-only — strip diacritics; drop suffixes like "Jr.").
   - Publication year (4-digit; copyright line or header).
   - Short title: lowercase the title, strip punctuation, take the first two content words. Skip articles: "the", "a", "an", "on", "of", "in", "for".
3. Today's date: `date +%Y-%m-%d`.
4. Assemble: `${author}_${year}_${title1}_${title2}_${date}` (use a single title word with underscore if only one content word).

Examples:

- "Kalbfleisch & Prentice (2002), *The Statistical Analysis of Failure Time Data*" → `kalbfleisch_2002_statistical_analysis_2026-04-22`
- "Zhang et al. (2024), *Deep Survival Forests for Competing Risks*" → `zhang_2024_deep_survival_2026-04-22`

---

## Step 0.3 — Create output directories

```bash
OUT_ROOT="/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/master_supporting_docs/supporting_papers/stress_tests"
mkdir -p "${OUT_ROOT}/briefing" "${OUT_ROOT}/transcripts" "${OUT_ROOT}/state"
```

---

## Step 0.4 — Prior-test detection

The slug prefix (everything before the date) identifies this paper across runs. Glob for prior briefings:

```bash
SLUG_PREFIX="kalbfleisch_2002_statistical_analysis"
ls "${OUT_ROOT}/briefing/${SLUG_PREFIX}"*_briefing.md 2>/dev/null
```

For each prior briefing file, count `critical` and `major` rows in its severity summary table:

```bash
for f in "${OUT_ROOT}/briefing/${SLUG_PREFIX}"*_briefing.md; do
  [ -f "$f" ] || continue
  CRIT=$(grep -c '| critical |' "$f" 2>/dev/null || echo 0)
  MAJ=$(grep -c '| major |' "$f" 2>/dev/null || echo 0)
  echo "$(basename "$f"): critical=${CRIT}, major=${MAJ}"
done
```

If prior hits exist, prompt:

> Prior stress-tests of this paper:
>   - kalbfleisch_2002_statistical_analysis_2026-03-14_briefing.md (critical: 2, major: 3)
>   - kalbfleisch_2002_statistical_analysis_2026-01-08_briefing.md (critical: 0, major: 1)
>
> Continue with new stress-test? [Y/n]

If user answers `n`, abort cleanly (no notebook created, no state written).

---

## Step 0.5 — Resume detection

If `${OUT_ROOT}/state/${FULL_SLUG}_state.json` already exists, prompt:

> A stress-test with today's slug is already in progress or completed:
>   ${FULL_SLUG}_state.json (run_status: in_progress)
>
> Choose:
>   [R] Resume from last completed lens
>   [S] Start fresh (overwrites state file; previous briefing left intact)
>   [A] Abort

- **R** — load state.json, jump directly to Phase 3 with `lenses_completed` already populated. Skip Phases 1 and 2; reuse persisted notebook IDs and plan.
- **S** — delete the state file, restart Phase 0 fresh. User has already acknowledged.
- **A** — exit.

See `SKILL.md §Resumability` for the detailed resume protocol.

---

## Exit state

By the end of Phase 0, the Moderator has:

- A validated local PDF path (`paper.source`).
- A full slug (`paper.slug`).
- Output directories created.
- User acknowledgment of any prior tests.
- Resume decision made (or no resume case).

Return control to SKILL.md, which loads `runbooks/phase-1-notebooklm.md`.
