# Local PR Review — Design Spec

**Date:** 2026-06-27  
**Status:** Approved  
**Scope:** Local-only tooling under `docs/reviews/` (gitignored)  
**Entry point:** `just review` / `just review-strict`

---

## Summary

Add a local, gitignored PR review workflow that spins up **fresh** Grok and Codex agents with minimal review context — isolated from whatever implementation agent is currently working on a branch.

The workflow compares the **current branch against `main`**, intelligently surfaces **uncommitted changes** when the working tree is dirty, supports **parallel multi-agent runs** with **per-agent model overrides**, and optionally hooks into **pre-push** (advisory by default, strict when configured).

All machinery and output live under `docs/reviews/`, which is already excluded from git via `.gitignore`.

---

## Goals

- On-demand review via `just review` while another agent implements on the same branch
- Optional pre-push hook that reuses the same implementation
- Run Grok and Codex independently or in parallel
- Override model per agent (`--grok-model`, `--codex-model`)
- Fresh agent context: no session continuation, no cross-session memory, review-only instructions
- Branch-vs-`main` as the primary diff; include uncommitted work when present
- Write review artifacts to `docs/reviews/` in a consistent, browsable format
- **Mandatory skill loading:** always `using-superpowers` + `requesting-code-review`; auto-add domain skills from diff paths
- **Manual skill runs:** `--skill <name>` for edge-case deep dives (superpowers + named skill only)

## Non-goals

- GitHub PR integration (`gh pr diff`, pending reviews on GitHub)
- Tracked repo files beyond thin `justfile` recipes
- Blocking every push by default
- Replacing the in-session Grok `/review` bundled skill
- CI integration or shared team configuration
- Auto-fixing code or opening PRs from review findings

---

## Approach

**Selected: Thin shell orchestrator + agent profiles (A + C hybrid)**

A shared shell script (`docs/reviews/bin/review.sh`) handles diff collection, parallelism, output paths, and hook wiring. Review-specific behavior lives in small agent artifacts (`AGENTS.md`, `reviewer.grok.md`, `config.toml`) rather than embedding prompts in the script.

### Rejected alternatives

| Approach | Reason rejected |
|----------|-----------------|
| Justfile-only (inline shell) | Hard to maintain; awkward for parallel jobs and hook sharing |
| In-session `/review` skill only | Does not provide fresh context; inherits implementation agent state |
| `.local/` split tree | User preference: single home under `docs/reviews/` |
| Separate pass per skill | Too slow/expensive for routine use with parallel Grok + Codex |

---

## Directory layout

```
docs/reviews/
├── README.md                 # local install/usage (gitignored)
├── AGENTS.md                 # minimal shared review contract
├── skills.toml               # skill name → SKILL.md path registry
├── config.toml               # local defaults
├── reviewer.grok.md          # Grok agent profile (read-only reviewer)
├── bin/
│   └── review.sh             # shared implementation (command + hook)
├── hooks/
│   └── pre-push              # copied to .git/hooks/pre-push (one-time install)
└── <output files>            # e.g. 2026-06-27-feat-pr2a-grok.md
```

**Tracked change (repo root):** two `justfile` recipes only:

```just
review *FLAGS='':
    docs/reviews/bin/review.sh {{FLAGS}}

review-strict:
    docs/reviews/bin/review.sh --strict
```

Everything else under `docs/reviews/` stays gitignored via existing `docs/*` rule in `.gitignore`.

---

## Diff collection

### Primary target

Review the **committed branch diff** against `main`:

```bash
BASE="${BASE:-main}"
MERGE_BASE="$(git merge-base "$BASE" HEAD)"
COMMITTED_DIFF="$(git diff "$MERGE_BASE...HEAD")"
BRANCH="$(git branch --show-current)"
```

### Uncommitted changes (smart detection)

If the working tree is dirty (`git status --porcelain` non-empty):

1. Append a labeled **Uncommitted changes** section to the review prompt
2. Include `git diff HEAD` (staged + unstaged vs last commit)
3. Pass `--uncommitted` to `codex review` when dirty
4. Record `dirty: true` in metadata JSON

The **focus remains branch-vs-main**. Uncommitted work is surfaced so reviewers do not miss in-progress edits, but it is clearly separated from the branch diff.

### Guard rails

