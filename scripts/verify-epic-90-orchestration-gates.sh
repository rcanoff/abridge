#!/usr/bin/env bash
# Verify orchestration gates for Epic #90 Contacts subtasks (13 features).
# See docs/superpowers/ for specs/plans and docs/reviews/feat-*/codex.md artifacts.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI required for PR and issue verification" >&2
  exit 1
fi

# slug|spec/plan basename (without -design)|PR number|GitHub issue
FEATURES=(
  "contacts-permissions-foundation|2026-06-29-contacts-permissions-foundation|145|144"
  "contacts-list-contacts|2026-06-29-contacts-list-contacts|146|91"
  "contacts-search-contacts|2026-06-29-contacts-search-contacts|147|92"
  "contacts-get-contact|2026-06-29-contacts-get-contact|148|93"
  "contacts-create-contact|2026-06-29-contacts-create-contact|152|94"
  "contacts-update-contact|2026-06-29-contacts-update-contact|153|95"
  "contacts-delete-contact|2026-06-29-contacts-delete-contact|154|96"
  "contacts-list-groups|2026-06-29-contacts-list-groups|155|99"
  "contacts-create-group|2026-06-29-contacts-create-group|156|100"
  "contacts-update-group|2026-06-29-contacts-update-group|157|101"
  "contacts-delete-group|2026-06-29-contacts-delete-group|158|102"
  "contacts-link-contacts|2026-06-29-contacts-link-contacts|159|97"
  "contacts-unlink-contacts|2026-06-29-contacts-unlink-contacts|160|98"
)

pass_count=0
fail_count=0

