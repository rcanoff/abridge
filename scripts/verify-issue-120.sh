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
GUARD_LOG="${SCRATCH}/single-instance-guard-suite.log"
GH_PR_SHIP_LOG="${SCRATCH}/gh-pr-ship.log"

mkdir -p "$SCRATCH" "$RESULT_DIR"

# Remove stale artifacts that misrepresent guard coverage or ship evidence.
rm -f \
  "$BUNDLE" \
  "$TEST_LOG" \
  "$GUARD_LOG" \
  "$GH_PR_SHIP_LOG" \
  "$SCRATCH/single-instance-guard-tests.log" \
  "$SCRATCH/double-launch-check.log" \
  "$SCRATCH/double-launch-check-v2.log" \
  "$SCRATCH/double-launch-check-v3.log" \
  "$SCRATCH/double-launch-clean-start.log" \
  "$SCRATCH/double-launch-pid-delta.log" \
  "$SCRATCH/gh-pr-create.log" \
  "$SCRATCH/gh-pr-create-137.log"
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

kill_apple_bridge_processes() {
  for _ in 1 2 3 4 5; do
    while read -r pid; do kill -9 "$pid" 2>/dev/null || true; done < <(pgrep -x AppleBridge 2>/dev/null || true)
    pkill -f "debugserver.*AppleBridge" 2>/dev/null || true
    sleep 1
    pgrep -x AppleBridge >/dev/null 2>&1 || return 0
  done
  return 1
}

extract_guard_suite() {
  awk '
    /Suite "SingleInstanceGuard" started/ { capture=1 }
    capture { print }
    capture && /Suite "SingleInstanceGuard" passed/ { exit }
  ' "$TEST_LOG"
}

append_codex_review() {
  local review_dir="$1"
  local path="docs/reviews/${review_dir}/codex.md"
  section "STEP 8 — cat ${path}"
  if [ -f "$path" ]; then
    cat "$path" >>"$BUNDLE"
  else
    echo "MISSING: $path" >>"$BUNDLE"
  fi
}

# --- Step 1: Issue scope ---
section "STEP 1 — gh issue view 120"
append_cmd gh issue view 120
append_cmd gh issue view 120 --json title,state,labels,closedAt

# --- Step 4: Full test run with guard suite extract ---
section "STEP 4 — TZ=UTC just test-swift (verbose guard extract)"
section "NOTE — Swift Testing suite filter"
{
  echo "AppleBridgeTests/SingleInstanceGuard -only-testing executes 0 tests (Swift Testing naming)."
  echo "Guard coverage is extracted from the full test run log and xcresult summary."
} >>"$BUNDLE"

rm -rf "$RESULT_BUNDLE"
TZ=UTC xcodebuild build-for-testing -project AppleBridge.xcodeproj -scheme AppleBridge \
  -destination 'platform=macOS,arch=arm64' -quiet >>"$BUNDLE" 2>&1
TZ=UTC xcodebuild test-without-building -project AppleBridge.xcodeproj -scheme AppleBridge \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_BUNDLE" 2>&1 | tee "$TEST_LOG" >>"$BUNDLE"

extract_guard_suite | tee "$GUARD_LOG"

section "GUARD SUITE — SingleInstanceGuard block only"
cat "$GUARD_LOG" >>"$BUNDLE"

section "GUARD SUITE — xcresult summary"
xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" >>"$BUNDLE" 2>&1