| Condition | Behavior |
|-----------|----------|
| Not on a branch (detached HEAD) | Exit with error message |
| `main` is the current branch | Exit with error (nothing to review vs base) |
| No diff vs merge-base and clean tree | Exit 0 with "nothing to review" message |
| `main` branch missing locally | Try `origin/main`; fail with clear error if absent |

---

## Agent invocation

### Grok (headless, fresh context)

```bash
grok -p "$(cat "$PROMPT_FILE")" \
  --cwd "$(git rev-parse --show-toplevel)" \
  --agent-profile docs/reviews/reviewer.grok.md \
  --no-memory \
  --always-approve \
  -m "${GROK_MODEL}" \
  --output-format plain \
  > "$OUTPUT_GROK"
```

**Isolation strategy:**

| Mechanism | Purpose |
|-----------|---------|
| `grok -p` (single-turn) | No `--continue`; one-shot session |
| `--agent-profile docs/reviews/reviewer.grok.md` | Review-only system prompt and toolset |
| `--no-memory` | Disable cross-session memory |
| `disallowedTools` in profile | Read-only review (no Write/Edit/Delete) |
| Read-only sandbox (if supported) | Prevent filesystem mutations |

**Fallback:** If root `AGENTS.md` still bleeds into context during testing, add `--system-prompt-override` loaded from `reviewer.grok.md` body (excluding frontmatter).

### Codex (native review)

```bash
codex review \
  --base "$BASE" \
  ${DIRTY:+--uncommitted} \
  -m "${CODEX_MODEL}" \
  < "$PROMPT_FILE" \
  > "$OUTPUT_CODEX"
```

Codex `review` subcommand handles branch diff natively. Shared `AGENTS.md` body is piped as supplemental instructions via stdin when non-empty.

### Parallelism

When both agents are selected and `parallel = true` (default):

```bash
run_grok &  GROK_PID=$!
run_codex & CODEX_PID=$!
wait "$GROK_PID" "$CODEX_PID"
```

`--no-parallel` runs agents sequentially (Codex first, then Grok) for easier log reading or rate-limit avoidance.

Exit code: non-zero if **any** invoked agent fails. In strict hook mode, a non-zero exit blocks push.

---

## Skill loading

**Selected: single pass with path-aware skill resolution** (not separate passes per skill).

### Always required (every run)

| Skill | Purpose |
|-------|---------|
| `using-superpowers` | Process discipline; how to use skills |
| `requesting-code-review` | Review lens and expectations |

### Auto-added from diff (default mode only)

| Diff signal | Skill |
|-------------|-------|
| Paths under `AppleBridge/` | `swiftui-pro` |
| Paths under `AppleBridgeTests/` | `swift-testing-pro` |
| Concurrency patterns (`@MainActor`, `@Observable`, `async`, `Sendable`, `FFI`, etc.) | `swift-concurrency-pro` |
| Paths under `rust/` | `rust-best-practices` |

Detection scans changed file paths plus committed + uncommitted diff text for concurrency patterns.

### Manual edge-case mode

```bash
just review --skill swift-concurrency-pro     # superpowers + named skill only
just review --skill swiftui-pro --skill swift-testing-pro
just review --skill swiftui-pro --with-auto   # named + auto-detected domain skills
```

| Mode | Skills loaded |
|------|---------------|
| **Default** (`just review`) | Always + auto from diff |
| **`--skill <name>`** | Always + named skill(s); **no** auto-detection |
| **`--skill <name> --with-auto`** | Always + named + auto |

Repeatable `--skill` flag. Unknown skill names exit with error listing valid names from `skills.toml`.

### Skill registry (`docs/reviews/skills.toml`)

Maps skill names to absolute `SKILL.md` paths (tilde-expanded). Keeps paths out of shell logic.

```toml
[skills]
using-superpowers = "~/.grok/installed-plugins/superpowers-21e2a56d/skills/using-superpowers/SKILL.md"
requesting-code-review = "~/.grok/installed-plugins/superpowers-21e2a56d/skills/requesting-code-review/SKILL.md"
swiftui-pro = "~/.agents/skills/swiftui-pro/SKILL.md"
swift-testing-pro = "~/.agents/skills/swift-testing-pro/SKILL.md"
swift-concurrency-pro = "~/.agents/skills/swift-concurrency-pro/SKILL.md"
rust-best-practices = "~/.agents/skills/rust-best-practices/SKILL.md"
```

