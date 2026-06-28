# Local PR Review — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local, gitignored PR review tooling under `docs/reviews/` that runs fresh Grok and Codex agents against the current branch vs `main`, with optional advisory pre-push hook.

**Architecture:** Thin shell orchestrator (`bin/review.sh`) collects git diffs, resolves mandatory skills (always superpowers; auto domain skills from diff paths; or manual `--skill`), builds a shared prompt with `SKILL.md` paths, and invokes `grok -p` + `codex review` in parallel. Review behavior lives in `AGENTS.md`, `skills.toml`, `reviewer.grok.md`, and `config.toml`. Only `justfile` recipes are tracked in git.

**Tech Stack:** Bash, `just`, Grok CLI (`grok -p`), Codex CLI (`codex review`), Python 3 (`tomllib` for config), git hooks

**Spec:** `docs/superpowers/specs/2026-06-27-local-pr-review-design.md`

**Branch:** `chore/local-pr-review`

---

## File Map

| File | Responsibility |
|------|----------------|
| `docs/reviews/AGENTS.md` | Shared review contract (prompt body for both agents) |
| `docs/reviews/skills.toml` | Skill name → `SKILL.md` path registry |
| `docs/reviews/reviewer.grok.md` | Grok agent profile (read-only tools, review instructions) |
| `docs/reviews/config.toml` | Local defaults (base branch, agents, models, hook strictness) |
| `docs/reviews/bin/review.sh` | Main orchestrator (diff, prompt, agents, output, hook modes) |
| `docs/reviews/bin/review-selftest.sh` | Dry-run tests for git guards and flag parsing (no agent calls) |
| `docs/reviews/hooks/pre-push` | Thin wrapper installed to `.git/hooks/pre-push` |
| `docs/reviews/README.md` | Local install and usage docs |
| `justfile` | `review` and `review-strict` recipes |

---

### Task 1: Review agent artifacts

**Files:**
- Create: `docs/reviews/AGENTS.md`
- Create: `docs/reviews/skills.toml`
- Create: `docs/reviews/reviewer.grok.md`
- Create: `docs/reviews/config.toml`

- [ ] **Step 1: Create `docs/reviews/AGENTS.md`**

```markdown
# PR Reviewer — Apple Bridge

You are a **read-only code reviewer**. Find problems; do not fix them.

## Scope

- Primary: committed changes on the current branch vs `main`
- Secondary: if an **Uncommitted changes** section is present, review it separately — it is work in progress, not yet on the branch

## Standards

When the diff touches these paths, apply the matching conventions from `docs/conventions.md`:

- `AppleBridge/`, `AppleBridgeTests/` — Swift 6, SwiftUI, strict concurrency
- `rust/` — UniFFI, error handling, localhost-only MCP rules

## Output format

Write a markdown review with these sections:

1. **Header** — branch name, base branch, date
2. **Findings** — one subsection per issue:
   - File path and line reference
   - What is wrong and why it matters
   - Before/after code snippets when helpful
3. **Summary** — numbered list of highest-risk items
4. **Verification Note** — what you could or could not verify (tests, build)

## Required skills (mandatory)

Read every `SKILL.md` path listed in the prompt before writing findings.

- Tag each finding with the skill that surfaced it: `(skill-name)`
- Do not skip skill loading
- Do not review from general knowledge alone

## Rules

- Findings only — never edit files
- No implementation advice beyond the fix for each finding
- No branch naming, merge, or PR workflow commentary
- Do not demand TDD or test runs unless the diff changes test infrastructure
- Ignore unrelated files not in the diff
```

- [ ] **Step 2: Create `docs/reviews/skills.toml`**

```toml
[skills]
using-superpowers = "~/.grok/installed-plugins/superpowers-21e2a56d/skills/using-superpowers/SKILL.md"
requesting-code-review = "~/.grok/installed-plugins/superpowers-21e2a56d/skills/requesting-code-review/SKILL.md"
swiftui-pro = "~/.agents/skills/swiftui-pro/SKILL.md"
swift-testing-pro = "~/.agents/skills/swift-testing-pro/SKILL.md"
swift-concurrency-pro = "~/.agents/skills/swift-concurrency-pro/SKILL.md"
rust-best-practices = "~/.agents/skills/rust-best-practices/SKILL.md"
```

