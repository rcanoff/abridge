# Review: `chore/ci-pipelines-readme` vs `main` (2026-06-27)

## Findings

### Important: `ServerOperationError` was made non-`Sendable` even though it crosses actor boundaries `(swift-concurrency-pro)`
- Evidence: [AppleBridge/Services/ServerService.swift] removes `Sendable` from `ServerOperationError` at the top of the file, while the same actor still throws it from `start()` / `stop()` and callers on `@MainActor` catch it in [AppleBridge/Models/ServerStore.swift]. The test double actor also accepts and stores it across isolation boundaries in [AppleBridgeTests/MockServerService.swift].
- What’s wrong: a non-`Sendable` error type is now being transferred across actor isolation. Under strict concurrency, that is exactly the kind of boundary Swift checks.
- Why it matters: this is likely to turn into a strict-concurrency compile failure or force the codebase into weaker isolation assumptions right where the app/server boundary is supposed to stay clean.
- Fix: restore `Sendable` on `ServerOperationError` (and keep boundary-crossing payloads `Sendable`), or redesign the actor API so the non-`Sendable` type never leaves actor isolation.

### Important: the pre-push verifier only validates the last ref from hook stdin `(requesting-code-review)`
- Evidence: in [scripts/ci/pre-push-verify.sh], lines around the `while read -r _local_ref local_oid _remote_ref remote_oid; do ... done` loop overwrite `HEAD_REF` and `REMOTE_OID` for each row, then the script computes paths from only the final values.
- What’s wrong: `git` can invoke `pre-push` with multiple refs. This script silently ignores every ref except the last one.
- Why it matters: a multi-ref push can report a clean pre-push result even though earlier refs were never checked, which undermines the new hook’s stated purpose as path-aware verification.
- Fix: iterate and verify each ref range independently, or explicitly reject multi-ref pushes with a clear message.

### Minor: workflow path filters do not match the new “Any PR” CI policy documented in `AGENTS.md` `(requesting-code-review)`
- Evidence: [AGENTS.md] adds `Any PR | just ci (or equivalent GitHub workflow checks)` to the verification matrix, but [`.github/workflows/ci-macos.yml`] and [`.github/workflows/ci-rust.yml`] only trigger for selected code/tooling paths and exclude files such as `README.md`, `AGENTS.md`, and `docs/conventions.md`.
- What’s wrong: a docs-only or policy-only PR now has no “equivalent GitHub workflow checks,” despite the updated repo guidance saying every PR should have them.
- Why it matters: the branch updates contributor-facing CI expectations, but the actual workflow triggers still allow PRs that bypass all checks.
- Fix: either widen the workflow path filters to cover all PRs, or narrow the wording in `AGENTS.md` / `README.md` so it accurately describes the real trigger scope.

## Summary

1. `ServerOperationError` losing `Sendable` is the highest-risk change because it directly conflicts with strict actor-boundary concurrency.
2. The new pre-push hook has an edge-case correctness bug: only the last pushed ref is verified.
3. The documented “Any PR” CI policy is broader than the workflows actually enforce.

## Verification Note

Assessed only from the provided diff, inventory, existing code context, and inlined skills. I could evaluate boundary-safety, hook logic, and workflow/documentation alignment from the prompt alone; runtime behavior, exact compiler diagnostics, and CI execution results are not visible in the diff.