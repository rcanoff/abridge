#!/usr/bin/env bash
# Verify orchestration gates for pr3b–pr3k EventKit reminder features.
# See docs/superpowers/ for specs/plans and docs/reviews/feat-*/codex.md artifacts.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI required for PR check verification" >&2
  exit 1
fi

# slug|spec/plan basename|PR number
FEATURES=(
  "pr3b-search-filter-reminders|2026-06-28-pr3b-search-filter-reminders|18"
  "pr3c-create-reminder|2026-06-28-pr3c-create-reminder|19"
  "pr3d-create-reminder-list|2026-06-28-pr3d-create-reminder-list|20"
  "pr3e-update-reminder|2026-06-28-pr3e-update-reminder|21"
  "pr3f-move-reminder|2026-06-28-pr3f-move-reminder|22"
  "pr3g-complete-uncomplete-reminder|2026-06-28-pr3g-complete-uncomplete-reminder|23"
  "pr3h-reminder-alarms|2026-06-28-pr3h-reminder-alarms|24"
  "pr3i-reminder-recurrence|2026-06-28-pr3i-reminder-recurrence|25"
  "pr3j-delete-reminder|2026-06-28-pr3j-delete-reminder|26"
  "pr3k-delete-reminder-list|2026-06-28-pr3k-delete-reminder-list|27"
)

BILLING_PATTERNS='billing|spending limit|payments have failed'

pass_count=0
billing_count=0
fail_count=0

is_tracked() {
  git ls-files --error-unmatch "$1" >/dev/null 2>&1
}