- [ ] **Step 3: Create `docs/reviews/reviewer.grok.md`**

```markdown
---
name: pr-reviewer
description: Fresh-context PR reviewer for apple-bridge
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit, Delete, GenerateImage, SwitchMode, StrReplace, ApplyPatch
---

# PR Reviewer

You review pull request diffs for apple-bridge. You are read-only.

Follow the review contract in your prompt. Required output sections: Findings, Summary, Verification Note.

Severity guidance:

- **Blocker** — correctness, security, or concurrency bug that will fail in production
- **Major** — user-visible bug or significant maintainability risk
- **Minor** — style, naming, or low-risk improvement

Do not modify any files. Do not run destructive commands.
```

- [ ] **Step 4: Create `docs/reviews/config.toml`**

```toml
base = "main"

[agents]
default = ["grok", "codex"]
parallel = true

[grok]
model = ""

[codex]
model = ""

[hook]
strict = false
agents = ["grok", "codex"]
```

- [ ] **Step 5: Verify files exist**

Run:
```bash
ls -la docs/reviews/AGENTS.md docs/reviews/skills.toml docs/reviews/reviewer.grok.md docs/reviews/config.toml
```
Expected: four files listed

---

### Task 2: Core review script — git guards and diff collection

**Files:**
- Create: `docs/reviews/bin/review.sh`

- [ ] **Step 1: Create `docs/reviews/bin/review.sh` with guards and diff helpers**

