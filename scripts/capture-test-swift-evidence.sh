#!/usr/bin/env bash
# Issue #167 DoD evidence capture — verification plan steps 3 and 5.
# Writes: ${SCRATCH}/test-swift.log, ${SCRATCH}/plans-specs-reviewer-evidence.txt
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-0858149818ca/implementer}"
TEST_LOG="${SCRATCH}/test-swift.log"
EVIDENCE="${SCRATCH}/plans-specs-reviewer-evidence.txt"
REVIEW_PATH="docs/reviews/feat-menu-bar-native-menu/codex.md"

mkdir -p "$SCRATCH"

set +e
TZ=UTC just test-swift 2>&1 | tee "$TEST_LOG"
TEST_EXIT=${PIPESTATUS[0]}
set -e

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "capture-test-swift-evidence: just test-swift failed (exit ${TEST_EXIT})" >&2
  exit "$TEST_EXIT"
fi

{
  ls -1 docs/superpowers/plans/ | cat
  echo '---'
  ls -1 docs/superpowers/specs/ | cat
  echo '---'
  find docs/reviews -type f -newer docs/superpowers/plans/2026-06-29-issue-121-menu-bar-quit.md 2>/dev/null | head -5 | cat
  echo '---'
  cat "$REVIEW_PATH" 2>/dev/null | head -100 | cat
} >"$EVIDENCE"

echo "Wrote $TEST_LOG and $EVIDENCE"