# Parsing contract for paper-stress-test

**Source of truth.** All parsing of subagent output (Reviewer, Author, classification-triple, novelty-check runner, group-moderator return) MUST use the regexes here. Do not reimplement these inline in SKILL.md or in any runbook — reference this file.

**Scope.** This file covers how *subagent text output* is parsed into `turn_record` fields. It does NOT define the `turn_record` JSON shape itself — that lives in `schema/state.schema.json` (definitions.turn_record) and `templates/transcript-slice.json`.

---

## Reparse protocol

On first parse failure, reprompt the source subagent with a format reminder (verbatim from the persona file, quoted). Capture the second response. If the second response still fails, do NOT reprompt again — hand off to task-specific recovery (record `errored`, user-prompted override, skip-lens, etc.).

Reprompt template:

```
Your previous response did not match the required format. The format is:

<copy the relevant format block from the persona verbatim>

Return ONLY a response in that format, nothing else.
```

---

## Patterns

All regexes below are PCRE-compatible extended regexes (Python `re`-compatible), multiline mode. Apply DOTALL (`(?s)` or `re.DOTALL`) when matching patterns that capture multi-line text with `.+?` lookaheads; do NOT apply DOTALL to single-line field anchors (`JUDGMENT`, `NEXT`, `SEVERITY`) that use `$` end-of-line anchors. Whitespace around field values must be trimmed on capture.

### 1. Reviewer primary-question turn

```
^QUESTION:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
```

Captures one group: the question text (may span multiple lines, stops at next `FIELD:` line or end of string). The full matched text becomes the `content` field of a single `turn_record` with `role: "reviewer"`.

### 2. Reviewer judgment + decision turn

Five fields, each on its own line; fields 4 and 5 are mutually exclusive based on field 3's value.

```
^JUDGMENT:[[:space:]]*(cited|evaded|handwaved|conceded)[[:space:]]*$
^REASONING:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
^NEXT:[[:space:]]*(FOLLOWUP|FINAL)[[:space:]]*$
^FOLLOWUP:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)     # only required if NEXT=FOLLOWUP
^SEVERITY:[[:space:]]*(critical|major|minor|clean)[[:space:]]*$  # only required if NEXT=FINAL
```

Validation: JUDGMENT must match the enum exactly. REASONING must be non-empty. If NEXT=FOLLOWUP, FOLLOWUP must be non-empty. If NEXT=FINAL, SEVERITY must match the enum exactly. The full matched text becomes the `content` of one `turn_record` with `role: "reviewer"`.

### 3. Reviewer Lens 7 initial turn (positioning)

Lens 7 is special: the Reviewer is granted access to the thematic notebook (invariant I-5) and performs the query itself, reporting findings inside its own turn. The output format is:

```
^QUESTION:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
^THEMATIC_FINDINGS:[[:space:]]*(.+?)(?=\n[A-Z_]+:|\z)
```

Both fields required and non-empty. Both are captured into the **same** `turn_record.content` (concatenated with a `\n\n` separator). One turn, one record — not two. The Reviewer's `notebooks_granted` field must include the thematic notebook id; this is enforced by gate G-3d-bis.

**Rename note (2026-04-23 refactor):** was `THEMATIC_QUERY` (moderator executed). Now `THEMATIC_FINDINGS` (Reviewer executes and reports).

### 4. Reviewer Lens 7 confrontation turn

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

### 5. Author answer turn

```
^ANSWER:[[:space:]]*(.+?)(?=\nCITATIONS:)
^CITATIONS:[[:space:]]*(.*)\z
```

The citation block is either:

- `CITATIONS: none` → `citations = []`
- one or more lines starting with `- ` under the CITATIONS header → `citations = [line.lstrip('- ') for line in lines]`

Validation:

- ANSWER must be non-empty.
- If ANSWER starts with the literal phrase `the paper does not address this`, the lens's `evidence` field is set to `"absent"` regardless of what follows in CITATIONS.
- The Author's `notebooks_granted` must NOT include the thematic notebook id (gate G-3d-bis / invariant I-5). Author sees paper + disposable only.

### 6. Classification triple-query response

The Reviewer returns three concatenated paragraphs with heading markers. Three fields to extract:

```
detected_type:   ^(?:##|\*\*)\s*Classification\s*(?:\*\*)?\s*\n\s*([a-z][a-zA-Z-]+)\b
headline_claim:  ^(?:##|\*\*)\s*Headline contribution\s*(?:\*\*)?\s*\n\s*"?([^"\n]+)"?
novelty_claims:  ^(?:##|\*\*)\s*Novelty claims\s*(?:\*\*)?\s*\n((?:\s*\d+\.\s+.+\n?)+)
```

Heading regex accepts BOTH `## Classification` AND `**Classification**` to tolerate persona format drift.

`detected_type` capture must match the 5-value enum; see `runbooks/phase-2-classify-plan.md` §Validate for the enforcement flow.

`novelty_claims` capture is a numbered-list block; split on `\n\s*\d+\.\s+` to get individual items.

### 7. novelty-check report

The `novelty-check` skill's Phase D output. Regexes:

```
overall_score:      Score:[[:space:]]*(\d+)/10
recommendation:     Recommendation:[[:space:]]*(PROCEED WITH CAUTION|PROCEED|ABANDON)
key_differentiator: Key differentiator:[[:space:]]*(.+?)(?=\n-|\n##|\z)
closest_prior_work: Closest Prior Work[[:space:]]*\n((?:\|.+\|\n)+)
```

For `closest_prior_work`, split each table row on `|` (strip pipes and whitespace), skip the header row and separator row, build a `{paper, year, venue, overlap, key_difference}` object per remaining row.

If any field fails to parse, leave it `null`. Do NOT fail the whole run — the raw report is kept in `raw_report_md` regardless.

### 8. Group-moderator return payload (Phase 3 parallel dispatch)

Each of the three parallel group moderators returns a **single JSON object** as its final text, no prose preamble, no markdown fences. Parse with:

```
^\s*\{[\s\S]*"group_id"\s*:\s*([0-2])[\s\S]*"lens_records"\s*:\s*\[[\s\S]*\][\s\S]*"partial_state_path"\s*:\s*"([^"]+)"[\s\S]*\}\s*$
```

Validation (all MUST pass, otherwise treat the group as errored and re-dispatch once):

- Top-level parses as a JSON object with required keys: `group_id` ∈ {0,1,2}; `lens_records` (array, 0–3 entries); `local_gate_results` (object with `g3a_local`, `g3b_local`, `g3c_local`, `g3d_bis_local` sub-objects each having boolean `passed`); `partial_state_path` (string, absolute path, file exists on disk); `group_spawn_count` (int ≥ 0); `aborted` (bool); `abort_reason` (string or null).
- For each entry in `lens_records`, the record matches `schema/state.schema.json#/definitions/lens_record`.
- Every `transcript_slice[i]` within each lens record matches `schema/state.schema.json#/definitions/turn_record` — **no `turn`, no `close_lens_mode`, no `action`, no `novelty_seed` keys** (gate G-3c).
- If `aborted == false`, `len(lens_records) == len(lens_ids_assigned)`. If `aborted == true`, `abort_reason` is non-null.
- The file at `partial_state_path` exists, parses as JSON, and has the same `group_id` and `lens_records` as the return payload (consistency check).

Out-of-order arrival: the Moderator buffers payloads by `group_id` in a dict and does NOT begin merge/synthesis until `len(received) == 3` (or until all un-received groups have exhausted their retry budget, in which case G-3a-aggregate catches the hollow-run).

---

## Cross-reference

| Pattern | Used in runbook |
|---------|---------------|
| 1. Primary question | `runbooks/phase-3-debate.md` (round 1 of any non-Lens-7 lens) |
| 2. Judgment + decision | `runbooks/phase-3-debate.md` (rounds 2..depth, close turn), `runbooks/phase-3-lens7.md` (terminal Reviewer), `runbooks/phase-4-synthesis.md` (severity extraction) |
| 3. Lens 7 initial (QUESTION + THEMATIC_FINDINGS) | `runbooks/phase-3-lens7.md` (round 1) |
| 4. Lens 7 confrontation (CONFRONTATION or JUDGMENT+SEVERITY) | `runbooks/phase-3-lens7.md` (round 2) |
| 5. Author answer (ANSWER + CITATIONS) | `runbooks/phase-3-debate.md`, `runbooks/phase-3-lens7.md` (every Author turn) |
| 6. Classification triple | `runbooks/phase-2-classify-plan.md` |
| 7. novelty-check | `runbooks/phase-2-classify-plan.md` |
| 8. Group-moderator return | `runbooks/phase-3-debate.md` (parallel dispatch merge) |