```bash
#!/usr/bin/env bash
set -euo pipefail
umask 077

REVIEW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(git -C "$REVIEW_ROOT" rev-parse --show-toplevel 2>/dev/null || git rev-parse --show-toplevel)"

# Defaults (overridden by config + CLI)
BASE="main"
AGENTS=("grok" "codex")
PARALLEL=true
STRICT=false
HOOK_MODE=false
DRY_RUN=false
GROK_MODEL=""
CODEX_MODEL=""
GROK_ONLY=false
CODEX_ONLY=false
WITH_AUTO=false
MANUAL_SKILLS=()
RESOLVED_SKILLS=()
SKILL_MODE="auto"
SKILL_SLUG=""

usage() {
  cat <<'EOF'
Usage: review.sh [OPTIONS]

Options:
  --grok-only           Run Grok only
  --codex-only          Run Codex only
  --grok-model MODEL    Override Grok model
  --codex-model MODEL   Override Codex model
  --no-parallel         Run agents sequentially
  --base BRANCH         Base branch (default: main)
  --skill NAME          Superpowers + named skill only; repeatable
  --with-auto           With --skill: also add auto-detected domain skills
  --strict              Wait for agents; exit non-zero on failure
  --hook                Called from pre-push hook
  --dry-run             Validate setup; do not invoke agents
  -h, --help            Show this help
EOF
}

load_config() {
  local cfg="$REVIEW_ROOT/config.toml"
  [[ -f "$cfg" ]] || return 0
  eval "$(python3 - "$cfg" <<'PY'
import sys, tomllib
cfg = tomllib.load(open(sys.argv[1], "rb"))
print(f'BASE={cfg.get("base", "main")!r}')
agents = cfg.get("agents", {})
print(f'PARALLEL={str(agents.get("parallel", True)).lower()!r}')
default_agents = agents.get("default", ["grok", "codex"])
print(f'DEFAULT_AGENTS={",".join(default_agents)!r}')
grok = cfg.get("grok", {})
codex = cfg.get("codex", {})
print(f'GROK_MODEL={grok.get("model", "")!r}')
print(f'CODEX_MODEL={codex.get("model", "")!r}')
hook = cfg.get("hook", {})
print(f'HOOK_STRICT={str(hook.get("strict", False)).lower()!r}')
hook_agents = hook.get("agents", agents.get("default", ["grok", "codex"]))
print(f'HOOK_AGENTS={",".join(hook_agents)!r}')
PY
)"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --grok-only) GROK_ONLY=true; AGENTS=("grok"); shift ;;
      --codex-only) CODEX_ONLY=true; AGENTS=("codex"); shift ;;
      --grok-model) GROK_MODEL="$2"; shift 2 ;;
      --codex-model) CODEX_MODEL="$2"; shift 2 ;;
      --no-parallel) PARALLEL=false; shift ;;
      --base) BASE="$2"; shift 2 ;;
      --skill) MANUAL_SKILLS+=("$2"); shift 2 ;;
      --with-auto) WITH_AUTO=true; shift ;;
      --strict) STRICT=true; shift ;;
      --hook) HOOK_MODE=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
}

resolve_base_ref() {
  if git -C "$REPO_ROOT" rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "$BASE"
  elif git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/$BASE" >/dev/null; then
    echo "origin/$BASE"
  else
    echo "error: base branch '$BASE' not found locally or as origin/$BASE" >&2
    exit 1
  fi
}

validate_branch() {
  local branch
  branch="$(git -C "$REPO_ROOT" branch --show-current)"
  if [[ -z "$branch" ]]; then
    echo "error: detached HEAD — checkout a branch to review" >&2
    exit 1
  fi
  if [[ "$branch" == "$BASE" ]]; then
    echo "error: already on '$BASE' — checkout a feature branch" >&2
    exit 1
  fi
  echo "$branch"
}

collect_diff_context() {
  local base_ref="$1"
  MERGE_BASE="$(git -C "$REPO_ROOT" merge-base "$base_ref" HEAD)"
  HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  COMMITTED_DIFF="$(git -C "$REPO_ROOT" diff "$MERGE_BASE...HEAD")"
  DIRTY=false
  UNCOMMITTED_DIFF=""
  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    DIRTY=true
    UNCOMMITTED_DIFF="$(git -C "$REPO_ROOT" diff HEAD)"
  fi
}

slugify_branch() {
  echo "$1" | tr '/' '-'
}

resolve_skills() {
  local changed_files="$1"
  local diff_text="$2"
  local json
  json="$(CHANGED_FILES="$changed_files" DIFF_TEXT="$diff_text" \
    MANUAL_SKILLS="${MANUAL_SKILLS[*]-}" WITH_AUTO="$WITH_AUTO" \
    python3 - "$REVIEW_ROOT/skills.toml" <<'PY'
import json, os, re, sys, tomllib

skills_file = sys.argv[1]
manual = [s for s in os.environ.get("MANUAL_SKILLS", "").split() if s]
with_auto = os.environ.get("WITH_AUTO", "") == "true"
changed = os.environ.get("CHANGED_FILES", "")
diff_text = os.environ.get("DIFF_TEXT", "")

registry = tomllib.load(open(skills_file, "rb")).get("skills", {})
ALWAYS = ["using-superpowers", "requesting-code-review"]
auto = []

if manual:
    skill_mode = "manual+auto" if with_auto else "manual"
else:
    skill_mode = "auto"
    if "AppleBridge/" in changed:
        auto.append("swiftui-pro")
    if "AppleBridgeTests/" in changed:
        auto.append("swift-testing-pro")
    if "rust/" in changed:
        auto.append("rust-best-practices")
    if re.search(r"@MainActor|@Observable|async\s+await|Sendable|FFI|@unchecked\s+Sendable", diff_text):
        auto.append("swift-concurrency-pro")

ordered, seen = [], set()
for group in (ALWAYS, manual, auto if (not manual or with_auto) else []):
    for skill in group:
        if skill not in seen:
            seen.add(skill)
            ordered.append(skill)

resolved = []
for skill in ordered:
    if skill not in registry:
        print(f"error: unknown skill '{skill}'", file=sys.stderr)
        print("valid:", ", ".join(sorted(registry)), file=sys.stderr)
        sys.exit(1)
    path = os.path.expanduser(registry[skill])
    if not os.path.isfile(path):
        print(f"error: skill file not found: {path}", file=sys.stderr)
        sys.exit(1)
    resolved.append({"name": skill, "path": path})

print(json.dumps({
    "skills": resolved,
    "skill_mode": skill_mode,
    "skill_slug": "+".join(manual) if manual else "",
}))
PY
)" || exit 1

  mapfile -t RESOLVED_SKILLS < <(python3 -c 'import json,sys; d=json.load(sys.stdin); [print(s["name"]) for s in d["skills"]]' <<<"$json")
  SKILL_MODE="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["skill_mode"])' <<<"$json")"
  SKILL_SLUG="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["skill_slug"])' <<<"$json")"
  SKILL_PATHS_JSON="$json"
}

build_output_paths() {
  local date branch_slug prefix
  date="$(date -u +%Y-%m-%d)"
  branch_slug="$(slugify_branch "$BRANCH")"
  prefix="${date}-${branch_slug}"
  [[ -n "$SKILL_SLUG" ]] && prefix="${prefix}-${SKILL_SLUG}"
  OUTPUT_PREFIX="$REVIEW_ROOT/${prefix}"
  OUTPUT_GROK="${OUTPUT_PREFIX}-grok.md"
  OUTPUT_CODEX="${OUTPUT_PREFIX}-codex.md"
  OUTPUT_META="${OUTPUT_PREFIX}-meta.json"
  PROMPT_FILE="$REVIEW_ROOT/.tmp/${prefix}-prompt.md"
  mkdir -p "$REVIEW_ROOT/.tmp"
}
```

