#!/usr/bin/env bash
# Verify Phase 4 ship order for Epic #90 Contacts subtasks (13 features).
# PASS ship_order when final codex Open=0 and last local review log predates PR merge.
# contacts-link-contacts (#97): REMEDIATED PASS if ship_order fails but frozen run-14 codex passes.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI required for PR merge timestamp verification" >&2
  exit 1
fi

# slug|PR number|GitHub issue
FEATURES=(
  "contacts-permissions-foundation|145|144"
  "contacts-list-contacts|146|91"
  "contacts-search-contacts|147|92"
  "contacts-get-contact|148|93"
  "contacts-create-contact|152|94"
  "contacts-update-contact|153|95"
  "contacts-delete-contact|154|96"
  "contacts-list-groups|155|99"
  "contacts-create-group|156|100"
  "contacts-update-group|157|101"
  "contacts-delete-group|158|102"
  "contacts-link-contacts|159|97"
  "contacts-unlink-contacts|160|98"
)

pass_count=0
remediated_count=0
fail_count=0

iso_utc_from_epoch() {
  python3 - "$1" <<'PY'
import sys
from datetime import datetime, timezone
print(datetime.fromtimestamp(float(sys.argv[1]), tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

merge_epoch_for_pr() {
  local pr="$1"
  local merged_at

  merged_at="$(gh pr view "$pr" --json mergedAt --jq '.mergedAt // empty' 2>/dev/null || true)"
  if [[ -z "$merged_at" || "$merged_at" == "null" ]]; then
    echo ""
    return 1
  fi

  python3 - "$merged_at" <<'PY'
import sys
from datetime import datetime
print(datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp())
PY
}

final_codex_open() {
  local slug="$1"
  local review="docs/reviews/feat-${slug}/codex.md"
  local last_open

  if [[ ! -f "$review" ]]; then
    echo "missing"
    return 1
  fi

  last_open="$(
    grep -E '^\| [0-9]+ \|' "$review" \
      | tail -1 \
      | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}' \
      || true
  )"
  if [[ -z "$last_open" ]]; then
    echo "none"
    return 1
  fi

  echo "$last_open"
}

last_review_log_info() {
  local slug="$1"
  local log_dir="local/review/feat-${slug}/logs"
  local last_log last_run mtime_epoch mtime_iso

  if [[ ! -d "$log_dir" ]]; then
    echo "||"
    return 1
  fi

  last_log="$(
    find "$log_dir" -maxdepth 1 -name 'codex-run-*.log' -print \
      | while IFS= read -r path; do
          run="$(basename "$path" .log | sed 's/^codex-run-//')"
          printf '%s\t%s\n' "$run" "$path"
        done \
      | sort -t $'\t' -k1,1n \
      | tail -1 \
      | cut -f2-
  )"

  if [[ -z "$last_log" || ! -f "$last_log" ]]; then
    echo "||"
    return 1
  fi

  last_run="$(basename "$last_log" .log | sed 's/^codex-run-//')"
  mtime_epoch="$(stat -f '%m' "$last_log" 2>/dev/null || stat -c '%Y' "$last_log")"
  mtime_iso="$(iso_utc_from_epoch "$mtime_epoch")"
  echo "${last_run}|${mtime_epoch}|${mtime_iso}|${last_log}"
}

