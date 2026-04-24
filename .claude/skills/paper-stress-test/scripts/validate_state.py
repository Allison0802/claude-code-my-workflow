#!/usr/bin/env python3
"""
Post-hoc validator for paper-stress-test state.json files.

Checks GATE invariants documented in SKILL.md:
  - G-3a           : per-lens hollow-run invariants (transcript_slice length, non-empty fields).
  - G-3b           : per-lens required keys + severity enum.
  - G-3c           : phase 3 integrity (spawn counts, transcript length vs slice_total).
  - G-3-schema     : NEW (2026-04-23 refactor) — every turn_record matches canonical shape
                     (keys role/round/content/timestamp_iso/lens_id; no turn/action/close_lens_mode/
                     novelty_seed/notebook_id/query/result_summary at the record level).
  - G-3-model      : NEW — every Author turn's "model" matches ^(opus|sonnet|haiku)(-[a-z0-9-]+)?$.
                     Rejects moderator_notebook_proxy.
  - G-3-notebook   : NEW (invariant I-5) — role-notebook isolation. Author's notebooks_granted
                     MUST NOT include thematic notebook id. Moderator's MUST be [].
  - G-3-mod-content: NEW — moderator_assessments entries have non-empty content and non-null round.
  - G-4a           : synthesis schema + recommendation enum.
  - G-5a           : disposition resolved at completion (I-4).

Exits 0 if well-formed, 1 otherwise. Prints one line per violation to stdout.

Usage:
    python3 validate_state.py <path-to-state.json>

Modes:
  default: validate a fully-merged state.json against all gates.

Note (2026-04-24 flat-dispatch refactor): --partial-group and --check-merge
modes were removed. The skill no longer produces partial state files because
nested subagent dispatch is architecturally impossible in Claude Code. All
lenses run inside the top-level Moderator; there is one state.json, nothing
to merge.

Stdlib only; no external dependencies.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


RECOMMENDATION_ENUM = {"cite", "build-on", "flag", "skip"}
SEVERITY_ENUM = {"critical", "major", "minor", "clean", "errored", "skipped"}
ROLE_ENUM = {"reviewer", "author", "moderator"}
MODEL_RE = re.compile(r"^(opus|sonnet|haiku)(-[a-z0-9-]+)?$")
# Canonical turn_record keys (schema/state.schema.json#/definitions/turn_record).
CANONICAL_TURN_KEYS = {"role", "round", "content", "timestamp_iso", "lens_id"}
OPTIONAL_TURN_KEYS = {"model", "notebooks_granted"}
ALLOWED_TURN_KEYS = CANONICAL_TURN_KEYS | OPTIONAL_TURN_KEYS
# Forbidden keys that appeared in v1 Group-2 drift.
FORBIDDEN_TURN_KEYS = {
    "turn", "action", "close_lens_mode", "novelty_seed",
    "notebook_id", "query", "result_summary", "result_verbatim",
    "phase", "confrontation_mode",
}
FORBIDDEN_ROLES = {
    "moderator_notebook_query", "moderator_thematic_query",
    "moderator_notebook_proxy", "moderator_direct", "moderator_notebook_proxy_author",
}
REQUIRED_LENS_KEYS = (
    "lens_id",
    "name",
    "severity",
    "one_line_finding",
    "evidence",
    "author_best_defense",
    "summary_for_compaction",
    "moderator_signals",
    "transcript_slice",
)
REQUIRED_SYNTHESIS_KEYS = (
    "verdict",
    "top_killer_questions",
    "subproject_relevance",
    "recommendation",
    "recommendation_rationale",
)


def _nonempty_str(v: Any) -> bool:
    return isinstance(v, str) and v.strip() != "" and v.strip() != "not provided"


def check_g3a(state: dict) -> list[str]:
    """Pre-lens invariants. Applied to each completed lens as if it were 'prior'."""
    fails: list[str] = []
    lenses = state.get("lenses_completed", []) or []
    for i, lens in enumerate(lenses):
        lens_id = lens.get("lens_id", f"<index {i}>")
        severity = lens.get("severity")
        # Skipped lenses (severity='skipped' per predictive-ML weight matrix or abort path)
        # are exempt from content gates — they have no debate to validate. They still must
        # be recorded in lenses_completed with a non-empty one_line_finding (explaining why)
        # and summary_for_compaction (so synthesis can reference them), but author_best_defense
        # and a full transcript_slice don't apply because no Author was spawned.
        is_skipped = severity == "skipped"
        slice_ = lens.get("transcript_slice") or []
        min_slice_len = 1 if is_skipped else 3
        if not isinstance(slice_, list) or len(slice_) < min_slice_len:
            fails.append(
                f"GATE G-3a FAIL: lens {lens_id} ({lens.get('name', '?')}) "
                f"transcript_slice length {len(slice_) if isinstance(slice_, list) else 'N/A'} < {min_slice_len}"
            )
        required_fields = ("one_line_finding", "summary_for_compaction") if is_skipped else \
            ("one_line_finding", "author_best_defense", "summary_for_compaction")
        for fld in required_fields:
            if not _nonempty_str(lens.get(fld)):
                fails.append(
                    f"GATE G-3a FAIL: lens {lens_id} ({lens.get('name', '?')}) "
                    f"{fld} is empty/missing/'not provided'"
                )
    if lenses and state.get("spawn_count", 0) < 1:
        fails.append(
            f"GATE G-3a FAIL: spawn_count={state.get('spawn_count', 0)} "
            f"but {len(lenses)} lenses marked complete (classification alone requires ≥1 spawn)"
        )
    if len(state.get("moderator_assessments") or []) < len(lenses):
        fails.append(
            f"GATE G-3a FAIL: moderator_assessments has "
            f"{len(state.get('moderator_assessments') or [])} entries "
            f"but {len(lenses)} lenses complete — each lens needs ≥1 moderator entry"
        )
    return fails


def check_g3b(state: dict) -> list[str]:
    """Per-lens record validation: all required keys present, severity in enum."""
    fails: list[str] = []
    for i, lens in enumerate(state.get("lenses_completed") or []):
        lens_id = lens.get("lens_id", f"<index {i}>")
        name = lens.get("name", "?")
        for key in REQUIRED_LENS_KEYS:
            if key not in lens:
                fails.append(f"GATE G-3b FAIL: lens {lens_id} ({name}) missing key '{key}'")
        sev = lens.get("severity")
        if sev not in SEVERITY_ENUM:
            fails.append(
                f"GATE G-3b FAIL: lens {lens_id} ({name}) severity={sev!r} not in {sorted(SEVERITY_ENUM)}"
            )
        if sev and sev != "clean" and "why_it_didnt_hold" not in lens:
            fails.append(
                f"GATE G-3b FAIL: lens {lens_id} ({name}) severity={sev!r} "
                f"but why_it_didnt_hold missing (required when severity != 'clean')"
            )
        ms = lens.get("moderator_signals")
        if not isinstance(ms, list) or len(ms) == 0:
            fails.append(
                f"GATE G-3b FAIL: lens {lens_id} ({name}) moderator_signals empty/missing"
            )
    return fails


def check_g3c(state: dict) -> list[str]:
    """End-of-Phase-3 integrity."""
    fails: list[str] = []
    plan = state.get("lens_plan") or []
    active = [l for l in plan if (l.get("depth") or 0) > 0]
    lenses = state.get("lenses_completed") or []
    if state.get("run_status") in {"completed", "in_progress"}:
        if len(lenses) != len(active):
            fails.append(
                f"GATE G-3c FAIL: lenses_completed has {len(lenses)} entries "
                f"but {len(active)} active lenses in plan"
            )
    depth_sum = sum((l.get("depth") or 0) for l in active)
    if state.get("run_status") == "completed" and depth_sum > 0:
        # Flat-dispatch formula (2026-04-24): 2 spawns per depth unit (Reviewer + Author per lens/round)
        # plus 1 for the Phase-2a classification call. Group-agent dispatches do not exist anymore.
        floor_flat = 2 * depth_sum + 1
        sc = state.get("spawn_count", 0)
        if sc < floor_flat:
            fails.append(
                f"GATE G-3c FAIL: spawn_count={sc} < flat-dispatch floor 2*sum(depth)+1={floor_flat} "
                f"(Reviewer+Author per depth unit + 1 Phase-2a classification; a hollow run has 0)"
            )
    if len(state.get("moderator_assessments") or []) < len(lenses):
        fails.append(
            f"GATE G-3c FAIL: moderator_assessments={len(state.get('moderator_assessments') or [])} "
            f"< lenses_completed={len(lenses)}"
        )
    transcript = state.get("transcript") or []
    transcript_len = len(transcript) if isinstance(transcript, list) else 0
    slice_total = sum(
        len(l.get("transcript_slice") or [])
        for l in lenses
        if isinstance(l.get("transcript_slice"), list)
    )
    # Per M4 (2026-04-24 schema change), state.transcript is OPTIONAL — canonical
    # per-lens turns live in lenses_completed[*].transcript_slice. Only enforce the
    # length inequality if state.transcript is explicitly populated (non-empty list);
    # absent/empty root transcript is acceptable as long as every lens has a valid slice.
    if (
        state.get("run_status") == "completed"
        and transcript_len > 0
        and transcript_len < slice_total
    ):
        fails.append(
            f"GATE G-3c FAIL: transcript length={transcript_len} < "
            f"sum(transcript_slice lengths)={slice_total} "
            f"(when root transcript is populated it MUST equal the concatenation of slices)"
        )
    return fails


def _iter_all_turn_records(state: dict):
    """Yield (location, turn_record) pairs for every turn across state.transcript and
    every lens.transcript_slice. Deduplication is not attempted — a turn in both places
    is emitted twice so the offending location is always named."""
    for i, t in enumerate(state.get("transcript") or []):
        yield (f"state.transcript[{i}]", t)
    for i, lens in enumerate(state.get("lenses_completed") or []):
        lens_id = lens.get("lens_id", f"<index {i}>")
        for j, t in enumerate(lens.get("transcript_slice") or []):
            yield (f"lens {lens_id} transcript_slice[{j}]", t)


def check_g3_schema(state: dict) -> list[str]:
    """NEW 2026-04-23. Every turn_record matches canonical shape — no legacy keys."""
    fails: list[str] = []
    for loc, t in _iter_all_turn_records(state):
        if not isinstance(t, dict):
            fails.append(f"GATE G-3-schema FAIL: {loc} is {type(t).__name__}, expected object")
            continue
        keys = set(t.keys())
        # Forbidden keys present?
        bad = keys & FORBIDDEN_TURN_KEYS
        if bad:
            fails.append(
                f"GATE G-3-schema FAIL: {loc} has forbidden keys {sorted(bad)} "
                f"(v1 Group-2 drift pattern)"
            )
        # Required keys present?
        missing = CANONICAL_TURN_KEYS - keys
        if missing:
            fails.append(
                f"GATE G-3-schema FAIL: {loc} missing required keys {sorted(missing)}"
            )
        # Extra keys beyond canonical + optional?
        extra = keys - ALLOWED_TURN_KEYS
        if extra:
            fails.append(
                f"GATE G-3-schema FAIL: {loc} has unexpected keys {sorted(extra)} "
                f"(not in canonical shape)"
            )
        # Role in enum, NOT in forbidden list.
        role = t.get("role")
        if role in FORBIDDEN_ROLES:
            fails.append(
                f"GATE G-3-schema FAIL: {loc} role={role!r} is a legacy drift role "
                f"(must be one of {sorted(ROLE_ENUM)})"
            )
        elif role not in ROLE_ENUM:
            fails.append(
                f"GATE G-3-schema FAIL: {loc} role={role!r} not in {sorted(ROLE_ENUM)}"
            )
        # content non-empty string.
        if not _nonempty_str(t.get("content")):
            fails.append(f"GATE G-3-schema FAIL: {loc} content is empty/missing")
        # round integer >= 1.
        r = t.get("round")
        if not isinstance(r, int) or r < 1:
            fails.append(f"GATE G-3-schema FAIL: {loc} round={r!r} must be int >= 1")
        # lens_id integer in 0..8.
        lid = t.get("lens_id")
        if not isinstance(lid, int) or not (0 <= lid <= 8):
            fails.append(f"GATE G-3-schema FAIL: {loc} lens_id={lid!r} must be int in 0..8")
    return fails


def check_g3_model(state: dict) -> list[str]:
    """NEW. Every turn's model (if present) matches opus|sonnet|haiku pattern.
    Rejects moderator_notebook_proxy and similar v1 drift values."""
    fails: list[str] = []
    for loc, t in _iter_all_turn_records(state):
        if not isinstance(t, dict):
            continue
        model = t.get("model")
        if model is None:
            continue  # optional field; if absent we don't check it here
        if not isinstance(model, str) or not MODEL_RE.match(model):
            fails.append(
                f"GATE G-3-model FAIL: {loc} model={model!r} does not match "
                f"^(opus|sonnet|haiku)(-[a-z0-9-]+)?$"
            )
    return fails


def check_g3_notebook(state: dict) -> list[str]:
    """NEW (invariant I-5). Role-notebook isolation:
       - Reviewer: MAY include thematic id (required for Lens 7).
       - Author:   MUST NOT include thematic id (ever).
       - Moderator: MUST be [].
    """
    fails: list[str] = []
    notebooks = state.get("notebooks") or {}
    thematic = (notebooks.get("thematic") or {}).get("id")
    if thematic is None:
        # User opted out of cross-check in Phase 1; I-5 vacuously holds.
        return fails
    for loc, t in _iter_all_turn_records(state):
        if not isinstance(t, dict):
            continue
        role = t.get("role")
        granted = t.get("notebooks_granted")
        if granted is None:
            continue  # optional field; absence is not a violation on its own
        if not isinstance(granted, list):
            fails.append(
                f"GATE G-3-notebook FAIL: {loc} notebooks_granted is "
                f"{type(granted).__name__}, expected list"
            )
            continue
        if role == "author" and thematic in granted:
            fails.append(
                f"GATE G-3-notebook FAIL: {loc} role=author but notebooks_granted "
                f"includes thematic id {thematic!r} (I-5 violation)"
            )
        if role == "moderator" and granted:
            fails.append(
                f"GATE G-3-notebook FAIL: {loc} role=moderator but notebooks_granted "
                f"is non-empty {granted!r} (I-5: moderator holds no notebook)"
            )
    return fails


def check_g3_mod_content(state: dict) -> list[str]:
    """NEW. moderator_assessments entries must have non-empty content, non-null round,
    valid lens_id, non-empty timestamp_iso."""
    fails: list[str] = []
    for i, entry in enumerate(state.get("moderator_assessments") or []):
        if not isinstance(entry, dict):
            fails.append(
                f"GATE G-3-mod-content FAIL: moderator_assessments[{i}] is "
                f"{type(entry).__name__}, expected object"
            )
            continue
        loc = f"moderator_assessments[{i}]"
        lid = entry.get("lens_id")
        if not isinstance(lid, int) or not (0 <= lid <= 8):
            fails.append(
                f"GATE G-3-mod-content FAIL: {loc} lens_id={lid!r} must be int in 0..8"
            )
        r = entry.get("round")
        if not isinstance(r, int) or r < 1:
            fails.append(
                f"GATE G-3-mod-content FAIL: {loc} round={r!r} must be int >= 1 "
                f"(empty stubs with round=null are rejected)"
            )
        if not _nonempty_str(entry.get("content")):
            fails.append(
                f"GATE G-3-mod-content FAIL: {loc} content is empty/missing "
                f"(empty stubs are rejected)"
            )
        if not _nonempty_str(entry.get("timestamp_iso")):
            fails.append(
                f"GATE G-3-mod-content FAIL: {loc} timestamp_iso is empty/missing"
            )
    return fails


def check_g4a(state: dict) -> list[str]:
    """Synthesis schema + recommendation enum."""
    fails: list[str] = []
    syn = state.get("synthesis")
    if syn is None:
        if state.get("run_status") == "completed":
            fails.append("GATE G-4a FAIL: state.synthesis is null on a completed run")
        return fails
    if not isinstance(syn, dict):
        fails.append(f"GATE G-4a FAIL: state.synthesis is {type(syn).__name__}, expected object")
        return fails
    for key in REQUIRED_SYNTHESIS_KEYS:
        if key not in syn:
            fails.append(f"GATE G-4a FAIL: state.synthesis missing key '{key}'")
    if "tldr_verdict" in syn:
        fails.append(
            "GATE G-4a FAIL: state.synthesis contains deprecated 'tldr_verdict' — "
            "use 'verdict' instead (the {{VERDICT}} template placeholder reads from .verdict)"
        )
    rec = syn.get("recommendation")
    if rec is not None and rec not in RECOMMENDATION_ENUM:
        fails.append(
            f"GATE G-4a FAIL: recommendation={rec!r} not in enum {sorted(RECOMMENDATION_ENUM)}"
        )
    tkq = syn.get("top_killer_questions")
    if tkq is not None and not isinstance(tkq, list):
        fails.append(
            f"GATE G-4a FAIL: top_killer_questions is {type(tkq).__name__}, expected list "
            f"(pointer strings like 'See briefing …' are not valid)"
        )
    sr = syn.get("subproject_relevance")
    if sr is not None and not isinstance(sr, dict):
        fails.append(
            f"GATE G-4a FAIL: subproject_relevance is {type(sr).__name__}, expected object"
        )
    return fails


def check_g5a(state: dict) -> list[str]:
    """Phase 5 → Phase 6 disposition check."""
    fails: list[str] = []
    if state.get("run_status") != "completed":
        return fails  # aborted runs are allowed to skip Phase 6
    notebooks = state.get("notebooks") or {}
    disposable = notebooks.get("disposable") or {}
    disp = disposable.get("disposition")
    valid = {"deleted", "kept", "promoted"}
    if disp not in valid:
        fails.append(
            f"GATE G-5a FAIL: notebooks.disposable.disposition={disp!r} not in {sorted(valid)} "
            f"on a completed run (Phase 6 cleanup did not run)"
        )
    # Note: v1 had a legacy top-level state.disposition field. Schema v2 removed it.
    # Only notebooks.disposable.disposition is authoritative.
    return fails


# Legacy group-partial and merge-consistency check functions (check_partial_group,
# check_merge_consistency) were removed in the 2026-04-24 flat-dispatch refactor.
# Nested subagent dispatch is architecturally impossible in Claude Code, so the 3×3
# group architecture they validated cannot exist. See
# quality_reports/plans/2026-04-24_paper-stress-test-flat-dispatch.md.


def validate(state_path: Path) -> int:
    try:
        state = json.loads(state_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FATAL: cannot load {state_path}: {exc}", file=sys.stderr)
        return 2
    all_fails: list[str] = []
    for check in (
        check_g3a,
        check_g3b,
        check_g3c,
        check_g3_schema,
        check_g3_model,
        check_g3_notebook,
        check_g3_mod_content,
        check_g4a,
        check_g5a,
    ):
        all_fails.extend(check(state))
    if all_fails:
        print(f"\n{state_path.name}: {len(all_fails)} gate violation(s)\n")
        for line in all_fails:
            print(f"  {line}")
        print()
        return 1
    print(f"{state_path.name}: OK (all gates pass)")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2:
        return validate(Path(argv[1]))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
