#!/bin/sh
# Shared tests for all developer container images.
# Verifies developer-image invariants common to the entire developer group.
# This script is mounted into the container and executed by the CI workflow.
# Exit non-zero to fail the test.

set -e

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  FAIL: $1"; FAIL=$(( FAIL + 1 )); }

echo "=== Developer base tests ==="

# ── User identity ─────────────────────────────────────────────────
echo ""
echo "-- User identity"

if [ "$(id -u)" != "0" ]; then
  pass "Container is not running as root (uid=$(id -u), user=$(id -un))"
else
  fail "Container is running as root — developer images must use a non-root user"
fi

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