check_docs_tracked() {
  local slug="$1"
  local basename="$2"
  local spec="docs/superpowers/specs/${basename}.md"
  local plan="docs/superpowers/plans/${basename}.md"
  local review="docs/reviews/feat-${slug}/codex.md"
  local missing=()

  for path in "$spec" "$plan" "$review"; do
    if ! is_tracked "$path"; then
      missing+=("$path")
    fi
  done

  if ((${#missing[@]} == 0)); then
    echo "PASS"
    return 0
  fi

  echo "FAIL (untracked: ${missing[*]})"
  return 1
}

check_spec_predates_merge() {
  local basename="$1"
  local pr="$2"
  local spec="docs/superpowers/specs/${basename}.md"
  local spec_add merge_oid

  if [[ ! -f "$spec" ]]; then
    echo "FAIL (spec missing: $spec)"
    return 1
  fi

  spec_add="$(git log --diff-filter=A --follow --format='%H' -- "$spec" | tail -1 || true)"
  if [[ -z "$spec_add" ]]; then
    echo "FAIL (no add commit for $spec)"
    return 1
  fi

  merge_oid="$(gh pr view "$pr" --json mergeCommit --jq '.mergeCommit.oid // empty' 2>/dev/null || true)"
  if [[ -z "$merge_oid" ]]; then
    echo "FAIL (no merge commit for PR #$pr)"
    return 1
  fi

  if [[ "$spec_add" == "$merge_oid" ]]; then
    echo "FAIL (spec introduced in merge commit $merge_oid; expected predating commit)"
    return 1
  fi

  if git merge-base --is-ancestor "$spec_add" "$merge_oid" 2>/dev/null; then
    echo "PASS (spec $spec_add predates merge $merge_oid)"
    return 0
  fi

  echo "FAIL (spec add $spec_add does not predate merge $merge_oid)"
  return 1
}

check_codex_open_zero() {
  local slug="$1"
  local review="docs/reviews/feat-${slug}/codex.md"
  local last_open

  if [[ ! -f "$review" ]]; then
    echo "FAIL (missing $review)"
    return 1
  fi

  last_open="$(grep -E '^\| [0-9]+ \|' "$review" | tail -1 | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}' || true)"
  if [[ "$last_open" == "0" ]]; then
    echo "PASS (run log Open: 0)"
    return 0
  fi

  if grep -qiE 'No open findings|Open:[[:space:]]*0' "$review"; then
    echo "PASS (summary shows no open findings)"
    return 0
  fi

  echo "FAIL (final run log Open=${last_open:-unknown})"
  return 1
}

check_run_billing_blocked() {
  local details_url="$1"
  local job_id annotation
  job_id="${details_url##*/job/}"
  if [[ -z "$job_id" || "$job_id" == "$details_url" ]]; then
    return 1
  fi

  annotation="$(gh api "repos/{owner}/{repo}/check-runs/${job_id}/annotations" --jq '.[].message' 2>/dev/null | head -1 || true)"
  if [[ -n "$annotation" ]] && grep -qiE "$BILLING_PATTERNS" <<<"$annotation"; then
    return 0
  fi

  local run_id
  run_id="$(sed -nE 's|.*/actions/runs/([0-9]+)/.*|\1|p' <<<"$details_url")"
  if [[ -n "$run_id" ]]; then
    if gh run view "$run_id" 2>&1 | grep -qiE "$BILLING_PATTERNS"; then
      return 0
    fi
  fi

  return 1
}

check_pr_checks() {
  local pr="$1"
  local rollup
  rollup="$(gh pr view "$pr" --json statusCheckRollup --jq '.statusCheckRollup // []' 2>/dev/null || echo '[]')"

  local total success failure billing_blocked non_billing_failure
  total="$(jq 'length' <<<"$rollup")"
  if [[ "$total" -eq 0 ]]; then
    echo "FAIL (no status checks on PR #$pr)"
    return 1
  fi

  success="$(jq '[.[] | select(.conclusion == "SUCCESS")] | length' <<<"$rollup")"
  failure="$(jq '[.[] | select(.conclusion == "FAILURE")] | length' <<<"$rollup")"

  if [[ "$success" -gt 0 && "$failure" -eq 0 ]]; then
    echo "PASS (all $total checks SUCCESS)"
    return 0
  fi

  if [[ "$success" -gt 0 ]]; then
    echo "FAIL (mixed results: $success SUCCESS, $failure FAILURE)"
    return 1
  fi

  if [[ "$failure" -ne "$total" ]]; then
    echo "FAIL (unexpected check conclusions on PR #$pr)"
    return 1
  fi

  billing_blocked=0
  non_billing_failure=0
  while IFS= read -r details_url; do
    [[ -z "$details_url" ]] && continue
    if check_run_billing_blocked "$details_url"; then
      billing_blocked=1
    else
      non_billing_failure=1
    fi
  done < <(jq -r '.[].detailsUrl // empty' <<<"$rollup")

  if [[ "$billing_blocked" -eq 1 && "$non_billing_failure" -eq 0 ]]; then
    echo "ENV_BLOCKED_BILLING (all $total checks blocked by billing)"
    return 2
  fi

  echo "FAIL (all checks FAILURE; not billing-only)"
  return 1
}

echo "verify-orchestration-gates: repo=$(basename "$REPO_ROOT") branch=$(git branch --show-current) head=$(git rev-parse --short HEAD)"
echo

for entry in "${FEATURES[@]}"; do
  IFS='|' read -r slug basename pr <<<"$entry"

  echo "=== $slug (PR #$pr) ==="

  gate_a=0 gate_b=0 gate_c=0 gate_d=0
  gate_d_billing=0
  failures=()

  printf '  (a) docs tracked: '
  if out="$(check_docs_tracked "$slug" "$basename")"; then
    printf '%s\n' "$out"
    gate_a=1
  else
    printf '%s\n' "$out"
    failures+=("(a)")
  fi

  printf '  (b) spec predates merge: '
  if out="$(check_spec_predates_merge "$basename" "$pr")"; then
    printf '%s\n' "$out"
    gate_b=1
  else
    printf '%s\n' "$out"
    failures+=("(b)")
  fi

  printf '  (c) review Open: 0: '
  if out="$(check_codex_open_zero "$slug")"; then
    printf '%s\n' "$out"
    gate_c=1
  else
    printf '%s\n' "$out"
    failures+=("(c)")
  fi

  printf '  (d) PR checks: '
  pr_rc=0
  out="$(check_pr_checks "$pr")" || pr_rc=$?
  printf '%s\n' "$out"
  if [[ "$pr_rc" -eq 0 ]]; then
    gate_d=1
  elif [[ "$pr_rc" -eq 2 ]]; then
    gate_d_billing=1
    failures+=("(d)")
  else
    failures+=("(d)")
  fi

  if [[ "$gate_a" -eq 1 && "$gate_b" -eq 1 && "$gate_c" -eq 1 && "$gate_d" -eq 1 ]]; then
    echo "  => PASS"
    pass_count=$((pass_count + 1))
  elif [[ "$gate_a" -eq 1 && "$gate_b" -eq 1 && "$gate_c" -eq 1 && "$gate_d_billing" -eq 1 ]]; then
    echo "  => ENV_BLOCKED_BILLING"
    billing_count=$((billing_count + 1))
  else
    echo "  => FAIL (${failures[*]})"
    fail_count=$((fail_count + 1))
  fi

  echo
done

echo "Summary: PASS=$pass_count ENV_BLOCKED_BILLING=$billing_count FAIL=$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

exit 0