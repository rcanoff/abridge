# Review: chore/mock-bearer-token-in-tests vs main

Date: 2026-06-28

## Findings

### 1. Non-Sendable Swift types now cross actor/protocol boundaries

**File:** `AppleBridge/Models/ServerRunState.swift`, `AppleBridge/Models/RemindersPermissionStatus.swift`, `AppleBridge/Services/ServerService.swift`, `AppleBridge/Services/KeychainService.swift`  
**Severity:** Critical  
**Tag:** `(swift-concurrency-pro)`

The diff removes `Sendable` from types that are returned or thrown across actor boundaries:

- `ServerRunState: Equatable, Sendable` → `ServerRunState: Equatable`
- `RemindersPermissionStatus: Equatable, CaseIterable, Sendable` → no `Sendable`
- `ServerOperationError: Error, Equatable, Sendable` → no `Sendable`
- `KeychainError: Error, Equatable, Sendable` → no `Sendable`

These are used by async actor/protocol APIs such as:

```swift
protocol ServerServing: Sendable {
    func refreshStatus() async -> ServerRunState
    ...
}
```

and `actor ServerService: ServerServing`.

Under strict Swift concurrency, values returned from actor-isolated async calls must be sendable. This is likely to produce strict-concurrency diagnostics or force unsafe inference around `ServerStore` and test mocks.

**Fix:** Restore `Sendable` conformances for value-only enums/structs that cross actor boundaries.

---

### 2. Real Keychain behavior lost coverage while production Keychain code changed

**File:** `AppleBridgeTests/KeychainServiceTests.swift`, `AppleBridgeTests/BearerTokenStoreTests.swift`, `AppleBridge/Services/KeychainService.swift`  
**Severity:** Important  
**Tag:** `(requesting-code-review)`

The diff deletes `KeychainServiceTests.swift`, which covered real `KeychainService` persistence:

```diff
-deleted file mode 100644 AppleBridgeTests/KeychainServiceTests.swift
```

At the same time, production `KeychainService` adds `rotateBearerToken()`:

```swift
func rotateBearerToken() throws {
    try deleteBearerToken()
    return try loadOrCreateBearerToken()
}
```

The replacement tests target only `MockBearerTokenStore`, so they verify mock behavior rather than the changed production Keychain implementation. The branch goal explains avoiding Keychain prompts, but from the diff there is no remaining production-level coverage for load/save/delete/rotate.

**Fix:** Keep at least one non-interactive production `KeychainService` test using an isolated service/account, or move it behind an opt-in/manual tag if CI Keychain access is intentionally avoided.

---

### 3. Generated UniFFI file is edited despite project rule

**File:** `AppleBridge/Services/apple_bridge_core.swift`  
**Severity:** Important  
**Tag:** `(requesting-code-review)`

`AGENTS.md` says:

```md
Never edit generated code — `AppleBridgeCore/`, `apple_bridge_core.swift`.
```

But this diff modifies `AppleBridge/Services/apple_bridge_core.swift` directly, adding `enabledCapabilities` and `FfiConverterSequenceString`.

Even if the generated output is correct, committing generated changes manually makes the source of truth unclear and risks drift from Rust UniFFI output.

**Fix:** Ensure this file was regenerated from the Rust UniFFI build, and document that regeneration path in the PR. If it was hand-edited, regenerate instead.

## Summary

1. Restoring `Sendable` on actor-crossing Swift value types is the highest risk because strict concurrency may reject the build.
2. The Keychain test swap removes production coverage exactly where token rotation was added.
3. The generated UniFFI Swift file is changed despite the repo rule forbidding manual edits.

## Verification Note

I reviewed only the provided diff, inventory, inlined skills, and context. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.