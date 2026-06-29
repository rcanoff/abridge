#!/usr/bin/env bash
# Extract completed AGENTS.md Read tool results from a Grok session updates.jsonl.
# Writes per-read logs and a PR-merge → nearest-preceding-read map for epic #90 (#145–#160).
set -euo pipefail

DEFAULT_SESSION_JSONL="/Users/rcanoff/.grok/sessions/%2FUsers%2Frcanoff%2FProjects%2Fapple-bridge/019f13d4-b445-7f03-b2ae-f8072709b96f/updates.jsonl"
DEFAULT_SCRATCH="/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-de5944b6527a/implementer"

SESSION_JSONL="${1:-$DEFAULT_SESSION_JSONL}"
SCRATCH="${2:-$DEFAULT_SCRATCH}"

if [[ ! -f "$SESSION_JSONL" ]]; then
  echo "error: SESSION_JSONL not found: $SESSION_JSONL" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 required" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI required for PR merge timestamps" >&2
  exit 1
fi

mkdir -p "$SCRATCH"

deleted_fabrications=0
while IFS= read -r -d '' f; do
  rm -f "$f"
  deleted_fabrications=$((deleted_fabrications + 1))
done < <(find "$SCRATCH" -maxdepth 1 -name 'agents-refresh-subtask-*.log' -print0 2>/dev/null || true)

if [[ -f "$SCRATCH/agents-refresh-log.md" ]]; then
  rm -f "$SCRATCH/agents-refresh-log.md"
  deleted_fabrications=$((deleted_fabrications + 1))
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SESSION_JSONL SCRATCH REPO_ROOT

python3 <<'PY'
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

session_jsonl = Path(os.environ["SESSION_JSONL"])
scratch = Path(os.environ["SCRATCH"])

AGENTS_PATHS = {
    "/Users/rcanoff/.grok/AGENTS.md": "global",
    "/Users/rcanoff/Projects/apple-bridge/AGENTS.md": "project",
    "/Users/rcanoff/Projects/apple-bridge/rust/AGENTS.md": "rust",
}

# Session jsonl uses Agents.md; repo/docs use AGENTS.md — normalize before matching.
PATH_ALIASES = {
    "/Users/rcanoff/Projects/apple-bridge/Agents.md": "/Users/rcanoff/Projects/apple-bridge/AGENTS.md",
}

# Index display paths (session jsonl spelling where it differs from canonical).
INDEX_DISPLAY_PATHS = {
    "/Users/rcanoff/Projects/apple-bridge/AGENTS.md": "/Users/rcanoff/Projects/apple-bridge/Agents.md",
}


def canonical_path(path: str) -> str:
    return PATH_ALIASES.get(path, path)


def is_partial_read(offset, limit) -> bool:
    if limit is not None:
        return True
    if offset is not None and offset != 0:
        return True
    return False

EPIC_PRS = [
    ("145", "144", "feat/contacts-permissions-foundation"),
    ("146", "91", "feat/contacts-list-contacts"),
    ("147", "92", "feat/contacts-search-contacts"),
    ("148", "93", "feat/contacts-get-contact"),
    ("152", "94", "feat/contacts-create-contact"),
    ("153", "95", "feat/contacts-update-contact"),
    ("154", "96", "feat/contacts-delete-contact"),
    ("155", "99", "feat/contacts-list-groups"),
    ("156", "100", "feat/contacts-create-group"),
    ("157", "101", "feat/contacts-update-group"),
    ("158", "102", "feat/contacts-delete-group"),
    ("159", "97", "feat/contacts-link-contacts"),
    ("160", "98", "feat/contacts-unlink-contacts"),
]


def iso_utc(ts):
    if ts is None:
        return "unknown"
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def extract_text(content) -> str:
    parts = []
    for block in content or []:
        if not isinstance(block, dict):
            continue
        inner = block.get("content")
        if isinstance(inner, dict) and inner.get("type") == "text":
            parts.append(inner.get("text", ""))
        elif isinstance(inner, str):
            parts.append(inner)
    return "".join(parts).strip()


def safe_filename(tool_call_id: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_.-]", "_", tool_call_id)


pending = {}
reads = []
all_reads = []
logs_written = 0
per_path_counts = {path: 0 for path in AGENTS_PATHS}
index_path_counts = {path: 0 for path in AGENTS_PATHS}

