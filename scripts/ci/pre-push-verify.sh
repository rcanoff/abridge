#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BASE_REF="${CI_BASE_REF:-origin/main}"
# Block on fmt/lint/test failures by default. Set CI_STRICT=0 for advisory mode.
STRICT="${CI_STRICT:-1}"

run_verify() {
  local label="$1"
  shift
  echo "pre-push verify: ${label}"
  if "$@"; then
    return 0
  fi
  if [[ "$STRICT" == "1" ]]; then
    echo "pre-push verify: FAILED (blocking push; set CI_STRICT=0 for advisory)" >&2
    return 1
  fi
  echo "pre-push verify: FAILED (advisory — push will continue)" >&2
  return 0
}

# Resolve range from pre-push stdin when invoked as hook
HEAD_REF="HEAD"
REMOTE_OID=""
while read -r _local_ref local_oid _remote_ref remote_oid; do
  HEAD_REF="$local_oid"
  REMOTE_OID="$remote_oid"
done

if [[ -z "$REMOTE_OID" ]]; then
  # Manual run or no stdin: compare branch against base
  # shellcheck source=scripts/ci/paths.sh
  source "$REPO_ROOT/scripts/ci/paths.sh" "$BASE_REF" "$HEAD_REF"
elif [[ "$REMOTE_OID" == "0000000000000000000000000000000000000000" ]]; then
  # New branch: compare commits on branch vs base
  MERGE_BASE="$(git merge-base "$BASE_REF" "$HEAD_REF" 2>/dev/null || echo "$BASE_REF")"
  # shellcheck source=scripts/ci/paths.sh
  source "$REPO_ROOT/scripts/ci/paths.sh" "$MERGE_BASE" "$HEAD_REF"
else
  # shellcheck source=scripts/ci/paths.sh
  source "$REPO_ROOT/scripts/ci/paths.sh" "$REMOTE_OID" "$HEAD_REF"
fi

if [[ "$PATHS_RUST_CHANGED" -eq 0 && "$PATHS_SWIFT_CHANGED" -eq 0 ]]; then
  echo "pre-push verify: no CI paths changed — skipping"
  exit 0
fi

if [[ "$PATHS_RUST_CHANGED" -eq 1 ]]; then
  run_verify "rust (ci-rust)" just ci-rust || exit $?
fi

if [[ "$PATHS_SWIFT_CHANGED" -eq 1 ]]; then
  run_verify "swift fmt" just fmt-check-swift || exit $?
  run_verify "swift lint" just lint-swift || exit $?
  run_verify "swift test" just test-swift || exit $?
fi

echo "pre-push verify: done (build-rust skipped — runs in macOS CI)"