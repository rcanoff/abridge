#!/usr/bin/env bash
# Issue #120 verification bundle — single canonical output for goal acceptance.
# Writes exactly one file: ${SCRATCH}/verification-bundle.txt (overwrite).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-b05ba8354914/implementer}"
BUNDLE="${SCRATCH}/verification-bundle.txt"
RESULT_DIR="${SCRATCH}/issue-120-xcresult"
RESULT_BUNDLE="${RESULT_DIR}/test-results.xcresult"
TEST_LOG="${SCRATCH}/issue-120-test-verbose.log"

mkdir -p "$SCRATCH" "$RESULT_DIR"
: >"$BUNDLE"

section() {
  {
    echo ""
    echo "=== $1 ==="
  } >>"$BUNDLE"
}

append_cmd() {
  {
    echo "\$ $*"
    "$@"
  } >>"$BUNDLE" 2>&1
}

# --- Step 1: Issue scope ---
section "STEP 1 — gh issue view 120"
append_cmd gh issue view 120
append_cmd gh issue view 120 --json title,state,labels,closedAt

# --- Step 4: Full test run with guard suite extract ---
section "STEP 4 — TZ=UTC just test-swift (verbose guard extract)"
rm -rf "$RESULT_BUNDLE"
TZ=UTC xcodebuild build-for-testing -project AppleBridge.xcodeproj -scheme AppleBridge \
  -destination 'platform=macOS,arch=arm64' -quiet >>"$BUNDLE" 2>&1
TZ=UTC xcodebuild test-without-building -project AppleBridge.xcodeproj -scheme AppleBridge \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_BUNDLE" 2>&1 | tee "$TEST_LOG" >>"$BUNDLE"

section "GUARD SUITE — named tests from verbose log"
{
  grep -E 'Suite "SingleInstanceGuard"|Test (performEntry|evaluate|runningApplication|launchRestore)|passed after|TEST EXECUTE' "$TEST_LOG" || true
} >>"$BUNDLE"

section "GUARD SUITE — xcresult summary"
xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" >>"$BUNDLE" 2>&1

# --- Step 7: Double-launch from clean start ---
section "STEP 7 — double-launch (kill-first)"
pkill -x AppleBridge 2>/dev/null || true
sleep 2
PRE_COUNT=$(pgrep -x AppleBridge 2>/dev/null | wc -l | tr -d ' ')
{
  echo "PRE_COUNT=$PRE_COUNT"
  if [ "$PRE_COUNT" -gt 0 ]; then
    echo "HARNESS_BLOCKED: cannot reach clean start"
    pgrep -x AppleBridge || true
    echo "FALLBACK: unit tests via performEntry prove duplicate path (see GUARD SUITE above)"
  else
    APP_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData/AppleBridge-*/Build/Products/Debug/AppleBridge.app -maxdepth 0 2>/dev/null | head -1)
    echo "APP_BUNDLE=$APP_BUNDLE"
    open -n "$APP_BUNDLE"
    sleep 4
    COUNT1=$(pgrep -x AppleBridge | wc -l | tr -d ' ')
    echo "INSTANCE_COUNT_AFTER_LAUNCH_1=$COUNT1"
    pgrep -x AppleBridge || true
    open -n "$APP_BUNDLE"
    sleep 2
    COUNT2=$(pgrep -x AppleBridge | wc -l | tr -d ' ')
    echo "INSTANCE_COUNT_AFTER_LAUNCH_2=$COUNT2"
    pgrep -x AppleBridge || true
    lsof -iTCP:3020 -sTCP:LISTEN 2>/dev/null || echo "(no listener on 3020)"
    PORT_COUNT=$(lsof -iTCP:3020 -sTCP:LISTEN 2>/dev/null | grep -c LISTEN || echo 0)
    echo "PORT_3020_LISTENERS=$PORT_COUNT"
    if [ "$COUNT1" -eq 1 ] && [ "$COUNT2" -eq 1 ] && [ "$PORT_COUNT" -le 1 ]; then
      echo "PASS: one instance, duplicate blocked, at most one port listener"
    else
      echo "FAIL: COUNT1=$COUNT1 COUNT2=$COUNT2 PORT=$PORT_COUNT"
    fi
    pkill -x AppleBridge 2>/dev/null || true
  fi
} >>"$BUNDLE" 2>&1 || true

# --- Step 8: Plans, specs, reviewer conversation ---
section "STEP 8 — ls docs/superpowers/specs/ | cat"
ls docs/superpowers/specs/ | cat >>"$BUNDLE"

section "STEP 8 — ls docs/superpowers/plans/ | cat"
ls docs/superpowers/plans/ | cat >>"$BUNDLE"

section "STEP 8 — cat docs/reviews/feat-single-instance-guard/codex.md"
if [ -f docs/reviews/feat-single-instance-guard/codex.md ]; then
  cat docs/reviews/feat-single-instance-guard/codex.md >>"$BUNDLE"
else
  echo "MISSING: docs/reviews/feat-single-instance-guard/codex.md" >>"$BUNDLE"
fi

# --- Step 5–6: Review + ship references ---
section "STEP 5–6 — codex review status"
if [ -f docs/reviews/feat-single-instance-guard-bootstrap-entry/codex.md ]; then
  tail -5 docs/reviews/feat-single-instance-guard-bootstrap-entry/codex.md >>"$BUNDLE"
fi

section "STEP 6 — linked PR for #120"
gh pr list --search "120" --state merged --json number,title,url,closingIssuesReferences --limit 5 >>"$BUNDLE" 2>&1

# --- Step 10: Merge commit ---
section "STEP 10 — git log --oneline -1"
git log --oneline -1 >>"$BUNDLE"

echo "Wrote $BUNDLE"