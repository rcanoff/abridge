#!/usr/bin/env bash
# Issue #167 definition-of-done gate — verification plan steps 3, 4, 5, 7.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-0858149818ca/implementer}"
PBXPROJ="AppleBridge.xcodeproj/project.pbxproj"
EVIDENCE="${SCRATCH}/plans-specs-reviewer-evidence.txt"
FAKE_UUID_PATTERN='890ABCDEF|5E6F7890|ABCDEF0123'
NATIVE_MENU_REVIEW="docs/reviews/feat-menu-bar-native-menu/codex.md"
CHORE_REVIEW="docs/reviews/chore-fix-167-verification-gaps/codex.md"

mkdir -p "$SCRATCH"

echo "verify-issue-167-dod: step 1 — gh issue view 167"
gh issue view 167 --json title,state,closedAt --jq .

echo "verify-issue-167-dod: checking pbxproj for fake UUID placeholders…"
if grep -qE "$FAKE_UUID_PATTERN" "$PBXPROJ"; then
  echo "verify-issue-167-dod: FAIL — fake UUID placeholders found in $PBXPROJ" >&2
  grep -nE "$FAKE_UUID_PATTERN" "$PBXPROJ" >&2 || true
  exit 1
fi
echo "verify-issue-167-dod: OK — no fake UUID placeholders (grep count: $(grep -cE "$FAKE_UUID_PATTERN" "$PBXPROJ" || echo 0))"

echo "verify-issue-167-dod: step 3 — capture-test-swift-evidence.sh"
SCRATCH="$SCRATCH" "${REPO_ROOT}/scripts/capture-test-swift-evidence.sh"

echo "verify-issue-167-dod: step 5 — plan one-liner (actual review path for #167)"
{
  ls -1 docs/superpowers/plans/ | cat
  echo '---'
  ls -1 docs/superpowers/specs/ | cat
  echo '---'
  find docs/reviews -type f -newer docs/superpowers/plans/2026-06-29-issue-121-menu-bar-quit.md 2>/dev/null | head -5 | cat
  echo '---'
  cat "$NATIVE_MENU_REVIEW" 2>/dev/null | head -100 | cat
  echo '---'
  cat "$CHORE_REVIEW" 2>/dev/null | head -100 | cat
} >"$EVIDENCE"

echo "verify-issue-167-dod: step 4 — codex review logs on disk"
for review_log in "${SCRATCH}/review-run-2.log" "${SCRATCH}/review-run-fix-2.log"; do
  if [ -f "$review_log" ]; then
    echo "verify-issue-167-dod: found $(basename "$review_log")"
  else
    echo "verify-issue-167-dod: WARN — missing $(basename "$review_log")" >&2
  fi
done

if [ ! -f "$NATIVE_MENU_REVIEW" ]; then
  echo "verify-issue-167-dod: FAIL — missing $NATIVE_MENU_REVIEW" >&2
  exit 1
fi

if ! grep -q '# Review conversation — feat/menu-bar-native-menu' "$EVIDENCE"; then
  echo "verify-issue-167-dod: FAIL — evidence missing feat/menu-bar-native-menu review" >&2
  exit 1
fi

if ! grep -q '# Review conversation — chore/fix-167-verification-gaps' "$EVIDENCE"; then
  echo "verify-issue-167-dod: FAIL — evidence missing chore verification review" >&2
  exit 1
fi

if ! grep -q '2026-06-29-issue-167-native-menu-bar-menu.md' "$EVIDENCE"; then
  echo "verify-issue-167-dod: FAIL — evidence missing 167 plan file" >&2
  exit 1
fi

if ! grep -q '2026-06-29-issue-167-native-menu-bar-menu-design.md' "$EVIDENCE"; then
  echo "verify-issue-167-dod: FAIL — evidence missing 167 spec file" >&2
  exit 1
fi

if ! grep -q 'No open findings' "$NATIVE_MENU_REVIEW"; then
  echo "verify-issue-167-dod: FAIL — native-menu codex review not clean" >&2
  exit 1
fi

echo "verify-issue-167-dod: step 7 — git state"
git log --oneline -1 | cat
git branch --show-current | cat

echo "verify-issue-167-dod: PASS"
echo "Wrote $EVIDENCE"