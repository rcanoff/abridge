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

pass_count=0
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

check_main_ancestry() {
  local basename="$1"
  local pr="$2"
  local spec="docs/superpowers/specs/${basename}.md"
  local spec_add merge_oid

  if [[ ! -f "$spec" ]]; then
    echo "FAIL (spec missing $spec)"
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
    echo "FAIL (spec introduced in merge commit ${merge_oid:0:7})"
    return 1
  fi

  if git merge-base --is-ancestor "$spec_add" "$merge_oid" 2>/dev/null; then
    echo "PASS (spec ${spec_add:0:7} predates merge ${merge_oid:0:7})"
    return 0
  fi

  echo "FAIL (spec ${spec_add:0:7} not ancestor of merge ${merge_oid:0:7})"
  return 1
}

check_feat_first_commit_docs_only() {
  local slug="$1"
  local branch="feat/${slug}"
  local branch_ref merge_base first_commit
  local -a paths=() bad=()
  local path

  if git show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
    branch_ref="origin/${branch}"
  elif git show-ref --verify --quiet "refs/heads/${branch}"; then
    branch_ref="${branch}"
  else
    echo "FAIL (no remote or local ${branch})"
    return 1
  fi

  merge_base="$(git merge-base main "$branch_ref" 2>/dev/null || true)"
  if [[ -z "$merge_base" ]]; then
    echo "FAIL (cannot find merge-base for ${branch_ref})"
    return 1
  fi

  first_commit="$(git log "${merge_base}..${branch_ref}" --reverse --format='%H' -1 2>/dev/null || true)"
  if [[ -z "$first_commit" ]]; then
    echo "FAIL (no commits on ${branch_ref} after merge-base)"
    return 1
  fi

  while IFS= read -r path; do
    [[ -n "$path" ]] && paths+=("$path")
  done < <(git log "${merge_base}..${branch_ref}" --reverse --name-only --format='' -1 2>/dev/null || true)

  if ((${#paths[@]} == 0)); then
    echo "FAIL (first commit ${first_commit:0:7} has no file changes)"
    return 1
  fi

  for path in "${paths[@]}"; do
    if [[ "$path" != docs/superpowers/* ]]; then
      bad+=("$path")
    fi
  done

  if ((${#bad[@]} > 0)); then
    echo "FAIL (first commit ${first_commit:0:7} touches non-docs/superpowers: ${bad[*]})"
    return 1
  fi

  echo "PASS (first commit ${first_commit:0:7} docs/superpowers only)"
  return 0
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

check_pr_checks() {
  local pr="$1"
  local rollup
  rollup="$(gh pr view "$pr" --json statusCheckRollup --jq '.statusCheckRollup // []' 2>/dev/null || echo '[]')"

  local total success non_success
  total="$(jq 'length' <<<"$rollup")"
  if [[ "$total" -eq 0 ]]; then
    echo "FAIL (no status checks on PR #$pr)"
    return 1
  fi

  success="$(jq '[.[] | select(.conclusion == "SUCCESS")] | length' <<<"$rollup")"
  non_success="$(jq '[.[] | select(.conclusion != "SUCCESS")] | length' <<<"$rollup")"

  if [[ "$success" -eq "$total" ]]; then
    echo "PASS (all $total checks SUCCESS)"
    return 0
  fi

  echo "FAIL ($success/$total SUCCESS; $non_success non-SUCCESS)"
  return 1
}

echo "verify-orchestration-gates: repo=$(basename "$REPO_ROOT") branch=$(git branch --show-current) head=$(git rev-parse --short HEAD)"
echo

for entry in "${FEATURES[@]}"; do
  IFS='|' read -r slug basename pr <<<"$entry"

  echo "=== $slug (PR #$pr) ==="

  gate_a=0 gate_b=0 gate_c=0 gate_d=0 gate_e=0
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
  if out="$(check_main_ancestry "$basename" "$pr")"; then
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
  if out="$(check_pr_checks "$pr")"; then
    printf '%s\n' "$out"
    gate_d=1
  else
    printf '%s\n' "$out"
    failures+=("(d)")
  fi

  printf '  (e) feat first commit docs-only: '
  if out="$(check_feat_first_commit_docs_only "$slug")"; then
    printf '%s\n' "$out"
    gate_e=1
  else
    printf '%s\n' "$out"
    failures+=("(e)")
  fi

  if [[ "$gate_a" -eq 1 && "$gate_b" -eq 1 && "$gate_c" -eq 1 && "$gate_d" -eq 1 && "$gate_e" -eq 1 ]]; then
    echo "  => PASS"
    pass_count=$((pass_count + 1))
  else
    echo "  => FAIL (${failures[*]})"
    fail_count=$((fail_count + 1))
  fi

  echo
done

echo "Summary: PASS=$pass_count FAIL=$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

exit 0