### Prompt injection

The script appends a **Required skills** section listing resolved paths:

```markdown
## Required skills (mandatory)

Read every SKILL.md below before writing findings. Tag each finding with its skill: `(skill-name)`.

- using-superpowers: /Users/.../using-superpowers/SKILL.md
- requesting-code-review: /Users/.../requesting-code-review/SKILL.md
- swiftui-pro: /Users/.../swiftui-pro/SKILL.md
```

Reviewers must `Read` skill files (Grok has Read in profile). Do not review from general knowledge alone.

---

## Review `AGENTS.md` (shared contract)

Minimal instructions (~40 lines). Purpose: tell a fresh reviewer how to behave without loading the full repo `AGENTS.md` implementation playbook.

**Includes:**

- Role: code reviewer only; read-only; findings only, no fixes
- Scope: branch diff vs `main`; separate section for uncommitted changes when present
- Output format: match existing reviews in `docs/reviews/` (file path, line refs, severity, before/after snippets)
- Standards: consult `docs/conventions.md` when Swift (`AppleBridge/`) or Rust (`rust/`) paths appear in diff
- **Required skills:** read every `SKILL.md` path listed in the prompt; tag findings with `(skill-name)`

**Excludes:**

- TDD / implementation workflow mandates
- Branch naming, merge, or PR hygiene advice
- "Run tests" unless diff touches test infrastructure
- MCP server, UniFFI, or architecture bootstrap guidance unrelated to changed files

---

## Grok agent profile (`reviewer.grok.md`)

YAML frontmatter + markdown body. Example shape:

```yaml
---
name: pr-reviewer
description: Fresh-context PR reviewer for apple-bridge
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit, Delete, GenerateImage, SwitchMode
---
```

Body restates the shared contract: severity levels, required sections (Summary, Findings, Verification Note), and explicit "do not modify files."

---

## Configuration (`docs/reviews/config.toml`)

```toml
base = "main"

[agents]
default = ["grok", "codex"]
parallel = true

[grok]
model = ""          # empty = CLI default

[codex]
model = ""

[hook]
strict = false      # advisory pre-push
agents = ["grok", "codex"]   # hook may differ from CLI default later
```

**Precedence:** CLI flags > `config.toml` > built-in defaults.

### CLI flags

| Flag | Effect |
|------|--------|
| `--grok-only` | Run Grok only |
| `--codex-only` | Run Codex only |
| `--grok-model <ID>` | Override Grok model |
| `--codex-model <ID>` | Override Codex model |
| `--no-parallel` | Sequential execution |
| `--base <BRANCH>` | Override merge target (default `main`) |
| `--strict` | Wait for completion; non-zero exit on failure |
| `--skill <NAME>` | Superpowers + named skill only; repeatable; disables auto-detection |
| `--with-auto` | With `--skill`: also add auto-detected domain skills |
| `--hook` | Internal: called from pre-push hook (suppresses some interactive output) |

---

## Output artifacts

### Review files

**Default mode:**

```
docs/reviews/<YYYY-MM-DD>-<branch-slug>-grok.md
docs/reviews/<YYYY-MM-DD>-<branch-slug>-codex.md
```

**Manual `--skill` mode** (suffix avoids collisions):

```
docs/reviews/<YYYY-MM-DD>-<branch-slug>-<skill-slug>-grok.md
```

Multiple `--skill` flags: join slugs with `+` (e.g. `swiftui-pro+swift-testing-pro`).

`branch-slug`: current branch with `/` replaced by `-` (e.g. `feat-pr2a-rust-uniffi`).

### Metadata

```
docs/reviews/<YYYY-MM-DD>-<branch-slug>-meta.json
```

```json
{
  "date": "2026-06-27",
  "branch": "feat/pr2a-rust-uniffi",
  "base": "main",
  "merge_base_sha": "abc123...",
  "head_sha": "def456...",
  "dirty": false,
  "agents": ["grok", "codex"],
  "models": { "grok": "grok-composer-2.5-fast", "codex": "" },
  "parallel": true,
  "strict": false,
  "skills": ["using-superpowers", "requesting-code-review", "swiftui-pro"],
  "skill_mode": "auto",
  "duration_ms": 120000,
  "exit_codes": { "grok": 0, "codex": 0 }
}
```

