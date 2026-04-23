#!/usr/bin/env bash
# Verifies the most recent smoke-test run against the pass predicate.
# Exit 0 = PASS; exit 1 = FAIL (with reasons printed).
set -u

STRESS_DIR="/Users/alison/Library/CloudStorage/OneDrive-UniversityofNorthCarolinaatChapelHill/Research/master_supporting_docs/supporting_papers/stress_tests"

# Find the most recent state file matching the Wager/Athey slug prefix
STATE_FILE=$(ls -t "${STRESS_DIR}/state/"wager_2018_*_state.json 2>/dev/null | head -1)
if [ -z "$STATE_FILE" ]; then
  echo "FAIL: no Wager/Athey state file found in ${STRESS_DIR}/state/"
  exit 1
fi

SLUG=$(basename "$STATE_FILE" _state.json)
BRIEFING_FILE="${STRESS_DIR}/briefing/${SLUG}_briefing.md"
TRANSCRIPT_FILE="${STRESS_DIR}/transcripts/${SLUG}_transcripts.md"

echo "Verifying run: $SLUG"
FAILURES=0

fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES+1)); }
pass() { echo "  PASS: $1"; }

# 1. state.json parses
jq -e . "$STATE_FILE" >/dev/null 2>&1 \
  && pass "state.json parses" \
  || fail "state.json is not valid JSON"

# 2-4. run_status, type, classification_source
RUN_STATUS=$(jq -r '.run_status' "$STATE_FILE")
[ "$RUN_STATUS" = "completed" ] && pass "run_status=completed" || fail "run_status=$RUN_STATUS (expected completed)"

TYPE=$(jq -r '.detected_type' "$STATE_FILE")
case "$TYPE" in
  predictive-ML|new-estimator|applied-empirical|causal-inference|review-survey)
    pass "detected_type=$TYPE (valid enum)"
    ;;
  *)
    fail "detected_type=$TYPE (not in enum)"
    ;;
esac

if [ "$TYPE" = "applied-empirical" ]; then
  SRC=$(jq -r '.classification_source // "reviewer"' "$STATE_FILE")
  [ "$SRC" = "user_override" ] \
    && pass "applied-empirical came from user_override (not silent default)" \
    || fail "applied-empirical was silently set (classification_source=$SRC) — BAD"
fi

# 5-7. lens plan + completion counts
PLAN_LEN=$(jq '.lens_plan | length' "$STATE_FILE")
[ "$PLAN_LEN" = "9" ] && pass "lens_plan has 9 entries" || fail "lens_plan has $PLAN_LEN entries"

ACTIVE=$(jq '[.lens_plan[] | select(.depth > 0)] | length' "$STATE_FILE")
COMPLETED=$(jq '.lenses_completed | length' "$STATE_FILE")
[ "$ACTIVE" = "$COMPLETED" ] && pass "lenses_completed ($COMPLETED) matches active ($ACTIVE)" \
  || fail "lenses_completed=$COMPLETED but active=$ACTIVE"

# 8-9. severity enum + errored count
BAD=$(jq '[.lenses_completed[] | select(.severity as $s | ["critical","major","minor","clean","errored"] | index($s) == null)] | length' "$STATE_FILE")
[ "$BAD" = "0" ] && pass "all severities in enum" || fail "$BAD lenses with out-of-enum severity"

ERRORED=$(jq '[.lenses_completed[] | select(.severity == "errored")] | length' "$STATE_FILE")
[ "$ERRORED" -le "1" ] && pass "errored count=$ERRORED (≤1)" || fail "errored count=$ERRORED (>1)"

# 10. recommendation enum
REC=$(jq -r '.synthesis.recommendation' "$STATE_FILE")
case "$REC" in
  cite|build-on|flag|skip)
    pass "recommendation=$REC"
    ;;
  *)
    fail "recommendation=$REC (not in enum)"
    ;;
esac

# 11. no unsubstituted placeholders in briefing
if [ -f "$BRIEFING_FILE" ]; then
  PLACEHOLDERS=$(grep -Eo '\{\{[A-Z_]+\}\}' "$BRIEFING_FILE" | wc -l | tr -d ' ')
  [ "$PLACEHOLDERS" = "0" ] && pass "briefing has 0 unsubstituted placeholders" \
    || fail "briefing has $PLACEHOLDERS unsubstituted placeholders"
else
  fail "briefing file missing: $BRIEFING_FILE"
fi

# 12. 11 H2 headers
if [ -f "$BRIEFING_FILE" ]; then
  H2_COUNT=$(grep -c '^## ' "$BRIEFING_FILE")
  [ "$H2_COUNT" -ge "10" ] && pass "briefing has $H2_COUNT H2 headers (≥10)" \
    || fail "briefing has only $H2_COUNT H2 headers (expected ≥10; 11 is ideal)"
fi

# 13. transcripts exists and ≥2KB
if [ -f "$TRANSCRIPT_FILE" ]; then
  SIZE=$(wc -c < "$TRANSCRIPT_FILE" | tr -d ' ')
  [ "$SIZE" -ge "2048" ] && pass "transcripts ${SIZE}B (≥2KB)" \
    || fail "transcripts only ${SIZE}B (<2KB)"
else
  fail "transcripts file missing: $TRANSCRIPT_FILE"
fi

# 14. no .tmp files
TMP_COUNT=$(find "${STRESS_DIR}/briefing" "${STRESS_DIR}/transcripts" "${STRESS_DIR}/state" -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ')
[ "$TMP_COUNT" = "0" ] && pass "no .tmp files left behind" \
  || fail "$TMP_COUNT .tmp files still present"

# 15. disposition finalized
DISP=$(jq -r '.notebooks.disposable.disposition' "$STATE_FILE")
case "$DISP" in
  deleted|kept|promoted)
    pass "disposable disposition=$DISP"
    ;;
  *)
    fail "disposable disposition=$DISP (expected deleted|kept|promoted)"
    ;;
esac

echo
if [ "$FAILURES" = "0" ]; then
  echo "=== SMOKE TEST PASSED ==="
  exit 0
else
  echo "=== SMOKE TEST FAILED: $FAILURES check(s) ==="
  exit 1
fi
