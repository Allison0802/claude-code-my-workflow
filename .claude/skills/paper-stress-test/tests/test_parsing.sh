#!/usr/bin/env bash
# Parsing-contract fixture tests for paper-stress-test skill (T1.6).
#
# Applies each of the seven Parsing-contract regexes from SKILL.md (L59-L165)
# to its fixture(s) and asserts the expected capture succeeds. Uses python3
# with re.DOTALL/re.MULTILINE per the SKILL.md preamble because the regexes
# rely on PCRE features (\d, \Z, lookaheads, DOTALL) not available in
# POSIX-ERE grep on macOS.
#
# Exit code 0 iff all 7 patterns PASS.

set -euo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
export FIXTURES_DIR

python3 - <<'PY'
import os, re, sys

FIX = os.environ["FIXTURES_DIR"]
fails = []

def read(name):
    with open(os.path.join(FIX, name)) as f:
        return f.read()

def split_variants(text):
    return [v.strip() for v in text.split('---FIXTURE_SEPARATOR---')]

def check(label, pattern, text, flags, expect_substring=None):
    m = re.search(pattern, text, flags)
    if not m:
        fails.append(f"{label}: NO MATCH")
        return None
    if expect_substring is not None:
        cap = m.group(1) if m.groups() else m.group(0)
        if expect_substring not in cap:
            fails.append(f"{label}: capture {cap!r} missing substring {expect_substring!r}")
            return None
    return m

DOTALL_MULTI = re.DOTALL | re.MULTILINE
MULTI = re.MULTILINE

# ---------------- Pattern 1: Primary question ----------------
t1 = read("01_primary_question.txt")
check("P1 primary question",
      r"^QUESTION:[ \t]*(.+?)(?=\n[A-Z_]+:|\Z)",
      t1, DOTALL_MULTI, "SUTVA")

# ---------------- Pattern 2: Judgment + decision (two variants) ----------------
t2 = read("02_judgment_decision.txt")
v_followup, v_final = split_variants(t2)

check("P2a JUDGMENT handwaved",
      r"^JUDGMENT:[ \t]*(cited|evaded|handwaved|conceded)[ \t]*$",
      v_followup, MULTI, "handwaved")
check("P2a REASONING",
      r"^REASONING:[ \t]*(.+?)(?=\n[A-Z_]+:|\Z)",
      v_followup, DOTALL_MULTI, "Table 3")
check("P2a NEXT=FOLLOWUP",
      r"^NEXT:[ \t]*(FOLLOWUP|FINAL)[ \t]*$",
      v_followup, MULTI, "FOLLOWUP")
check("P2a FOLLOWUP body",
      r"^FOLLOWUP:[ \t]*(.+?)(?=\n[A-Z_]+:|\Z)",
      v_followup, DOTALL_MULTI, "variance inflation")

check("P2b JUDGMENT cited",
      r"^JUDGMENT:[ \t]*(cited|evaded|handwaved|conceded)[ \t]*$",
      v_final, MULTI, "cited")
check("P2b NEXT=FINAL",
      r"^NEXT:[ \t]*(FOLLOWUP|FINAL)[ \t]*$",
      v_final, MULTI, "FINAL")
check("P2b SEVERITY clean",
      r"^SEVERITY:[ \t]*(critical|major|minor|clean)[ \t]*$",
      v_final, MULTI, "clean")

# ---------------- Pattern 3: Lens 7 initial ----------------
t3 = read("03_lens7_initial.txt")
check("P3 QUESTION",
      r"^QUESTION:[ \t]*(.+?)(?=\n[A-Z_]+:|\Z)",
      t3, DOTALL_MULTI, "Overgaard")
check("P3 THEMATIC_QUERY",
      r"^THEMATIC_QUERY:[ \t]*(.+?)(?=\n[A-Z_]+:|\Z)",
      t3, DOTALL_MULTI, "pseudo-observation")

# ---------------- Pattern 4: Lens 7 confrontation (two variants) ----------------
t4 = read("04_lens7_confrontation.txt")
v_conf, v_cited = split_variants(t4)

