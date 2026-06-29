#!/usr/bin/env bash
# Issue #149 definition-of-done gate — verification plan steps 1–7.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-87638bf96566/implementer}"
EVIDENCE="${SCRATCH}/plans-specs-reviewer-evidence.txt"
AGENTS_EVIDENCE="${SCRATCH}/agents-read-evidence.txt"
ISSUE_EVIDENCE="${SCRATCH}/gh-issue-149.txt"
SHIP_EVIDENCE="${SCRATCH}/phase5-ship-transcript.txt"
REVIEW_LOG="${SCRATCH}/review-codex-full.log"
CODEX_REVIEW="docs/reviews/feat-calendars-events-apple-permission/codex.md"
TARGETED_LOG="${SCRATCH}/test-swift-issue-149-targeted.log"
TEST_LOG="${SCRATCH}/test-swift.log"

mkdir -p "$SCRATCH"

echo "verify-issue-149-dod: step 1 — read global + project AGENTS.md"
{
  echo "=== /Users/rcanoff/.grok/AGENTS.md ==="
  cat /Users/rcanoff/.grok/AGENTS.md
  echo ""
  echo "=== ${REPO_ROOT}/Agents.md ==="
  cat "${REPO_ROOT}/Agents.md"
} >"$AGENTS_EVIDENCE"

echo "verify-issue-149-dod: step 1 — gh issue view 149"
gh issue view 149 >"$ISSUE_EVIDENCE"

if ! grep -q 'Calendars & Events Apple permission row and request-access flow' "$ISSUE_EVIDENCE"; then
  echo "verify-issue-149-dod: FAIL — issue title mismatch" >&2
  exit 1
fi

if ! grep -q 'feat/calendars-events-apple-permission' "$ISSUE_EVIDENCE"; then
  echo "verify-issue-149-dod: FAIL — branch name missing from issue" >&2
  exit 1
fi

echo "verify-issue-149-dod: step 2 — spec + plan exist"
test -f docs/superpowers/specs/2026-06-29-issue-149-calendars-events-apple-permission-design.md
test -f docs/superpowers/plans/2026-06-29-issue-149-calendars-events-apple-permission.md

echo "verify-issue-149-dod: step 3 — capture-test-swift-issue-149-evidence.sh"
chmod +x "${REPO_ROOT}/scripts/capture-test-swift-issue-149-evidence.sh"
SCRATCH="$SCRATCH" "${REPO_ROOT}/scripts/capture-test-swift-issue-149-evidence.sh"

if ! grep -q 'EXIT_CODE=0' "$TEST_LOG"; then
  echo "verify-issue-149-dod: FAIL — test-swift.log missing EXIT_CODE=0" >&2
  exit 1
fi

for needle in \
  'EventsPermissionStatusMapper' \
  'EventsPermissionStatusReconciliation' \
  'EventsPermissionService' \
  'requestCalendarAccess' \
  'currentStatus'; do
  if ! grep -q "$needle" "$TARGETED_LOG"; then
    echo "verify-issue-149-dod: FAIL — targeted log missing ${needle}" >&2
    exit 1
  fi
done

if ! grep -qE 'passed|TEST SUCCEEDED|succeeded' "$TARGETED_LOG"; then
  echo "verify-issue-149-dod: FAIL — targeted log missing pass marker" >&2
  exit 1
fi

echo "verify-issue-149-dod: step 4 — codex review conversation + run logs"
if [ ! -f "$CODEX_REVIEW" ]; then
  echo "verify-issue-149-dod: FAIL — missing $CODEX_REVIEW" >&2
  exit 1
fi

if ! grep -q 'No open findings' "$CODEX_REVIEW"; then
  echo "verify-issue-149-dod: FAIL — codex review not clean" >&2
  exit 1
fi

{
  echo "=== just review --codex-only invocation log (concatenated local/review run logs) ==="
  for run in 1 2 3 4; do
    echo "--- codex-run-${run}.log ---"
    cat "local/review/feat-calendars-events-apple-permission/logs/codex-run-${run}.log" 2>/dev/null || true
  done
} >"$REVIEW_LOG"

if ! grep -q 'codex-run-4.log' "$REVIEW_LOG"; then
  echo "verify-issue-149-dod: FAIL — review log missing run 4" >&2
  exit 1
fi

echo "verify-issue-149-dod: step 5 — plans/specs/reviewer evidence"
{
  ls -1 docs/superpowers/plans/ | cat
  echo '---'
  ls -1 docs/superpowers/specs/ | cat
  echo '---'
  find docs/reviews -type f -newer docs/superpowers/plans/2026-06-29-issue-167-native-menu-bar-menu.md 2>/dev/null | head -5 | cat
  echo '---'
  cat "$CODEX_REVIEW" | head -100 | cat
  echo '---'
  echo "codex review summary tail:"
  tail -15 "$CODEX_REVIEW" | cat
} >"$EVIDENCE"

if ! grep -q '2026-06-29-issue-149-calendars-events-apple-permission.md' "$EVIDENCE"; then
  echo "verify-issue-149-dod: FAIL — evidence missing 149 plan" >&2
  exit 1
fi

if ! grep -q '2026-06-29-issue-149-calendars-events-apple-permission-design.md' "$EVIDENCE"; then
  echo "verify-issue-149-dod: FAIL — evidence missing 149 spec" >&2
  exit 1
fi

if ! grep -q 'No open findings' "$EVIDENCE"; then
  echo "verify-issue-149-dod: FAIL — evidence missing clean review summary" >&2
  exit 1
fi

echo "verify-issue-149-dod: step 6 — phase 5 ship transcript (retrospective)"
{
  echo "=== git push (branch already merged; transcript from PR metadata) ==="
  gh pr view 174 --json number,title,state,mergedAt,headRefName,url,body
  echo ""
  echo "=== gh pr checks 174 ==="
  gh pr checks 174 2>&1 || true
  echo ""
  echo "=== gh issue view 149 (post-merge) ==="
  gh issue view 149
} >"$SHIP_EVIDENCE"

if ! grep -q 'MERGED' "$SHIP_EVIDENCE"; then
  echo "verify-issue-149-dod: FAIL — PR 174 not merged" >&2
  exit 1
fi

if ! grep -q 'CLOSED' "$ISSUE_EVIDENCE" && ! gh issue view 149 --json state --jq .state | grep -q CLOSED; then
  echo "verify-issue-149-dod: FAIL — issue 149 not closed" >&2
  exit 1
fi

echo "verify-issue-149-dod: step 7 — git state"
{
  git log --oneline -1 | cat
  git branch --show-current | cat
} | tee -a "$EVIDENCE"

if [ "$(git branch --show-current)" != "main" ]; then
  echo "verify-issue-149-dod: FAIL — not on main" >&2
  exit 1
fi

echo "verify-issue-149-dod: PASS"
echo "Wrote:"
echo "  $AGENTS_EVIDENCE"
echo "  $ISSUE_EVIDENCE"
echo "  $TEST_LOG"
echo "  $TARGETED_LOG"
echo "  $REVIEW_LOG"
echo "  $SHIP_EVIDENCE"
echo "  $EVIDENCE"