check_link_contacts_frozen_codex() {
  local review="docs/reviews/feat-contacts-link-contacts/codex.md"
  local failures=()
  local summary_line high_run open_val

  if [[ ! -f "$review" ]]; then
    echo "FAIL (missing $review)"
    return 1
  fi

  summary_line="$(
    awk '/^## Summary$/{found=1; next} found && /^## /{exit} found && NF{print; exit}' "$review" \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
  )"
  if [[ "$summary_line" != "No open findings." ]]; then
    failures+=("summary!=No open findings.")
  fi

  if ! sed -n '/^## Thread 1 —/,/^## Thread 2 —/p' "$review" | grep -q '^\*\*Status:\*\* wont-fix'; then
    failures+=("Thread 1 status!=wont-fix")
  fi

  high_run="$(
    grep -E '^\| [0-9]+ \|' "$review" \
      | awk -F'|' '{gsub(/^ +| +$/,"",$2); if ($2+0 >= 15) {print $2; exit}}'
  )"
  if [[ -n "$high_run" ]]; then
    failures+=("run log has run>=15 (run $high_run)")
  fi

  open_val="$(final_codex_open "contacts-link-contacts")"
  if [[ "$open_val" != "0" ]]; then
    failures+=("final Open!=0 (Open=${open_val})")
  fi

  if ((${#failures[@]} == 0)); then
    echo "PASS (frozen run-14: summary, Thread 1 wont-fix, no run>=15, Open: 0)"
    return 0
  fi

  echo "FAIL (${failures[*]})"
  return 1
}

echo "verify-epic-90-phase4-order: repo=$(basename "$REPO_ROOT") branch=$(git branch --show-current) head=$(git rev-parse --short HEAD)"
echo

for entry in "${FEATURES[@]}"; do
  IFS='|' read -r slug pr issue <<<"$entry"

  echo "=== $slug (PR #$pr, issue #$issue) ==="

  merged_at=""
  merge_epoch=""
  if merged_at="$(gh pr view "$pr" --json mergedAt --jq '.mergedAt // empty' 2>/dev/null || true)"; then
    :
  fi
  if [[ -n "$merged_at" && "$merged_at" != "null" ]]; then
    merge_epoch="$(merge_epoch_for_pr "$pr" || true)"
  fi

  printf '  PR mergedAt: %s\n' "${merged_at:-unknown}"

  open_val="$(final_codex_open "$slug" || true)"
  printf '  codex final Open: %s\n' "${open_val:-unknown}"

  IFS='|' read -r last_run log_epoch log_iso last_log_path < <(last_review_log_info "$slug" || true)
  if [[ -n "$last_run" ]]; then
    printf '  last review log: codex-run-%s mtime=%s (%s)\n' "$last_run" "$log_iso" "$last_log_path"
  else
    printf '  last review log: MISSING\n'
  fi

  ship_order_ok=0
  open_ok=0
  order_note=""

  if [[ "$open_val" == "0" ]]; then
    open_ok=1
  fi

  if [[ -n "$merge_epoch" && -n "$log_epoch" ]]; then
    if awk -v log_ts="$log_epoch" -v merge_ts="$merge_epoch" 'BEGIN { exit (log_ts < merge_ts) ? 0 : 1 }'; then
      ship_order_ok=1
      order_note="last log before merge"
    else
      order_note="last log after merge"
    fi
  else
    order_note="missing merge or log timestamp"
  fi

  result="FAIL"
  if [[ "$ship_order_ok" -eq 1 && "$open_ok" -eq 1 ]]; then
    result="PASS"
    pass_count=$((pass_count + 1))
    printf '  => PASS ship_order (%s, Open=0)\n' "$order_note"
  elif [[ "$slug" == "contacts-link-contacts" && "$open_ok" -eq 1 ]]; then
    printf '  ship_order: FAIL (%s)\n' "$order_note"
    printf '  frozen codex (run 14): '
    if frozen_out="$(check_link_contacts_frozen_codex)"; then
      printf '%s\n' "$frozen_out"
      result="REMEDIATED PASS"
      remediated_count=$((remediated_count + 1))
      printf '  => REMEDIATED PASS (#97 ship-before-Open:0 deviation)\n'
    else
      printf '%s\n' "$frozen_out"
      fail_count=$((fail_count + 1))
      printf '  => FAIL (ship_order and frozen codex)\n'
    fi
  else
    fail_count=$((fail_count + 1))
    reasons=()
    [[ "$ship_order_ok" -eq 0 ]] && reasons+=("ship_order")
    [[ "$open_ok" -eq 0 ]] && reasons+=("Open!=0")
    printf '  => FAIL (%s)\n' "$(IFS=', '; echo "${reasons[*]}")"
  fi

  echo "  result: $result"
  echo
done

echo "Summary: PASS=$pass_count REMEDIATED_PASS=$remediated_count FAIL=$fail_count"

total_ok=$((pass_count + remediated_count))
if [[ "$total_ok" -eq 13 && "$fail_count" -eq 0 ]]; then
  exit 0
fi

exit 1