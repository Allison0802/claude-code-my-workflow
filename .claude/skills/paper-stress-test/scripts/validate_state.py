#!/usr/bin/env python3
"""
Post-hoc validator for paper-stress-test state.json files.

Checks GATE invariants G-3a, G-3b, G-3c, G-4a, G-5a documented in SKILL.md.
Exits 0 if well-formed, 1 otherwise. Prints one line per violation to stdout.

Usage:
    python3 validate_state.py <path-to-state.json>

The skill does NOT invoke this at runtime (runtime gates enforce equivalents);
this exists for (a) post-hoc triage of legacy runs, (b) regression-testing
proposed SKILL.md edits against known failed runs (e.g. Lin 2021, Loe 2025).
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
        if state.get("spawn_count", 0) < 2 * depth_sum:
            fails.append(
                f"GATE G-3c FAIL: spawn_count={state.get('spawn_count', 0)} < "
                f"2 * sum(depth)={2 * depth_sum} (Reviewer+Author per depth unit is the floor)"
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


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    return validate(Path(argv[1]))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