`skill_mode`: `"auto"` (default), `"manual"` (`--skill` without `--with-auto`), or `"manual+auto"` (`--skill --with-auto`).

### Prompt file (ephemeral)

The script may write a temp prompt file under `docs/reviews/.tmp/` (gitignored by parent `docs/*` rule) or `/tmp/` with restrictive permissions (`umask 077`). Contains branch metadata + diff sections fed to both agents.

---

## Pre-push hook

**Source:** `docs/reviews/hooks/pre-push`  
**Install (one-time, local):**

```bash
cp docs/reviews/hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
```

**Implementation:**

```bash
#!/bin/sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
exec "$REPO_ROOT/docs/reviews/bin/review.sh" --hook ${REVIEW_STRICT:+--strict}
```

### Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Advisory** | Default (`config.toml` `[hook] strict = false`) | Fork review to background; push proceeds immediately; print output paths |
| **Strict** | `REVIEW_STRICT=1 git push` or `just review-strict` before push | Wait for all agents; block push on non-zero exit |

Advisory mode prints something like:

```
Review started in background (grok + codex). Watch:
  docs/reviews/2026-06-27-feat-pr2a-grok.md
  docs/reviews/2026-06-27-feat-pr2a-codex.md
```

Strict mode is intended for intentional gating; default stays non-blocking so parallel agent calls do not stall pushes.

---

## Usage examples

```bash
# Both agents, parallel, config defaults
just review

# Single agent
just review --codex-only
just review --grok-only

# Model overrides
just review --grok-model grok-composer-2.5-fast --codex-model o3

# Sequential
just review --no-parallel

# Blocking run (manual strict)
just review-strict

# Strict push
REVIEW_STRICT=1 git push

# Edge-case: concurrency deep dive (superpowers + one skill)
just review --skill swift-concurrency-pro

# Edge-case: SwiftUI + auto domain skills
just review --skill swiftui-pro --with-auto
```

---

## Error handling

| Failure | Behavior |
|---------|----------|
| `grok` or `codex` not in PATH | Clear error naming missing binary; exit 1 |
| Agent non-zero exit | Record in meta.json; exit 1 (strict/hook); advisory hook still allows push |
| Empty diff, clean tree | Exit 0, print "nothing to review" |
| Auth failure (grok login / codex login) | Surface CLI error; exit 1 |
| Partial parallel failure | Write whichever outputs completed; exit 1 |
| Unknown `--skill` name | List valid names from `skills.toml`; exit 1 |
| Skill file missing on disk | Warn in stderr; exit 1 |

---

## Security

- `umask 077` before writing prompt/diff temp files (may contain env snippets)
- Never log or write API tokens
- Review agents run read-only; Grok profile disallows write tools
- All artifacts gitignored; no secrets committed

---

## Testing / verification (implementation phase)

Manual smoke checklist:

1. On a feature branch with commits vs `main`: `just review` produces grok + codex output files
2. Dirty working tree: uncommitted section appears in prompt; codex gets `--uncommitted`
3. `--grok-only` / `--codex-only` run single agent
4. `--grok-model` overrides appear in meta.json
5. `--no-parallel` runs sequentially
6. Advisory hook: push completes while review runs in background
7. `REVIEW_STRICT=1 git push`: push blocked if review fails
8. On `main` branch: script exits with helpful error
9. Default review prompt lists superpowers + auto domain skills from diff
10. `--skill swift-concurrency-pro` produces suffixed output; prompt lists only superpowers + that skill
11. Unknown `--skill foo` lists valid skill names and exits 1

---

## Future tightening (out of scope for v1)

- Default hook to strict for specific branches
- `just review-install-hook` recipe
- Diff size limits / file filtering for large branches
- Summary markdown combining grok + codex findings
- Integration with `docs/superpowers/plans/` PR checklist
- Add `verification-before-completion` to always-required superpowers stack
- Two-pass hybrid (process pass + domain pass) if single-pass misses process issues

---

## References

- Existing review format: `docs/reviews/2026-06-27-pr1-review.md`
- Repo conventions: `docs/conventions.md`
- Grok headless: `grok -p`, `--agent-profile`, `--no-memory`
- Codex review: `codex review --base main [--uncommitted]`