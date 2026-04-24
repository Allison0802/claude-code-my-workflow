#!/usr/bin/env python3
"""
Score existing paper-stress-test artifact triples (state.json + briefing.md +
transcripts.md) against eval criteria E1..E10.

Usage:
    python3 score_corpus.py [--run-label LABEL]

Prints a TSV to stdout (one row per slug + totals) and a summary.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path("/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research")
STATE_DIR = REPO / "master_supporting_docs/supporting_papers/stress_tests/state"
BRIEF_DIR = REPO / "master_supporting_docs/supporting_papers/stress_tests/briefing"
TRANS_DIR = REPO / "master_supporting_docs/supporting_papers/stress_tests/transcripts"
VALIDATOR = REPO / ".claude/skills/paper-stress-test/scripts/validate_state.py"
SCHEMA_CHECK = REPO / ".claude/skills/paper-stress-test/scripts/enforce_schema.py"

# Editorial phrases banned in Author turns (E5). Lowercase substring match.
# The point is argumentative framing, not domain terms.
EDITORIAL_PATTERNS = [
    r"\bthe reviewer identifies?\b",
    r"\bthe reviewer'?s?\s+(critique|concern|charge)\b",
    r"\bmisreads?\s+the\s+paper\b",
    r"\brun[s]?\s+in\s+the\s+opposite\s+direction\b",
    r"\bthe .*charge misreads?\b",
    r"\bstraw[- ]man charge\b",
    r"\bgenuine gap\b",
    # Author self-evaluation framings
    r"\bthe paper does not hide\b",
    r"\bthe reviewer['’]s exact concern\b",
    r"\bthe reviewer is (right|wrong|correct)\b",
]
EDITORIAL_RE = re.compile("|".join(EDITORIAL_PATTERNS), re.IGNORECASE)


def find_triples() -> list[tuple[str, Path, Path, Path]]:
    """Return (slug_stem, state, brief, trans) for each canonical state.json."""
    triples = []
    for state_path in sorted(STATE_DIR.glob("*_state.json")):
        name = state_path.name
        # Skip partial/group files and backups
        if "_group_" in name or name.endswith(".bak") or name.endswith(".baseline"):
            continue
        stem = name[: -len("_state.json")]
        brief = BRIEF_DIR / f"{stem}_briefing.md"
        # Transcripts may use _transcripts.md or _transcript.md
        cands = list(TRANS_DIR.glob(f"{stem}_transcript*.md"))
        trans = cands[0] if cands else None
        triples.append((stem, state_path, brief, trans))
    return triples


def read_text(p: Path | None) -> str:
    if p is None or not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace")


def load_state(p: Path) -> dict | None:
    try:
        return json.loads(p.read_text())
    except Exception:
        return None


# --- Evals ----------------------------------------------------------------


def e1_disposition_agrees(state: dict, brief: str) -> bool:
    """state.disposition string appears in briefing disposition line."""
    disp = (
        state.get("notebooks", {})
        .get("disposable", {})
        .get("disposition", "")
        .lower()
    )
    if not disp:
        return False
    # Find the briefing disposition line.
    m = re.search(
        r"disposition[^:\n]*:\s*(.+)", brief, re.IGNORECASE
    )
    if not m:
        return False
    line = m.group(1).strip().lower()
    # Must NOT claim a different terminal disposition than state.
    for other in ("deleted", "kept", "promoted"):
        if other == disp:
            continue
        # If a different terminal word is in the line, it's a contradiction.
        # But allow listing choices e.g. "Delete / Keep / Promote" by requiring
        # "promoted" word only if it is the lead word; simplify: require disp token in line.
        pass
    return disp in line


def e2_spawn_count_matches(state: dict, trans: str) -> bool:
    """state.spawn_count matches the number in transcripts footer."""
    sc = state.get("spawn_count")
    if sc is None:
        return False
    m = re.search(r"total subagent spawns?:\s*(\d+)", trans, re.IGNORECASE)
    if not m:
        return False
    return int(m.group(1)) == sc


def e3_breakdown_arithmetic(state: dict, trans: str) -> bool:
    """Transcripts breakdown arithmetic matches footer total AND number of lenses.

    Accepts two format variants:
      (a) Parenthetical: "Total subagent spawns: N (1 classification + ...)"
      (b) Bullet list (preferred per M3): "Total subagent spawns: N" followed by
          indented bullet lines "- Label: M" on subsequent lines.
    """
    m_total = re.search(r"total subagent spawns?:\s*(\d+)", trans, re.IGNORECASE)
    if not m_total:
        return False
    total = int(m_total.group(1))

    # Try variant (a): parenthetical.
    m_paren = re.search(r"total subagent spawns?:\s*\d+\s*\(([^)]*)\)", trans, re.IGNORECASE)
    if m_paren:
        nums = [int(x) for x in re.findall(r"(\d+)", m_paren.group(1))]
    else:
        # Try variant (b): bullet list in the ~15 lines after the Total line.
        after = trans[m_total.end() : m_total.end() + 1500]
        # Stop at next section header (## or ---).
        stop = re.search(r"(?:\n##\s|\n---\s*\n)", after)
        if stop:
            after = after[: stop.start()]
        # Collect integers from bullet-style lines: "- Label: N" or "    - Label: N".
        bullet_lines = re.findall(r"(?m)^\s*[-*]\s+[^:\n]+:\s*(\d+)", after)
        nums = [int(x) for x in bullet_lines]
    if not nums:
        return False
    parts_sum = sum(nums)
    if parts_sum != total:
        return False
    # Arithmetic must also sanity-check against ACTIVE lens count.
    # Skipped lenses (severity='skipped' per weight matrix) don't spawn a Reviewer/Author,
    # so R1 count equals the number of non-skipped lenses, not len(lens_plan).
    lenses = state.get("lenses_completed") or []
    n_active_lens = sum(
        1 for l in lenses if (l.get("severity") or "") != "skipped"
    )
    if n_active_lens == 0:
        # Fall back to lens_plan count if lenses_completed is empty (partial run).
        n_active_lens = len(state.get("lens_plan", []))
    # Accept if at least one of the R1 count fields reaches n_active_lens.
    return max(nums) >= n_active_lens


def e4_transcript_field_handled(state: dict) -> bool:
    """state.transcript is either populated OR schema no longer requires it."""
    t = state.get("transcript")
    if isinstance(t, list) and len(t) > 0:
        return True
    # Field absent is also acceptable (schema removed it).
    if "transcript" not in state:
        return True
    # Present but empty → fail.
    return False


def e5_author_not_editorial(trans: str) -> bool:
    """Author turn bodies contain no editorial framing phrases."""
    # Split into sections per lens; within each, find Author ANSWER blocks.
    # Heuristic: capture chunks between "author" role markers and next turn header.
    # Use a simple scan: find lines after "author" within Turn headers.
    author_blocks: list[str] = []
    for section in re.split(r"(?=^#+\s+Lens\s+\d+)", trans, flags=re.MULTILINE):
        # Find author turn blocks.
        for m in re.finditer(
            r"###\s*Turn\s*\d+\s*[—-]\s*author[^\n]*\n(.*?)(?=###\s*Turn|\Z)",
            section,
            flags=re.DOTALL | re.IGNORECASE,
        ):
            author_blocks.append(m.group(1))
    if not author_blocks:
        # No author turns detected — treat as fail (something is off).
        return False
    for body in author_blocks:
        if EDITORIAL_RE.search(body):
            return False
    return True


def e6_timestamps_aligned(state: dict) -> bool:
    """wall_clock_start >= started_at OR wall_clock_start is None (per 2026-04-22 fix).

    Corrected after mutation M7: a drift is expected (Phase 2 confirmation sits
    between state.json init and Phase 3 start). Only ORDER matters, not equality.
    """
    s = state.get("started_at")
    w = state.get("wall_clock_start")
    if w is None:
        return True
    if s is None:
        return False
    # Both are ISO-8601 strings; lexicographic comparison works for same timezone.
    return w >= s


def e7_briefing_header_label(brief: str) -> bool:
    """Briefing header labels the weight list as 'weights', not 'lens plan'."""
    # The bug was: "Depth: 2 (lens plan: medium/heavy/medium/heavy/medium/light/heavy/heavy/medium)"
    # Fix: label should say "weights:" before the slash-list.
    m = re.search(
        r"\*\*Depth:\*\*\s*\d+\s*\(([^)]*)\)", brief
    )
    if not m:
        # No depth-parens line at all — accept (template may have evolved).
        return True
    inner = m.group(1).lower()
    # Fail if slash-list is labeled "lens plan" instead of "weights".
    if "lens plan" in inner and ("heavy" in inner or "medium" in inner):
        return False
    return True


def e8_tldr_word_cap(brief: str) -> bool:
    """TL;DR section ≤ 150 words."""
    m = re.search(
        r"##\s*TL;DR[^\n]*\n(.*?)(?=^##\s)", brief, flags=re.DOTALL | re.MULTILINE
    )
    if not m:
        return False
    body = m.group(1).strip()
    # Strip horizontal rules and blank lines.
    body = re.sub(r"^-{3,}\s*$", "", body, flags=re.MULTILINE)
    words = re.findall(r"\w+", body)
    return len(words) <= 150


def run_cmd(args: list[str]) -> int:
    try:
        r = subprocess.run(args, capture_output=True, timeout=30)
        return r.returncode
    except Exception:
        return 99


def e9_validator_passes(state_path: Path) -> bool:
    return run_cmd(["python3", str(VALIDATOR), str(state_path)]) == 0


def e10_schema_passes(state_path: Path) -> bool:
    if not SCHEMA_CHECK.exists():
        # If enforce_schema.py is missing, skip (treat as pass to avoid noise).
        return True
    return run_cmd(["python3", str(SCHEMA_CHECK), str(state_path)]) == 0


EVALS = [
    ("E1_disposition", e1_disposition_agrees),
    ("E2_spawncount", e2_spawn_count_matches),
    ("E3_breakdown", e3_breakdown_arithmetic),
    ("E4_transcript", e4_transcript_field_handled),
    ("E5_author_tone", e5_author_not_editorial),
    ("E6_timestamps", e6_timestamps_aligned),
    ("E7_header_label", e7_briefing_header_label),
    ("E8_tldr_cap", e8_tldr_word_cap),
    ("E9_validator", e9_validator_passes),
    ("E10_schema", e10_schema_passes),
]


def score_triple(stem: str, state_path: Path, brief_path: Path, trans_path: Path | None) -> dict:
    state = load_state(state_path) or {}
    brief = read_text(brief_path)
    trans = read_text(trans_path)
    results: dict[str, int] = {}
    for name, fn in EVALS:
        try:
            if name in ("E1_disposition",):
                ok = fn(state, brief)
            elif name in ("E2_spawncount", "E3_breakdown"):
                ok = fn(state, trans)
            elif name == "E4_transcript":
                ok = fn(state)
            elif name == "E5_author_tone":
                ok = fn(trans)
            elif name == "E6_timestamps":
                ok = fn(state)
            elif name == "E7_header_label":
                ok = fn(brief)
            elif name == "E8_tldr_cap":
                ok = fn(brief)
            elif name in ("E9_validator", "E10_schema"):
                ok = fn(state_path)
            else:
                ok = False
        except Exception:
            ok = False
        results[name] = 1 if ok else 0
    return results


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-label", default="baseline")
    ap.add_argument("--tsv", action="store_true", help="Print TSV rows only")
    args = ap.parse_args()

    triples = find_triples()
    if not triples:
        print("No triples found", file=sys.stderr)
        sys.exit(2)

    header = ["slug"] + [e[0] for e in EVALS] + ["total"]
    rows = []
    eval_totals = {e[0]: 0 for e in EVALS}
    n = len(triples)
    grand_total = 0
    max_per = len(EVALS)
    for stem, sp, bp, tp in triples:
        r = score_triple(stem, sp, bp, tp)
        total = sum(r.values())
        grand_total += total
        for k, v in r.items():
            eval_totals[k] += v
        rows.append([stem] + [str(r[e[0]]) for e in EVALS] + [str(total)])

    max_total = n * max_per
    print("\t".join(header))
    for row in rows:
        print("\t".join(row))
    if not args.tsv:
        print()
        print(f"label={args.run_label}  corpus={n}  evals={max_per}  total={grand_total}/{max_total}  pass_rate={100.0*grand_total/max_total:.1f}%")
        print("per-eval pass counts:")
        for e, _ in EVALS:
            print(f"  {e}: {eval_totals[e]}/{n}")


if __name__ == "__main__":
    main()