# --- Step 7: Double-launch from clean start ---
section "STEP 7 — double-launch (kill-first, PRE must be 0)"
kill_apple_bridge_processes || true
sleep 2
PRE_COUNT=$( (pgrep -x AppleBridge 2>/dev/null || true) | wc -l | tr -d ' ')
DOUBLE_LAUNCH_OK=0
set +e
if (
  echo "PRE_COUNT=$PRE_COUNT"
  if [ "$PRE_COUNT" -ne 0 ]; then
    echo "FAIL: expected PRE_COUNT=0 after kill"
    pgrep -x AppleBridge || true
    exit 1
  fi

  APP_BUNDLE=$(xcodebuild -project AppleBridge.xcodeproj -scheme AppleBridge \
    -destination 'platform=macOS,arch=arm64' -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/TARGET_BUILD_DIR = / {dir=$2} /WRAPPER_NAME = / {name=$2} END {print dir"/"name}')
  echo "APP_BUNDLE=$APP_BUNDLE"

  /usr/bin/open -n "$APP_BUNDLE"
  sleep 4
  COUNT1=$(pgrep -x AppleBridge | wc -l | tr -d ' ')
  echo "INSTANCE_COUNT_AFTER_LAUNCH_1=$COUNT1"
  pgrep -x AppleBridge || true

  /usr/bin/open -n "$APP_BUNDLE"
  sleep 2
  COUNT2=$(pgrep -x AppleBridge | wc -l | tr -d ' ')
  echo "INSTANCE_COUNT_AFTER_LAUNCH_2=$COUNT2"
  pgrep -x AppleBridge || true

  lsof -iTCP:3020 -sTCP:LISTEN 2>/dev/null || echo "(no listener on 3020)"
  PORT_COUNT=$(lsof -iTCP:3020 -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { count++ } END { print count + 0 }')
  echo "PORT_3020_LISTENERS=$PORT_COUNT"

  if [ "$COUNT1" -eq 1 ] && [ "$COUNT2" -eq 1 ] && [ "$PORT_COUNT" -le 1 ]; then
    echo "PASS: PRE=0, launch1→1 instance, launch2→still 1, port listeners ≤1"
    exit 0
  fi
  echo "FAIL: COUNT1=$COUNT1 COUNT2=$COUNT2 PORT=$PORT_COUNT"
  exit 1
) >>"$BUNDLE" 2>&1; then
  DOUBLE_LAUNCH_OK=1
fi
set -e

kill_apple_bridge_processes || true

if [ "$DOUBLE_LAUNCH_OK" -ne 1 ]; then
  echo "verify-issue-120: double-launch check failed (see STEP 7 in bundle)" >&2
  exit 1
fi

# --- Step 8: Plans, specs, reviewer conversations ---
section "STEP 8 — ls docs/superpowers/specs/ | cat"
ls docs/superpowers/specs/ | cat >>"$BUNDLE"

section "STEP 8 — ls docs/superpowers/plans/ | cat"
ls docs/superpowers/plans/ | cat >>"$BUNDLE"

ISSUE_120_REVIEW_DIRS=(
  feat-single-instance-guard
  feat-single-instance-guard-bootstrap-entry
  feat-single-instance-guard-order-fix
  fix-issue-120-verification-gaps
  fix-verify-issue-120-port-count
)
for review_dir in "${ISSUE_120_REVIEW_DIRS[@]}"; do
  append_codex_review "$review_dir"
done

# --- Step 6: Ship references ---
section "STEP 6 — gh pr ship log (all #120 PRs)"
{
  for pr in 135 136 137 138 139 140; do
    echo "--- PR #${pr} ---"
    gh pr view "$pr" --json number,title,url,state,mergedAt,closingIssuesReferences
  done
} | tee "$GH_PR_SHIP_LOG" >>"$BUNDLE"

section "STEP 6 — merged PRs closing #120 (search)"
gh pr list --search "120" --state merged --json number,title,url,closingIssuesReferences --limit 10 >>"$BUNDLE" 2>&1

# --- Step 9: Tree scope evidence ---
section "STEP 9 — git status (main tree clean; #120 scope)"
git status --short >>"$BUNDLE"
{
  echo "Changed files in #120 PR stack (135–140):"
  git log --oneline --name-only main --grep='#120' --grep='single-instance' --grep='issue-120' --grep='verify-issue-120' -i --max-count=20
} >>"$BUNDLE" 2>&1

# --- Step 10: Merge commit ---
section "STEP 10 — git log --oneline -1"
git log --oneline -1 >>"$BUNDLE"

echo "Wrote $BUNDLE"