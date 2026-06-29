#!/usr/bin/env bash
# Verification plan step 3 — tee stdout/stderr of TZ=UTC just test-swift only.
# Writes: ${SCRATCH}/test-swift.log (overwrite)
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-0858149818ca/implementer}"
TEST_LOG="${SCRATCH}/test-swift.log"

mkdir -p "$SCRATCH"

set +e
TZ=UTC just test-swift 2>&1 | tee "$TEST_LOG"
TEST_EXIT=${PIPESTATUS[0]}
set -e

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "capture-test-swift-evidence: just test-swift failed (exit ${TEST_EXIT})" >&2
  exit "$TEST_EXIT"
fi

echo "Wrote $TEST_LOG"