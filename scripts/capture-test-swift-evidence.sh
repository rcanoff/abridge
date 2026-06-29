#!/usr/bin/env bash
# Capture literal `just test-swift` output plus xcresult summary for goal verification.
# Writes: ${SCRATCH}/test-swift.log (overwrite + append on success)
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-0858149818ca/implementer}"
LOG="${SCRATCH}/test-swift.log"
RESULT_DIR="${SCRATCH}/test-swift-xcresult"
RESULT_BUNDLE="${RESULT_DIR}/test-results.xcresult"

mkdir -p "$SCRATCH" "$RESULT_DIR"

set +e
TZ=UTC just test-swift 2>&1 | tee "$LOG"
TEST_EXIT=${PIPESTATUS[0]}
set -e

{
  echo ""
  echo "=== just test-swift exit code: ${TEST_EXIT} ==="
} >>"$LOG"

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "capture-test-swift-evidence: just test-swift failed (exit ${TEST_EXIT})" >&2
  exit "$TEST_EXIT"
fi

rm -rf "$RESULT_BUNDLE"
{
  echo ""
  echo "--- xcresult summary (same scheme/destination, no -quiet) ---"
} >>"$LOG"

TZ=UTC xcodebuild test-without-building -project AppleBridge.xcodeproj -scheme AppleBridge \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_BUNDLE" >>"$LOG" 2>&1

xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" >>"$LOG" 2>&1

echo "Wrote $LOG"