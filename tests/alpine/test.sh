#!/bin/sh
# Tests for the alpine container image.
# This script is mounted into the container and executed by the CI workflow.
# Exit non-zero to fail the test.

set -e

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  FAIL: $1"; FAIL=$(( FAIL + 1 )); }

echo "=== Alpine container tests ==="

# ── OS identity ───────────────────────────────────────────────────
echo ""
echo "-- OS identity"

if grep -qi 'alpine' /etc/os-release 2>/dev/null; then
  pass "Running Alpine Linux"
else
  fail "Expected Alpine Linux, got: $(cat /etc/os-release 2>/dev/null | head -1)"
fi

# ── Essential commands ────────────────────────────────────────────
echo ""
echo "-- Essential commands"

for cmd in sh echo cat ls grep awk sed find; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "Command available: $cmd"
  else
    fail "Command missing: $cmd"
  fi
done

# ── Filesystem basics ─────────────────────────────────────────────
echo ""
echo "-- Filesystem basics"

for dir in /bin /etc /tmp /usr; do
  if [ -d "$dir" ]; then
    pass "Directory exists: $dir"
  else
    fail "Directory missing: $dir"
  fi
done

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