check("P4a CONFRONTATION",
      r"^CONFRONTATION:[ \t]*(.+?)(?=\n[A-Z_]+:|\Z)",
      v_conf, DOTALL_MULTI, "Overgaard")

# Pattern 4 early-close path: JUDGMENT cited AND SEVERITY clean must both be present.
m_judge = re.search(r"^JUDGMENT:[ \t]*cited[ \t]*$", v_cited, MULTI)
m_sev   = re.search(r"^SEVERITY:[ \t]*clean[ \t]*$", v_cited, MULTI)
if not (m_judge and m_sev):
    fails.append("P4b JUDGMENT cited + SEVERITY clean: one or both did not match")

# ---------------- Pattern 5: Author answer (two variants) ----------------
t5 = read("05_author_answer.txt")
v_ans, v_none = split_variants(t5)

check("P5a ANSWER",
      r"^ANSWER:[ \t]*(.+?)(?=\nCITATIONS:)",
      v_ans, DOTALL_MULTI, "Section 4.2")
# Citation block: everything from 'CITATIONS:' to end of variant.
m_cit = re.search(r"^CITATIONS:[ \t]*(.*)\Z", v_ans, DOTALL_MULTI)
if not m_cit or "randomization" not in m_cit.group(1):
    fails.append("P5a CITATIONS block: did not capture randomization evidence")

# Fixture 5b: ANSWER must start with the 'the paper does not address this' phrase
m_ans_b = re.search(r"^ANSWER:[ \t]*(.+?)(?=\nCITATIONS:)", v_none, DOTALL_MULTI)
if not m_ans_b:
    fails.append("P5b ANSWER: NO MATCH")
elif not m_ans_b.group(1).strip().startswith("the paper does not address this"):
    fails.append(f"P5b ANSWER: did not start with 'the paper does not address this' (got {m_ans_b.group(1)[:60]!r})")

# Fixture 5b CITATIONS: none
if not re.search(r"^CITATIONS:[ \t]*none[ \t]*$", v_none, MULTI):
    fails.append("P5b CITATIONS: none — did not match")

# ---------------- Pattern 6: Classification triple ----------------
t6 = read("06_classification_triple.txt")
check("P6 detected_type",
      r"^(?:##|\*\*)\s*Classification\s*(?:\*\*)?\s*\n\s*([a-z][a-zA-Z-]+)\b",
      t6, MULTI, "new-estimator")
check("P6 headline_claim",
      r"^(?:##|\*\*)\s*Headline contribution\s*(?:\*\*)?\s*\n\s*\"?([^\"\n]+)\"?",
      t6, MULTI, "jackknife")
check("P6 novelty_claims block",
      r"^(?:##|\*\*)\s*Novelty claims\s*(?:\*\*)?\s*\n((?:\s*\d+\.\s+.+\n?)+)",
      t6, MULTI, "Theorem 1")

# ---------------- Pattern 7: novelty-check ----------------
t7 = read("07_novelty_check.txt")
check("P7 overall_score",
      r"Score:[ \t]*(\d+)/10",
      t7, MULTI, "7")
check("P7 recommendation",
      r"Recommendation:[ \t]*(PROCEED WITH CAUTION|PROCEED|ABANDON)",
      t7, MULTI, "PROCEED WITH CAUTION")
check("P7 key_differentiator",
      r"Key differentiator:[ \t]*(.+?)(?=\n-|\n##|\Z)",
      t7, DOTALL_MULTI, "jackknife")
check("P7 closest_prior_work table",
      r"Closest Prior Work\s*\n((?:\|.+\|\n)+)",
      t7, MULTI, "Overgaard")

# ---------------- Summary ----------------
if fails:
    print(f"test_parsing.sh: FAIL ({len(fails)} issue(s))", file=sys.stderr)
    for f in fails:
        print("  - " + f, file=sys.stderr)
    sys.exit(1)

print("test_parsing.sh: all 7 patterns PASS")
PY
