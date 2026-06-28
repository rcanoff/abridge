# Review: `chore/ci-pipelines-readme` against `main` — 2026-06-27

## Findings

### 1. Workflow changes can merge without either GitHub workflow running `(requesting-code-review)`
**Evidence:** [`.github/workflows/ci-macos.yml`](.github/workflows/ci-macos.yml) and [`.github/workflows/ci-rust.yml`](.github/workflows/ci-rust.yml) both add restrictive `paths:` filters, but those filters do not include `.github/workflows/**`, `justfile`, `.swiftformat`, `.swiftlint.yml`, or `scripts/ci/**`.

- `ci-macos.yml` only triggers for `AppleBridge/**`, `AppleBridgeTests/**`, `project.yml`, and `rust/**`.
- `ci-rust.yml` only triggers for `rust/**`.

That means a PR changing the workflows themselves, the CI scripts, or the lint/Just config can show no status checks from these workflows at all. This branch is exactly that kind of change: it modifies both workflow files plus `justfile`, `.swiftformat`, `.swiftlint.yml`, and `scripts/ci/*`, yet the new filters would not cover several of those files. That is a production-readiness gap because CI policy changes are not self-validating.

**Fix:** Expand the workflow `paths:` filters to include CI-control files, or remove the filters and handle selective work inside the jobs.

### 2. The new pre-push verifier skips many files that change CI behavior `(requesting-code-review)`
**Evidence:** [`scripts/ci/paths.sh`](scripts/ci/paths.sh) marks changes only for:
- `rust/*` → Rust and Swift changed
- `AppleBridge/*|AppleBridgeTests/*|project.yml` → Swift changed

It does **not** classify changes to:
- `justfile`
- `.swiftformat`
- `.swiftlint.yml`
- `.githooks/*`
- `scripts/ci/*`
- `.github/workflows/*`

Then [`scripts/ci/pre-push-verify.sh`](scripts/ci/pre-push-verify.sh) exits early when both flags are `0`:
- `if [[ "$PATHS_RUST_CHANGED" -eq 0 && "$PATHS_SWIFT_CHANGED" -eq 0 ]]; then`
- `echo "pre-push verify: no CI paths changed — skipping"`

So edits to the lint config, CI scripts, or recipes that actually define verification behavior will bypass the hook entirely. That undermines the stated purpose of “path-aware CI verify” and makes the hook least effective precisely when its own behavior changes.

**Fix:** Treat CI/tooling files as verification inputs in `paths.sh`, at minimum covering `justfile`, `.swiftformat`, `.swiftlint.yml`, `scripts/ci/**`, and `.github/workflows/**`.

### 3. Removing `Sendable` from `ServerRunState` breaks strict-concurrency boundaries `(swift-concurrency-pro)`
**Evidence:** [`AppleBridge/Models/ServerRunState.swift`](AppleBridge/Models/ServerRunState.swift) changes:
- `enum ServerRunState: Equatable, Sendable {`
- to `enum ServerRunState: Equatable {`

But [`AppleBridge/Services/ServerServing.swift`](AppleBridge/Services/ServerServing.swift) still exposes it across async actor boundaries:
- `func refreshStatus() async -> ServerRunState`

And [`AppleBridge/Models/ServerStore.swift`](AppleBridge/Models/ServerStore.swift) awaits that actor-backed service result:
- `let state = await serverService.refreshStatus()`

Under the repo’s strict concurrency rules, values crossing actor boundaries must be `Sendable`. `ServerRunState` contains only sendable payloads (`String` in the error case), so dropping `Sendable` weakens correctness for no visible benefit and is likely to trigger strict-concurrency diagnostics.

**Fix:** Restore `Sendable` conformance on `ServerRunState` and keep other cross-actor model/error types sendable where they cross isolation domains.

## Summary

1. CI is no longer self-protecting: workflow, script, and lint-config changes can land without the new workflows running.
2. The pre-push hook has the same blind spot locally, so CI/tooling changes often skip verification entirely.
3. `ServerRunState` no longer satisfies the sendability expected by the app’s actor-based server API.

## Verification Note

Assessment is based only on the provided diff, inventory, existing code context, and inlined skills. I could evaluate trigger coverage, hook path classification, and visible Swift concurrency boundaries from the diff; I could not confirm runtime behavior, actual GitHub runner availability, or whether other unseen repo configuration compensates for these gaps.