- [ ] **Step 2: Make executable and syntax-check**

Run:
```bash
chmod +x docs/reviews/bin/review.sh
bash -n docs/reviews/bin/review.sh
```
Expected: no output (syntax OK)

---

### Task 3: Prompt builder and agent runners

**Files:**
- Modify: `docs/reviews/bin/review.sh` (append functions + main flow)

- [ ] **Step 1: Append prompt builder and agent functions to `review.sh`**

Append after `build_output_paths()`:

```bash
build_prompt_file() {
  cat > "$PROMPT_FILE" <<EOF
# Review request

- **Branch:** $BRANCH
- **Base:** $BASE
- **Merge base:** $MERGE_BASE
- **HEAD:** $HEAD_SHA
- **Dirty working tree:** $DIRTY

Review the branch diff below against $BASE. Focus on correctness, concurrency, and project conventions.

## Branch diff (committed changes vs $BASE)

\`\`\`diff
$COMMITTED_DIFF
\`\`\`
EOF

  if [[ "$DIRTY" == true ]]; then
    cat >> "$PROMPT_FILE" <<EOF

## Uncommitted changes (not yet on branch)

\`\`\`diff
$UNCOMMITTED_DIFF
\`\`\`
EOF
  fi

  cat >> "$PROMPT_FILE" <<'EOF'

## Required skills (mandatory)

Read every SKILL.md below before writing findings. Tag each finding with `(skill-name)`.

EOF

  python3 - "$SKILL_PATHS_JSON" <<'PY' >> "$PROMPT_FILE"
import json, sys
data = json.loads(sys.argv[1])
for skill in data["skills"]:
    print(f"- {skill['name']}: {skill['path']}")
PY

  if [[ -f "$REVIEW_ROOT/AGENTS.md" ]]; then
    cat >> "$PROMPT_FILE" <<'EOF'

## Review contract

EOF
    cat "$REVIEW_ROOT/AGENTS.md" >> "$PROMPT_FILE"
  fi
}

require_binaries() {
  local agent
  for agent in "${AGENTS[@]}"; do
    case "$agent" in
      grok)
        command -v grok >/dev/null || { echo "error: grok not found in PATH" >&2; exit 1; }
        ;;
      codex)
        command -v codex >/dev/null || { echo "error: codex not found in PATH" >&2; exit 1; }
        ;;
    esac
  done
}

run_grok() {
  local model_args=()
  [[ -n "$GROK_MODEL" ]] && model_args=(-m "$GROK_MODEL")
  grok -p "$(cat "$PROMPT_FILE")" \
    --cwd "$REPO_ROOT" \
    --agent-profile "$REVIEW_ROOT/reviewer.grok.md" \
    --no-memory \
    --always-approve \
    --output-format plain \
    "${model_args[@]}" \
    > "$OUTPUT_GROK"
}

run_codex() {
  local model_args=() uncommitted_args=()
  [[ -n "$CODEX_MODEL" ]] && model_args=(-m "$CODEX_MODEL")
  [[ "$DIRTY" == true ]] && uncommitted_args=(--uncommitted)
  codex review \
    --base "$BASE" \
    "${uncommitted_args[@]}" \
    "${model_args[@]}" \
    < "$PROMPT_FILE" \
    > "$OUTPUT_CODEX"
}

run_agents() {
  local start_ms end_ms exit_grok=0 exit_codex=0
  start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"

  if [[ "$DRY_RUN" == true ]]; then
    echo "dry-run: would run agents: ${AGENTS[*]}"
    echo "dry-run: prompt -> $PROMPT_FILE"
    echo "dry-run: outputs -> ${OUTPUT_PREFIX}-{grok,codex}.md"
    return 0
  fi

  require_binaries

  if [[ "$PARALLEL" == true && ${#AGENTS[@]} -gt 1 ]]; then
    for agent in "${AGENTS[@]}"; do
      case "$agent" in
        grok) run_grok & GROK_PID=$! ;;
        codex) run_codex & CODEX_PID=$! ;;
      esac
    done
    if [[ -n "${GROK_PID:-}" ]]; then wait "$GROK_PID" || exit_grok=$?; fi
    if [[ -n "${CODEX_PID:-}" ]]; then wait "$CODEX_PID" || exit_codex=$?; fi
  else
    for agent in "${AGENTS[@]}"; do
      case "$agent" in
        grok) run_grok || exit_grok=$? ;;
        codex) run_codex || exit_codex=$? ;;
      esac
    done
  fi

  end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
  DURATION_MS=$((end_ms - start_ms))

  write_meta_json "$exit_grok" "$exit_codex"

  if [[ $exit_grok -ne 0 || $exit_codex -ne 0 ]]; then
    echo "error: review failed (grok=$exit_grok codex=$exit_codex)" >&2
    return 1
  fi
  return 0
}

write_meta_json() {
  local exit_grok="$1" exit_codex="$2"
  python3 - "$OUTPUT_META" <<PY
import json, datetime
data = {
    "date": datetime.datetime.utcnow().strftime("%Y-%m-%d"),
    "branch": "$BRANCH",
    "base": "$BASE",
    "merge_base_sha": "$MERGE_BASE",
    "head_sha": "$HEAD_SHA",
    "dirty": $([[ "$DIRTY" == true ]] && echo True || echo False),
    "agents": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${AGENTS[@]}"),
    "models": {"grok": "$GROK_MODEL", "codex": "$CODEX_MODEL"},
    "parallel": $([[ "$PARALLEL" == true ]] && echo True || echo False),
    "strict": $([[ "$STRICT" == true ]] && echo True || echo False),
    "skills": $(python3 -c 'import json,sys; print(json.dumps([s["name"] for s in json.loads(sys.argv[1])["skills"]]))' "$SKILL_PATHS_JSON"),
    "skill_mode": "$SKILL_MODE",
    "duration_ms": ${DURATION_MS:-0},
    "exit_codes": {"grok": $exit_grok, "codex": $exit_codex},
    "outputs": {
        "grok": "$OUTPUT_GROK",
        "codex": "$OUTPUT_CODEX"
    }
}
with open("$OUTPUT_META", "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}
```

