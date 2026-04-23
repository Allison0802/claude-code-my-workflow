#!/usr/bin/env python3
"""
Post-hoc validator for paper-stress-test state.json files.

Checks GATE invariants G-3a, G-3b, G-3c, G-4a, G-5a documented in SKILL.md.
Exits 0 if well-formed, 1 otherwise. Prints one line per violation to stdout.

Usage:
    python3 validate_state.py <path-to-state.json>
    python3 validate_state.py --partial-group <path-to-group-N.json>
    python3 validate_state.py --check-merge <state.json> <group_0.json> <group_1.json> <group_2.json>

Modes:
  default: validate a fully-merged state.json against all 5 gates.
  --partial-group: validate a single group partial against G-3a-local and G-3b-local.
  --check-merge: validate that the merged state.json is consistent with the 3 partials
                 (no duplicate lens_ids, all 9 covered when all groups completed, counts match).

The skill does NOT invoke this at runtime (runtime gates enforce equivalents);
this exists for (a) post-hoc triage of legacy runs, (b) regression-testing
proposed SKILL.md edits against known failed runs (e.g. Lin 2021, Loe 2025),
(c) validating group partials in the 3×3 parallel architecture.
Stdlib only; no external dependencies.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


RECOMMENDATION_ENUM = {"cite", "build-on", "flag", "skip"}
SEVERITY_ENUM = {"critical", "major", "minor", "clean", "errored"}
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
        slice_ = lens.get("transcript_slice") or []
        if not isinstance(slice_, list) or len(slice_) < 3:
            fails.append(
                f"GATE G-3a FAIL: lens {lens_id} ({lens.get('name', '?')}) "
                f"transcript_slice length {len(slice_) if isinstance(slice_, list) else 'N/A'} < 3"
            )
        for fld in ("one_line_finding", "author_best_defense", "summary_for_compaction"):
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
        # Parallel 3x3 formula: 3 group-agent dispatches + 2 per depth unit (Reviewer + Author per lens/round).
        # Legacy sequential runs used floor = 2 * depth_sum; parallel floor = 3 + 2 * depth_sum.
        floor_parallel = 3 + 2 * depth_sum
        floor_legacy = 2 * depth_sum
        sc = state.get("spawn_count", 0)
        if sc < floor_legacy:
            fails.append(
                f"GATE G-3c FAIL: spawn_count={sc} < legacy floor 2*sum(depth)={floor_legacy} "
                f"(Reviewer+Author per depth unit is the minimum; a hollow run has 0)"
            )
        elif sc < floor_parallel and state.get("architecture", "parallel") == "parallel":
            fails.append(
                f"GATE G-3c FAIL: spawn_count={sc} < parallel floor 3 + 2*sum(depth)={floor_parallel} "
                f"(3 group-agent dispatches + Reviewer+Author per depth unit). "
                f"If this is a legacy sequential run, set state.architecture='sequential' to skip this check."
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
    if state.get("run_status") == "completed" and transcript_len < slice_total:
        fails.append(
            f"GATE G-3c FAIL: transcript length={transcript_len} < "
            f"sum(transcript_slice lengths)={slice_total}"
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
    top_disp = state.get("disposition")
    if top_disp in {None, "pending"} and state.get("run_status") == "completed":
        fails.append(
            f"GATE G-5a FAIL: top-level state.disposition={top_disp!r} on a completed run "
            f"(Phase 6 cleanup did not run)"
        )
    return fails


def check_partial_group(partial: dict) -> list[str]:
    """Validate a single group partial (G-3a-local + G-3b-local equivalent)."""
    fails: list[str] = []
    gid = partial.get("group_id")
    if gid not in {0, 1, 2}:
        fails.append(f"PARTIAL FAIL: group_id={gid!r} not in {{0, 1, 2}}")
    assigned = partial.get("lens_ids_assigned") or []
    if not isinstance(assigned, list):
        fails.append(f"PARTIAL FAIL: lens_ids_assigned is {type(assigned).__name__}, expected list")
        assigned = []
    records = partial.get("lens_records") or []
    if not isinstance(records, list):
        fails.append(f"PARTIAL FAIL: lens_records is {type(records).__name__}, expected list")
        return fails
    aborted = bool(partial.get("aborted", False))
    if not aborted and len(records) != len(assigned):
        fails.append(
            f"PARTIAL FAIL: group {gid} aborted=false but len(lens_records)={len(records)} "
            f"!= len(lens_ids_assigned)={len(assigned)}"
        )
    # Per-record G-3b-local: reuse check_g3b by wrapping the records as a pseudo-state.
    pseudo_state = {"lenses_completed": records}
    fails.extend(check_g3b(pseudo_state))
    # Transcript slice length per record (G-3a-local equivalent).
    for i, lens in enumerate(records):
        slice_ = lens.get("transcript_slice") or []
        if not isinstance(slice_, list) or len(slice_) < 3:
            lens_id = lens.get("lens_id", f"<index {i}>")
            fails.append(
                f"PARTIAL FAIL: group {gid} lens {lens_id} transcript_slice length "
                f"{len(slice_) if isinstance(slice_, list) else 'N/A'} < 3"
            )
    # Group spawn count sanity.
    gsc = partial.get("group_spawn_count", 0)
    if records and gsc < 2 * len(records):
        fails.append(
            f"PARTIAL FAIL: group {gid} group_spawn_count={gsc} < 2 * len(lens_records)={2 * len(records)} "
            f"(each completed lens requires ≥1 Reviewer + ≥1 Author spawn)"
        )
    return fails


def check_merge_consistency(state: dict, partials: list[dict]) -> list[str]:
    """Validate that the merged state.json is consistent with its 3 source partials."""
    fails: list[str] = []
    if len(partials) != 3:
        fails.append(f"MERGE FAIL: expected 3 partials, got {len(partials)}")
    # Collect lens_ids from partials and state.
    partial_ids: list[int] = []
    for p in partials:
        gid = p.get("group_id")
        for lens in p.get("lens_records") or []:
            lid = lens.get("lens_id")
            if lid is not None:
                partial_ids.append(lid)
    state_ids = [l.get("lens_id") for l in state.get("lenses_completed") or []]
    # No duplicates across partials.
    if len(partial_ids) != len(set(partial_ids)):
        seen: set = set()
        dupes = [x for x in partial_ids if x in seen or seen.add(x)]
        fails.append(f"MERGE FAIL: duplicate lens_ids across partials: {sorted(set(dupes))}")
    # Merged state covers every partial lens_id (and nothing extra).
    if sorted(partial_ids) != sorted(state_ids):
        fails.append(
            f"MERGE FAIL: partial lens_ids {sorted(partial_ids)} != "
            f"state.lenses_completed lens_ids {sorted(state_ids)}"
        )
    # If every partial is complete (not aborted), all 9 lens_ids (0-8) must be present, assuming full depth.
    all_complete = all(not p.get("aborted", False) for p in partials)
    if all_complete:
        # Consider only lens_ids in active plan (depth > 0).
        plan = state.get("lens_plan") or []
        active_ids = sorted(l.get("lens_id") for l in plan if (l.get("depth") or 0) > 0)
        if sorted(state_ids) != active_ids:
            fails.append(
                f"MERGE FAIL: all partials complete but state.lenses_completed lens_ids "
                f"{sorted(state_ids)} != active plan lens_ids {active_ids}"
            )
    # group_spawn_count sum consistency.
    sum_gsc = sum(p.get("group_spawn_count", 0) for p in partials)
    sc = state.get("spawn_count", 0)
    # Expected: state.spawn_count >= sum_gsc + 3 (3 for group-agent dispatches) + any pre-Phase-3 spawns (Phase 2a classification).
    if sc < sum_gsc + 3:
        fails.append(
            f"MERGE FAIL: state.spawn_count={sc} < sum(group_spawn_count)={sum_gsc} + 3 (group dispatches). "
            f"Moderator folded counts incorrectly."
        )
    return fails


def validate(state_path: Path) -> int:
    try:
        state = json.loads(state_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FATAL: cannot load {state_path}: {exc}", file=sys.stderr)
        return 2
    all_fails: list[str] = []
    for check in (check_g3a, check_g3b, check_g3c, check_g4a, check_g5a):
        all_fails.extend(check(state))
    if all_fails:
        print(f"\n{state_path.name}: {len(all_fails)} gate violation(s)\n")
        for line in all_fails:
            print(f"  {line}")
        print()
        return 1
    print(f"{state_path.name}: OK (all gates pass)")
    return 0


def validate_partial(partial_path: Path) -> int:
    try:
        partial = json.loads(partial_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FATAL: cannot load {partial_path}: {exc}", file=sys.stderr)
        return 2
    fails = check_partial_group(partial)
    if fails:
        print(f"\n{partial_path.name}: {len(fails)} partial-group violation(s)\n")
        for line in fails:
            print(f"  {line}")
        print()
        return 1
    print(f"{partial_path.name}: OK (partial group gates pass)")
    return 0


def validate_merge(state_path: Path, partial_paths: list[Path]) -> int:
    try:
        state = json.loads(state_path.read_text())
        partials = [json.loads(p.read_text()) for p in partial_paths]
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FATAL: cannot load inputs: {exc}", file=sys.stderr)
        return 2
    fails = check_merge_consistency(state, partials)
    if fails:
        print(f"\nmerge check ({state_path.name} vs {len(partials)} partials): {len(fails)} violation(s)\n")
        for line in fails:
            print(f"  {line}")
        print()
        return 1
    print(f"merge check OK: {state_path.name} consistent with {len(partials)} partials")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2:
        return validate(Path(argv[1]))
    if len(argv) == 3 and argv[1] == "--partial-group":
        return validate_partial(Path(argv[2]))
    if len(argv) == 6 and argv[1] == "--check-merge":
        return validate_merge(Path(argv[2]), [Path(p) for p in argv[3:6]])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
