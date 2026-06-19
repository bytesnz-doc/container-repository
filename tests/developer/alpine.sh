#!/bin/sh
# Tests specific to the developer/alpine container image.
# This script is mounted into the container and executed by the CI workflow.
# Exit non-zero to fail the test.

set -e

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  FAIL: $1"; FAIL=$(( FAIL + 1 )); }

echo "=== developer/alpine tests ==="

# ── sudo apk (passwordless) ───────────────────────────────────────
echo ""
echo "-- sudo apk (passwordless)"

if sudo apk --version >/dev/null 2>&1; then
  pass "sudo apk runs without a password prompt"
else
  fail "sudo apk failed (check NOPASSWD sudoers entry for apk)"
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
