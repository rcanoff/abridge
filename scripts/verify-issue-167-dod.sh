#!/usr/bin/env bash
# Issue #167 definition-of-done gate — pbxproj, tests, evidence, review path.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-0858149818ca/implementer}"
PBXPROJ="AppleBridge.xcodeproj/project.pbxproj"
EVIDENCE="${SCRATCH}/plans-specs-reviewer-evidence.txt"
REVIEW_MARKER="# Review conversation — feat/menu-bar-native-menu"

echo "verify-issue-167-dod: checking pbxproj for fake UUID placeholders…"
if grep -qE '890ABCDEF|ABCDEF0123' "$PBXPROJ"; then
  echo "verify-issue-167-dod: FAIL — fake UUID placeholders found in $PBXPROJ" >&2
  grep -nE '890ABCDEF|ABCDEF0123' "$PBXPROJ" >&2 || true
  exit 1
fi
echo "verify-issue-167-dod: OK — no fake UUID placeholders"

echo "verify-issue-167-dod: running capture-test-swift-evidence.sh…"
SCRATCH="$SCRATCH" "${REPO_ROOT}/scripts/capture-test-swift-evidence.sh"

echo "verify-issue-167-dod: checking evidence review section…"
if ! grep -q "$REVIEW_MARKER" "$EVIDENCE"; then
  echo "verify-issue-167-dod: FAIL — evidence missing $REVIEW_MARKER" >&2
  exit 1
fi

REVIEW_SECTION="$(awk '/^---$/{n++} n==3{found=1} found{print}' "$EVIDENCE")"
if echo "$REVIEW_SECTION" | grep -q 'menu-bar-quit'; then
  echo "verify-issue-167-dod: FAIL — evidence review section contains menu-bar-quit" >&2
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

echo "verify-issue-167-dod: PASS"