- [ ] **Step 2: Syntax-check**

Run:
```bash
bash -n docs/reviews/bin/review.sh
```
Expected: no output

---

### Task 4: Main entry, hook modes, and empty-diff guard

**Files:**
- Modify: `docs/reviews/bin/review.sh` (append `main`)

- [ ] **Step 1: Append `main` and hook background logic**

Append to `review.sh`:

```bash
maybe_background_hook() {
  # Advisory hook: re-exec without --hook in background, then exit 0 so push proceeds
  if [[ "$HOOK_MODE" == true && "$STRICT" != true ]]; then
    local -a bg_args=(--base "$BASE")
    [[ "$GROK_ONLY" == true ]] && bg_args+=(--grok-only)
    [[ "$CODEX_ONLY" == true ]] && bg_args+=(--codex-only)
    [[ -n "$GROK_MODEL" ]] && bg_args+=(--grok-model "$GROK_MODEL")
    [[ -n "$CODEX_MODEL" ]] && bg_args+=(--codex-model "$CODEX_MODEL")
    [[ "$PARALLEL" != true ]] && bg_args+=(--no-parallel)
    echo "Starting PR review in background (${AGENTS[*]})..."
    "$REVIEW_ROOT/bin/review.sh" "${bg_args[@]}" &
    echo "Watch outputs under: $REVIEW_ROOT/"
    exit 0
  fi
}

main() {
  load_config
  parse_args "$@"

  # Apply config default agents unless CLI narrowed selection
  if [[ "$GROK_ONLY" != true && "$CODEX_ONLY" != true && -n "${DEFAULT_AGENTS:-}" ]]; then
    IFS=',' read -r -a AGENTS <<< "$DEFAULT_AGENTS"
  fi

  # Hook mode uses hook-specific agent list unless CLI narrowed it
  if [[ "$HOOK_MODE" == true && "$GROK_ONLY" != true && "$CODEX_ONLY" != true && -n "${HOOK_AGENTS:-}" ]]; then
    IFS=',' read -r -a AGENTS <<< "$HOOK_AGENTS"
  fi

  # Config strict applies to hook when CLI did not pass --strict
  if [[ "$HOOK_MODE" == true && "$STRICT" != true && "${HOOK_STRICT:-false}" == true ]]; then
    STRICT=true
  fi

  maybe_background_hook

  BASE_REF="$(resolve_base_ref)"
  BRANCH="$(validate_branch)"
  collect_diff_context "$BASE_REF"
  CHANGED_FILES="$(git -C "$REPO_ROOT" diff --name-only "$MERGE_BASE...HEAD" 2>/dev/null; git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null || true)"
  resolve_skills "$CHANGED_FILES" "$COMMITTED_DIFF$UNCOMMITTED_DIFF"
  build_output_paths

  if [[ -z "$COMMITTED_DIFF" && "$DIRTY" != true ]]; then
    echo "nothing to review (no diff vs $BASE and clean working tree)"
    exit 0
  fi

  build_prompt_file

  echo "Reviewing $BRANCH vs $BASE (${AGENTS[*]})..."
  if run_agents; then
    echo "Review complete:"
    for agent in "${AGENTS[@]}"; do
      case "$agent" in
        grok) echo "  $OUTPUT_GROK" ;;
        codex) echo "  $OUTPUT_CODEX" ;;
      esac
    done
    echo "  $OUTPUT_META"
    exit 0
  fi
  exit 1
}

main "$@"
```