check_docs_exist() {
  local slug="$1"
  local basename="$2"
  local spec="docs/superpowers/specs/${basename}-design.md"
  local plan="docs/superpowers/plans/${basename}.md"
  local review="docs/reviews/feat-${slug}/codex.md"
  local missing=()

  for path in "$spec" "$plan" "$review"; do
    if [[ ! -f "$path" ]]; then
      missing+=("$path")
    fi
  done

  if ((${#missing[@]} == 0)); then
    echo "PASS"
    return 0
  fi

  echo "FAIL (missing: ${missing[*]})"
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
  if [[ -z "$last_open" ]]; then
    echo "FAIL (no run log rows in $review)"
    return 1
  fi

  if [[ "$last_open" == "0" ]]; then
    echo "PASS (run log Open: 0)"
    return 0
  fi

  echo "FAIL (final run log Open=${last_open})"
  return 1
}

check_pr_merged() {
  local pr="$1"
  local state

  state="$(gh pr view "$pr" --json state --jq '.state // empty' 2>/dev/null || true)"
  if [[ "$state" == "MERGED" ]]; then
    echo "PASS (PR #$pr MERGED)"
    return 0
  fi

  echo "FAIL (PR #$pr state=${state:-unknown})"
  return 1
}

check_issue_closed() {
  local issue="$1"
  local state

  state="$(gh issue view "$issue" --json state --jq '.state // empty' 2>/dev/null || true)"
  if [[ "$state" == "CLOSED" ]]; then
    echo "PASS (issue #$issue CLOSED)"
    return 0
  fi

  echo "FAIL (issue #$issue state=${state:-unknown})"
  return 1
}

check_link_contacts_run_log_gate() {
  local review="docs/reviews/feat-contacts-link-contacts/codex.md"
  local last_open last_run

  if [[ ! -f "$review" ]]; then
    echo "FAIL (missing $review)"
    return 1
  fi

  last_open="$(grep -E '^\| [0-9]+ \|' "$review" | tail -1 | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}' || true)"
  last_run="$(grep -E '^\| [0-9]+ \|' "$review" | tail -1 | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}' || true)"
  if [[ "$last_open" != "0" ]]; then
    echo "FAIL (final run log Open=${last_open:-unknown}, expected 0)"
    return 1
  fi

  if [[ -n "$last_run" && "$last_run" -lt 15 ]]; then
    echo "FAIL (final run=$last_run, expected >= 15 after post-merge Phase 4 close)"
    return 1
  fi

  echo "PASS (final run=${last_run:-?} Open=0)"
  return 0
}

check_link_contacts_thread1_reviewer_followup() {
  local review="docs/reviews/feat-contacts-link-contacts/codex.md"

  if [[ ! -f "$review" ]]; then
    echo "FAIL (missing $review)"
    return 1
  fi

  if awk '/^## Thread 1 —/{found=1} found && /^### Follow-up — run 1[5-9]/{exit 0} found && /^## Thread 2 —/{exit 1}' "$review"; then
    echo "PASS (Thread 1 has reviewer Follow-up run >= 15)"
    return 0
  fi

  echo "FAIL (Thread 1 missing reviewer Follow-up run >= 15)"
  return 1
}

print_link_contacts_ship_deviation_note() {
  local review="docs/reviews/feat-contacts-link-contacts/codex.md"
  local -a open_one_runs=()
  local line run_num open_val

  if [[ ! -f "$review" ]]; then
    return 0
  fi

  while IFS= read -r line; do
    if [[ "$line" =~ ^\|[[:space:]]*([0-9]+)[[:space:]]*\| ]]; then
      run_num="${BASH_REMATCH[1]}"
      if [[ "$run_num" -eq 1 ]]; then
        continue
      fi
      open_val="$(awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}' <<<"$line")"
      if [[ "$open_val" == "1" ]]; then
        open_one_runs+=("$run_num")
      fi
    fi
  done < <(grep -E '^\| [0-9]+ \|' "$review" || true)

  if ((${#open_one_runs[@]} > 0)); then
    echo "  NOTE: ship-time Phase 4 deviation — run log shows Open=1 after run 1 on run(s): ${open_one_runs[*]} (PR #159 merged during runs 10–12 with Open=1; remediated post-merge via wont-fix disposition + codex run 13 + PR #162)"
  fi
}

echo "verify-epic-90-orchestration-gates: repo=$(basename "$REPO_ROOT") branch=$(git branch --show-current) head=$(git rev-parse --short HEAD)"
echo

for entry in "${FEATURES[@]}"; do
  IFS='|' read -r slug basename pr issue <<<"$entry"

  echo "=== $slug (PR #$pr, issue #$issue) ==="

  gate_a=0 gate_b=0 gate_c=0 gate_d=0 gate_e=0 gate_f=0
  failures=()

  printf '  (a) docs on disk: '
  if out="$(check_docs_exist "$slug" "$basename")"; then
    printf '%s\n' "$out"
    gate_a=1
  else
    printf '%s\n' "$out"
    failures+=("(a)")
  fi

  printf '  (b) review Open: 0: '
  if out="$(check_codex_open_zero "$slug")"; then
    printf '%s\n' "$out"
    gate_b=1
  else
    printf '%s\n' "$out"
    failures+=("(b)")
  fi

  printf '  (c) PR merged: '
  if out="$(check_pr_merged "$pr")"; then
    printf '%s\n' "$out"
    gate_c=1
  else
    printf '%s\n' "$out"
    failures+=("(c)")
  fi

  printf '  (d) issue closed: '
  if out="$(check_issue_closed "$issue")"; then
    printf '%s\n' "$out"
    gate_d=1
  else
    printf '%s\n' "$out"
    failures+=("(d)")
  fi

  if [[ "$slug" == "contacts-link-contacts" ]]; then
    printf '  (e) link-contacts run log final: '
    if out="$(check_link_contacts_run_log_gate)"; then
      printf '%s\n' "$out"
      gate_e=1
    else
      printf '%s\n' "$out"
      failures+=("(e)")
    fi
    printf '  (f) Thread 1 reviewer follow-up: '
    if out="$(check_link_contacts_thread1_reviewer_followup)"; then
      printf '%s\n' "$out"
      gate_f=1
    else
      printf '%s\n' "$out"
      failures+=("(f)")
    fi
    print_link_contacts_ship_deviation_note
  fi

  if [[ "$slug" == "contacts-link-contacts" ]]; then
    if [[ "$gate_a" -eq 1 && "$gate_b" -eq 1 && "$gate_c" -eq 1 && "$gate_d" -eq 1 && "$gate_e" -eq 1 && "$gate_f" -eq 1 ]]; then
      echo "  => PASS"
      pass_count=$((pass_count + 1))
    else
      echo "  => FAIL (${failures[*]})"
      fail_count=$((fail_count + 1))
    fi
  else
    if [[ "$gate_a" -eq 1 && "$gate_b" -eq 1 && "$gate_c" -eq 1 && "$gate_d" -eq 1 ]]; then
      echo "  => PASS"
      pass_count=$((pass_count + 1))
    else
      echo "  => FAIL (${failures[*]})"
      fail_count=$((fail_count + 1))
    fi
  fi

  echo
done

echo "Summary: PASS=$pass_count FAIL=$fail_count"

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

exit 0