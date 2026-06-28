# Review — `chore/ci-pipelines-readme` vs `main` — 2026-06-28

## Findings

### 1. Swift build/test is no longer part of the required merge gate, which conflicts with the repo’s own verification standard `(requesting-code-review)`
- Evidence:
  - [`.github/workflows/ci-pr-gate.yml`](.github/workflows/ci-pr-gate.yml) only runs `just fmt-check-swift` and `just lint-swift` for Swift-path changes, then explicitly says `Swift build/tests run in macOS CI (path-filtered).`
  - [`docs/conventions.md`](docs/conventions.md) now says `Set PR Gate as the required branch-protection check. Rust/macOS workflows are supplementary`.
  - [`AGENTS.md`](AGENTS.md) still defines the minimum validation for `SwiftUI / store` as `Build + unit tests`.
- What’s wrong:
  - The only workflow documented as required is the Linux PR gate, but that workflow does not compile or test Swift code.
- Why it matters:
  - A Swift PR can satisfy the documented required check without ever meeting the project’s stated minimum validation for Swift changes.
- Fix:
  - Either make `macOS CI` a required check for Swift-touching PRs, or move a compile/test step into the required gate.

### 2. The path filters classify `.githooks/README.md` as code, so some docs-only changes still fan out into full CI `(requesting-code-review)`
- Evidence:
  - [`.github/workflows/ci-macos.yml`](.github/workflows/ci-macos.yml) includes `.githooks/**` in its trigger paths.
  - [`scripts/ci/paths.sh`](scripts/ci/paths.sh) marks `.githooks/*` as both `PATHS_RUST_CHANGED=1` and `PATHS_SWIFT_CHANGED=1`.
  - This branch itself adds [`.githooks/README.md`](.githooks/README.md), which is documentation, not executable hook logic.
- What’s wrong:
  - The docs-only fast path described in the README is not actually true for hook documentation changes.
- Why it matters:
  - It needlessly burns Rust and macOS CI time on non-code edits, which undercuts the branch’s stated goal of path-aware, cheap pipelines.
- Fix:
  - Narrow the hook-related filters to executable hook files such as `.githooks/pre-push`, or explicitly exclude `.githooks/README.md`.

## Summary

1. The documented required check no longer guarantees Swift build + unit test coverage for Swift PRs.
2. The path classifier is too broad around `.githooks/`, so some documentation-only changes still trigger full CI.

## Verification Note

Assessed only from the provided diff, inventory, existing code context, and inlined skills. I could evaluate workflow logic, trigger coverage, and consistency with repo standards; I could not confirm actual GitHub branch-protection settings or runtime CI behavior beyond what the diff shows.