- [ ] **Step 2: Dry-run smoke on current branch**

Run:
```bash
docs/reviews/bin/review.sh --dry-run
```
Expected: prints agents list and output paths; exit 0 (or branch guard error if on `main`)

- [ ] **Step 3: Syntax-check final script**

Run:
```bash
bash -n docs/reviews/bin/review.sh
```
Expected: no output

---

### Task 5: Pre-push hook and README

**Files:**
- Create: `docs/reviews/hooks/pre-push`
- Create: `docs/reviews/README.md`

- [ ] **Step 1: Create `docs/reviews/hooks/pre-push`**

```bash
#!/bin/sh
set -eu

REPO_ROOT="$(git rev-parse --show-toplevel)"
REVIEW_SCRIPT="$REPO_ROOT/docs/reviews/bin/review.sh"

if [ ! -x "$REVIEW_SCRIPT" ]; then
  echo "review: skipping — $REVIEW_SCRIPT not found" >&2
  exit 0
fi

if [ -n "${REVIEW_STRICT:-}" ]; then
  exec "$REVIEW_SCRIPT" --hook --strict
fi

exec "$REVIEW_SCRIPT" --hook
```

- [ ] **Step 2: Make hook executable**

Run:
```bash
chmod +x docs/reviews/hooks/pre-push
```

- [ ] **Step 3: Create `docs/reviews/README.md`**

```markdown
# Local PR Review

Gitignored tooling to run fresh Grok and Codex reviews against the current branch vs `main`.

## Quick start

```bash
just review                  # both agents, parallel
just review --codex-only     # single agent
just review-strict           # blocking run
```

## Install pre-push hook (optional)

```bash
cp docs/reviews/hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

Advisory by default (push proceeds). Strict push:

```bash
REVIEW_STRICT=1 git push
```

## Configuration

Edit `docs/reviews/config.toml` for defaults (base branch, models, agents, hook strictness).

## Output

Reviews land in this directory:

```
docs/reviews/2026-06-27-feat-pr2a-grok.md
docs/reviews/2026-06-27-feat-pr2a-codex.md
docs/reviews/2026-06-27-feat-pr2a-meta.json
```

## Flags

| Flag | Effect |
|------|--------|
| `--grok-only` / `--codex-only` | Single agent |
| `--grok-model` / `--codex-model` | Model override |
| `--no-parallel` | Sequential |
| `--base` | Override base branch |
| `--strict` | Block on failure |
| `--skill NAME` | Superpowers + named skill; repeatable |
| `--with-auto` | With `--skill`: also auto-detect domain skills |
| `--dry-run` | Validate without calling agents |

## Skill modes

| Command | Skills loaded |
|---------|---------------|
| `just review` | superpowers + auto from diff |
| `just review --skill swift-concurrency-pro` | superpowers + named only |
| `just review --skill swiftui-pro --with-auto` | superpowers + named + auto |
```

---

### Task 6: Self-test script

**Files:**
- Create: `docs/reviews/bin/review-selftest.sh`

- [ ] **Step 1: Create self-test script**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
REVIEW_SH="$REPO_ROOT/docs/reviews/bin/review.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[[ -x "$REVIEW_SH" ]] || fail "review.sh not executable"

# Help exits 0
"$REVIEW_SH" --help >/dev/null || fail "--help should exit 0"
pass "--help"

# Dry-run on feature branch (skip if on main)
BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "main" ]]; then
  "$REVIEW_SH" --dry-run >/dev/null || fail "--dry-run on feature branch"
  pass "--dry-run on $BRANCH"
else
  echo "SKIP: on main — dry-run branch test"
fi

# Unknown skill error
if "$REVIEW_SH" --skill not-a-real-skill 2>/dev/null; then
  fail "--skill unknown should exit non-zero"
fi
pass "unknown --skill rejected"

# Main branch guard
if [[ "$BRANCH" == "main" ]]; then
  if "$REVIEW_SH" --dry-run 2>/dev/null; then
    fail "should error on main"
  fi
  pass "main branch guard"
fi

echo "All self-tests passed"
```

- [ ] **Step 2: Run self-tests**

Run:
```bash
chmod +x docs/reviews/bin/review-selftest.sh
docs/reviews/bin/review-selftest.sh
```
Expected: `All self-tests passed` (or SKIP for main-branch dry-run if not on main)

---

### Task 7: Justfile recipes

**Files:**
- Modify: `justfile`

- [ ] **Step 1: Add review recipes to `justfile`**

Append after the header comment:

```just
review *FLAGS='':
    docs/reviews/bin/review.sh {{FLAGS}}

review-strict:
    docs/reviews/bin/review.sh --strict
```

- [ ] **Step 2: Verify just parses recipes**

Run:
```bash
just --list | grep review
```
Expected:
```
review ...
review-strict
```

- [ ] **Step 3: Dry-run via just**

Run:
```bash
just review --dry-run
```
Expected: dry-run output; exit 0 (unless on `main`)

---

### Task 8: Grok isolation fallback (only if needed)

**Files:**
- Modify: `docs/reviews/bin/review.sh` (`run_grok` function)

- [ ] **Step 1: Run a real Grok-only review on a feature branch**

Run (requires `grok login` and a feature branch with commits vs `main`):
```bash
just review --grok-only
```
Expected: `docs/reviews/<date>-<branch>-grok.md` created with findings

- [ ] **Step 2: If root AGENTS.md bleeds into review (implementation workflow language), add system prompt override**

Replace `run_grok()` with:

```bash
run_grok() {
  local model_args=() profile_body
  [[ -n "$GROK_MODEL" ]] && model_args=(-m "$GROK_MODEL")

  # Strip YAML frontmatter from reviewer profile for override body
  profile_body="$(python3 - "$REVIEW_ROOT/reviewer.grok.md" <<'PY'
import sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
if text.startswith("---"):
    end = text.find("---", 3)
    text = text[end + 3:].lstrip("\n") if end != -1 else text
print(text)
PY
)"

  grok -p "$(cat "$PROMPT_FILE")" \
    --cwd "$REPO_ROOT" \
    --system-prompt-override "$profile_body" \
    --no-memory \
    --always-approve \
    --output-format plain \
    "${model_args[@]}" \
    > "$OUTPUT_GROK"
```

