#!/usr/bin/env python3
"""
Strict JSON Schema validator for paper-stress-test state.json files.

Companion to validate_state.py. Where validate_state.py enforces
content-level invariants (hollow-run, spawn counts, I-5, etc.),
this script enforces pure shape against schema/state.schema.json.

Requires the `jsonschema` package. Installed in user site on Alison's box:
    pip3 install --user jsonschema

Usage:
    python3 enforce_schema.py <path-to-state.json>

Exits 0 if the file matches the schema, 1 otherwise. Prints every violation.

Schema lives at:
    <skill_dir>/schema/state.schema.json

Known limitation: grandfathered v1 files (schema_version != "2") are
flagged rather than excluded — the audit output is part of the point.
Run validate_state.py if you want content gates on a v1 file.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    state_path = Path(argv[1])
    skill_dir = Path(__file__).resolve().parent.parent
    schema_path = skill_dir / "schema" / "state.schema.json"

    try:
        from jsonschema import Draft7Validator
    except ImportError:
        print(
            "FATAL: jsonschema package is not installed. Install with:\n"
            "    pip3 install --user jsonschema",
            file=sys.stderr,
        )
        return 2

    try:
        state = json.loads(state_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FATAL: cannot load {state_path}: {exc}", file=sys.stderr)
        return 2

    try:
        schema = json.loads(schema_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FATAL: cannot load schema at {schema_path}: {exc}", file=sys.stderr)
        return 2

    Draft7Validator.check_schema(schema)
    validator = Draft7Validator(schema)
    errors = sorted(validator.iter_errors(state), key=lambda e: list(e.absolute_path))

    if not errors:
        print(f"{state_path.name}: schema OK (schema_version={state.get('schema_version')!r})")
        return 0

    print(f"\n{state_path.name}: {len(errors)} schema violation(s)\n")
    for err in errors:
        path = "/".join(str(p) for p in err.absolute_path) or "<root>"
        # Trim gigantic value dumps.
        msg = err.message
        if len(msg) > 200:
            msg = msg[:200] + "..."
        print(f"  [{path}] {msg}")
    print()
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