for line in session_jsonl.read_text().splitlines():
    if not line.strip():
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue

    ts = obj.get("timestamp")
    upd = obj.get("params", {}).get("update", {})
    kind = upd.get("sessionUpdate")

    if kind == "tool_call":
        raw = upd.get("rawInput") or {}
        path = raw.get("path")
        tool_call_id = upd.get("toolCallId")
        canon = canonical_path(path) if path else None
        if canon in AGENTS_PATHS and tool_call_id:
            pending[tool_call_id] = {
                "ts": ts,
                "path": canon,
                "offset": raw.get("offset"),
                "limit": raw.get("limit"),
            }
        continue

    if kind != "tool_call_update":
        continue

    tool_call_id = upd.get("toolCallId")
    if not tool_call_id:
        continue

    raw = upd.get("rawInput") or {}
    raw_path = raw.get("path")
    canon_path = canonical_path(raw_path) if raw_path else None
    if canon_path in AGENTS_PATHS:
        meta = pending.setdefault(
            tool_call_id,
            {
                "ts": ts,
                "path": canon_path,
                "offset": raw.get("offset"),
                "limit": raw.get("limit"),
            },
        )
    elif tool_call_id not in pending:
        continue
    else:
        meta = pending[tool_call_id]

    if upd.get("status") != "completed":
        continue

    body = extract_text(upd.get("content"))
    if not body:
        raw_output = upd.get("rawOutput")
        if isinstance(raw_output, dict):
            body = (raw_output.get("output_for_prompt") or "").strip()

    if not body:
        continue

    read_ts = ts if ts is not None else meta["ts"]
    out_name = f"agents-refresh-{safe_filename(tool_call_id)}.log"
    out_path = scratch / out_name

    partial = is_partial_read(meta.get("offset"), meta.get("limit"))

    header_lines = [
        f"read_utc: {iso_utc(read_ts)}",
        f"path: {meta['path']}",
        f"toolCallId: {tool_call_id}",
    ]
    if partial:
        header_lines.append("partial: true")
    if meta.get("offset") is not None or meta.get("limit") is not None:
        header_lines.append(f"offset: {meta.get('offset')}")
        header_lines.append(f"limit: {meta.get('limit')}")
    header_lines.append("---")

    out_path.write_text("\n".join(header_lines) + "\n" + body + "\n", encoding="utf-8")
    logs_written += 1

    nbytes = len(body.encode("utf-8"))
    all_reads.append(
        {
            "ts": read_ts,
            "path": meta["path"],
            "toolCallId": tool_call_id,
            "bytes": nbytes,
            "partial": partial,
        }
    )
    index_path_counts[meta["path"]] += 1

    if not partial:
        reads.append(
            {
                "ts": read_ts,
                "path": meta["path"],
                "toolCallId": tool_call_id,
                "log": out_name,
                "bytes": nbytes,
            }
        )
        per_path_counts[meta["path"]] += 1
    pending.pop(tool_call_id, None)

reads.sort(key=lambda r: (r["ts"], r["path"], r["toolCallId"]))
all_reads.sort(key=lambda r: (r["ts"], r["path"], r["toolCallId"]))

extracted_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
index_lines = [
    "# agents-refresh-jsonl-index.txt",
    f"source: {session_jsonl}",
    f"extracted_utc: {extracted_utc}",
    "",
]

for path, label in AGENTS_PATHS.items():
    display_path = INDEX_DISPLAY_PATHS.get(path, path)
    path_reads = [r for r in all_reads if r["path"] == path]
    index_lines.append(f"## {label}: {display_path}")
    index_lines.append(f"count: {len(path_reads)}")
    for r in path_reads:
        index_lines.append(
            f"  - {iso_utc(r['ts'])} toolCallId={r['toolCallId']} bytes={r['bytes']}"
        )
    index_lines.append("")

index_path = scratch / "agents-refresh-jsonl-index.txt"
index_path.write_text("\n".join(index_lines) + "\n", encoding="utf-8")

repo_root = Path(os.environ["REPO_ROOT"])

merge_lines = [
    "# agents-refresh-by-merge.txt",
    f"source: {session_jsonl}",
    f"generated_utc: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
    "mapping: nearest preceding completed Read per AGENTS file before each epic PR merge",
    "",
]

merge_pass = 0
paths_needed = list(AGENTS_PATHS.keys())

for pr, issue, branch in EPIC_PRS:
    try:
        merged_at = subprocess.check_output(
            ["gh", "pr", "view", pr, "--json", "mergedAt", "--jq", ".mergedAt"],
            cwd=repo_root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip().strip('"')
    except subprocess.CalledProcessError:
        merged_at = ""

    if not merged_at:
        merge_lines.append(f"## PR #{pr} (issue #{issue}, {branch}) — mergedAt: unknown")
        for path in paths_needed:
            merge_lines.append(f"  - {path}: MISSING (no merge timestamp)")
        merge_lines.append("")
        continue

    merge_ts = datetime.fromisoformat(merged_at.replace("Z", "+00:00")).timestamp()
    prior = [r for r in reads if r["ts"] <= merge_ts]
    picked = {}
    for path in paths_needed:
        for r in reversed(prior):
            if r["path"] == path:
                picked[path] = r
                break

    complete = all(path in picked for path in paths_needed)
    if complete:
        merge_pass += 1

    merge_lines.append(
        f"## PR #{pr} (issue #{issue}, {branch}) — mergedAt: {merged_at}"
    )
    for path in paths_needed:
        label = AGENTS_PATHS[path]
        if path in picked:
            r = picked[path]
            merge_lines.append(
                f"  - [{label}] {path}: {r['log']} "
                f"(read {iso_utc(r['ts'])}, {r['bytes']} bytes, toolCallId={r['toolCallId']})"
            )
        else:
            merge_lines.append(f"  - [{label}] {path}: MISSING before merge")
    merge_lines.append(f"  gate: {'PASS' if complete else 'FAIL'} (nearest preceding read per file)")
    merge_lines.append("")

merge_lines.insert(4, f"summary: {merge_pass}/{len(EPIC_PRS)} PR merges have preceding read for all three AGENTS files")
merge_lines.insert(5, "")

merge_path = scratch / "agents-refresh-by-merge.txt"
merge_path.write_text("\n".join(merge_lines) + "\n", encoding="utf-8")

print(f"extract-agents-reads-from-jsonl")
print(f"  SESSION_JSONL: {session_jsonl}")
print(f"  SCRATCH: {scratch}")
print(f"  log files written: {logs_written} ({len(reads)} full reads for merge mapping)")
for path, label in AGENTS_PATHS.items():
    print(f"  {label} ({path}): {per_path_counts[path]} full reads")
print(f"  jsonl-index: {index_path}")
for path, label in AGENTS_PATHS.items():
    print(f"  jsonl-index {label}: {index_path_counts[path]} reads")
print(f"  merge mapping: {merge_path}")
print(f"  merge gates PASS: {merge_pass}/{len(EPIC_PRS)}")
PY

echo "  deleted fabrication artifacts: ${deleted_fabrications}"