Re-run `just review --grok-only` and confirm output no longer references implementation/TDD mandates unrelated to the diff.

---

### Task 9: End-to-end manual verification

**Files:** none (verification only)

- [ ] **Step 1: Feature branch + both agents**

On a branch with commits vs `main`:
```bash
just review
```
Expected: grok + codex output files + meta.json; meta shows `"parallel": true`

- [ ] **Step 2: Model override**

```bash
just review --grok-model grok-composer-2.5-fast --codex-only
```
Expected: only codex output; meta.json `models.codex` reflects override if passed

- [ ] **Step 3: Dirty tree**

Make a trivial unstaged edit, then:
```bash
just review --dry-run
cat docs/reviews/.tmp/*-prompt.md | tail -20
```
Expected: prompt contains `Uncommitted changes` section

- [ ] **Step 4: Advisory hook**

```bash
cp docs/reviews/hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
git push --dry-run 2>&1 | head -5
```
Expected: hook prints background-start message; dry-run push does not hang

- [ ] **Step 5: Commit tracked changes only**

```bash
git add justfile
git status
```
Expected: only `justfile` staged — `docs/reviews/` remains untracked/gitignored

```bash
git commit -m "chore: add just review recipes for local PR review tooling"
```

---

### Task 10: Skill resolution verification

**Files:** none (verification only)

- [ ] **Step 1: Default mode lists superpowers + auto skills**

On a feature branch with Swift changes:
```bash
just review --dry-run
cat docs/reviews/.tmp/*-prompt.md | grep -A20 "Required skills"
```
Expected: includes `using-superpowers`, `requesting-code-review`, and auto skills matching diff paths

- [ ] **Step 2: Manual skill mode**

```bash
just review --skill swift-concurrency-pro --dry-run
ls docs/reviews/.tmp/*swift-concurrency-pro*prompt.md 2>/dev/null || \
  cat docs/reviews/.tmp/*-swift-concurrency-pro*prompt.md | grep "swift-concurrency-pro"
```
Expected: prompt lists superpowers + `swift-concurrency-pro` only; output prefix includes `swift-concurrency-pro`

- [ ] **Step 3: Unknown skill error**

```bash
just review --skill not-a-real-skill 2>&1 | head -5
```
Expected: `unknown skill` error listing valid names from `skills.toml`; exit 1

- [ ] **Step 4: Meta records skills**

After a real `--codex-only` run:
```bash
cat docs/reviews/*-meta.json | python3 -m json.tool | grep -A3 skills
```
Expected: `skills` array and `skill_mode` field populated

---

## Spec Coverage Checklist

| Spec requirement | Task |
|------------------|------|
| `docs/reviews/` layout | Tasks 1, 2, 5 |
| Branch vs `main` diff | Task 2 (`collect_diff_context`) |
| Uncommitted smart detection | Tasks 3, 4 |
| Grok fresh context | Tasks 3, 8 |
| Codex `review --base` | Task 3 |
| Parallel + model overrides | Tasks 3, 4 |
| `config.toml` defaults | Task 1 |
| Output naming + meta.json | Tasks 3, 4 |
| Advisory + strict hook | Tasks 4, 5 |
| `just review` / `just review-strict` | Task 7 |
| Always superpowers skills | Tasks 1, 2 (`skills.toml`, `resolve_skills`) |
| Auto domain skills from diff | Task 2 (`resolve_skills`) |
| `--skill` / `--with-auto` manual mode | Tasks 2, 4 (`parse_args`, `resolve_skills`) |
| Suffixed output for manual skill runs | Task 2 (`build_output_paths`) |
| Security (`umask 077`) | Task 2 |
| Manual verification matrix | Tasks 6, 9, 10 |

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-27-local-pr-review.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — run tasks in this session with checkpoints

Which approach?