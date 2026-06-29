#!/usr/bin/env bash
# Issue #149 verification plan step 3 — literal just test-swift + verbose targeted suites.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-87638bf96566/implementer}"
TEST_LOG="${SCRATCH}/test-swift.log"
TARGETED_LOG="${SCRATCH}/test-swift-issue-149-targeted.log"

mkdir -p "$SCRATCH"

echo "capture-test-swift-issue-149-evidence: step 3a — TZ=UTC just test-swift (literal)"
set +e
TZ=UTC just test-swift 2>&1 | tee "$TEST_LOG"
TEST_EXIT=${PIPESTATUS[0]}
set -e
echo "EXIT_CODE=${TEST_EXIT}" | tee -a "$TEST_LOG"

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "capture-test-swift-issue-149-evidence: FAIL — just test-swift exit ${TEST_EXIT}" >&2
  exit "$TEST_EXIT"
fi

echo "capture-test-swift-issue-149-evidence: step 3b — verbose targeted suites (issue #149)"
set +e
TZ=UTC xcodebuild test-without-building \
  -project AppleBridge.xcodeproj \
  -scheme AppleBridge \
  -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO \
  -only-testing:AppleBridgeTests/EventsPermissionStatusTests \
  -only-testing:AppleBridgeTests/EventsPermissionReconciliationTests \
  -only-testing:AppleBridgeTests/EventsPermissionServiceTests \
  -only-testing:AppleBridgeTests/AppStoreTests \
  2>&1 | tee "$TARGETED_LOG"
TARGETED_EXIT=${PIPESTATUS[0]}
set -e
echo "EXIT_CODE=${TARGETED_EXIT}" | tee -a "$TARGETED_LOG"

if [ "$TARGETED_EXIT" -ne 0 ]; then
  echo "capture-test-swift-issue-149-evidence: FAIL — targeted tests exit ${TARGETED_EXIT}" >&2
  exit "$TARGETED_EXIT"
fi

echo "capture-test-swift-issue-149-evidence: PASS"
echo "Wrote $TEST_LOG and $TARGETED_LOG"