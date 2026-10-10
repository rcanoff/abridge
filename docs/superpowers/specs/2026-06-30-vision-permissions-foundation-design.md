# Vision MCP Capability Foundation — Design Spec

**Date:** 2026-06-30  
**Status:** Approved  
**Issue:** #151 (Epic #103, first in Vision merge order)  
**Branch:** `feat/vision-permissions-foundation`  
**PRD:** `docs/prd.md` § Future Providers, § User Interface — Permissions  
**Architecture:** `docs/architecture-bootstrap-guide.md`  
**Reference:** `docs/superpowers/specs/2026-06-29-mapkit-permissions-foundation-design.md`, `docs/superpowers/specs/2026-06-29-contacts-permissions-foundation-design.md`

---

## Summary

Establish **Vision MCP capability scaffolding** before any `vision.*` MCP tool ships. Unlike Contacts, EventKit, or MapKit, Vision V1 operates on **client-provided image data** (base64 in tool arguments) — there is **no macOS TCC permission row** for this foundation.

No MCP tools or Rust tool registration in this subtask — only capability catalog entries (unshipped), Settings UI, server gating wiring, and a `VisionProvider` routing stub in `AppleProviderBridge`.

Camera capture, photo-library access, and live capture pipelines are **out of scope** for V1 and must not add Info.plist usage strings unless a future subtask proves they are required.

---

## Goals

1. MCP Permissions shows **Vision** capability group with four toggles; selections persist in `AppSettings.savedCapabilityIDs`.
2. Shipped Vision capabilities reach the MCP server when toggled on — **no Apple permission gate** (V1 is payload-only).
3. Unshipped Vision toggles persist locally but do **not** register on the server.
4. `VisionProvider` skeleton routes through `AppleProviderBridge` with `unknown_operation` until tool subtasks land.
5. Apple Permissions section includes a **footer note** explaining why Vision has no macOS permission row.
6. `just test-swift` passes including capability gating unit tests.

## Non-goals

- Individual `vision.*` MCP tools (sibling sub-issues)
- Rust tool registration or capability constants in `rust/abridge_core`
- `VisionPermissionService` or any TCC status/request plumbing
- `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, or other image-capture plist keys
- Menu bar popover Vision status
- Vision request JSON schemas or `VN*` result projection (deferred to tool subtasks)
- Live camera / Photos.app / file-picker image acquisition in the app UI

---

## Permission model (Vision V1 — MCP-only)

Vision V1 uses a **single-layer model**: MCP capability toggles only. There is no Layer 1 Apple TCC gate for the foundation subtask.

### TCC decision (documented)

| Question | V1 answer |
|----------|-----------|
| Does the app read the camera? | **No** — MCP clients supply image bytes in tool arguments. |
| Does the app access Photos / files on disk? | **No** — not in foundation or planned V1 tools. |
| Does `Vision` framework processing of in-memory `CGImage`/`Data` require TCC? | **No** — TCC applies to capture and library access, not in-process analysis of client-provided buffers. |
| Info.plist changes in this subtask? | **None** — do not add usage strings speculatively. |

**Revisit trigger:** A future subtask that adds camera capture, photo-library pickers, or sandbox file reads must add the appropriate usage strings and Apple permission rows in a **separate** permissions subtask — not retrofitted silently into tool PRs.

### Layer — MCP capabilities (app)

| Toggle ID | Capability ID | Label | Shipped | Future MCP tools (README) |
|-----------|---------------|-------|---------|---------------------------|
| `vision-text` | `vision.text` | Text | `false` | `vision_recognize_text` |
| `vision-document` | `vision.document` | Document | `false` | `vision_recognize_documents` |
| `vision-barcodes` | `vision.barcodes` | Barcodes | `false` | `vision_detect_barcodes` |
| `vision-faces` | `vision.faces` | Faces | `false` | `vision_detect_face_landmarks` |

`shipped: false` until sibling MCP tool subtasks land. Toggles persist in `AppSettings.savedCapabilityIDs` but do not reach the server until **shipped** and checked.

Capability IDs follow `docs/conventions.md` provider naming (`vision.text`, `vision.document`, etc.) — provider prefix `vision`, dot-separated capability segment.

---

## Framework fidelity rules (deferred to tool subtasks)

Per `AGENTS.md` § Framework fidelity, Vision tool subtasks must serialize Apple `Vision` framework results with **mechanical serialization only**:

- `VNRecognizedTextObservation`, `VNBarcodeObservation`, `VNFaceObservation`, document-structure observations → nested JSON mirroring Apple property names (snake_case keys)
- Image input: client-supplied base64 → decode to `Data`/`CGImage` for `VNImageRequestHandler` — no invented DTO read models
- `nil` optionals → JSON `null`; no field subsetting or derived fields

This foundation subtask does **not** define tool payloads. Any spec proposing partial/minimal Vision JSON is invalid per AGENTS.md.

---

## Components

### New Swift files

| File | Responsibility |
|------|----------------|
| `ABridge/Providers/Vision/VisionProvider.swift` | Thin stub: returns `unknown_operation` for all ops |
| `ABridgeTests/AppSettingsVisionTests.swift` | Vision capability server gating tests |
| `ABridgeTests/PermissionsStoreVisionTests.swift` | Vision toggle gating seam tests |
| `ABridgeTests/AppleProviderBridgeVisionTests.swift` | Bridge routes `vision` provider |

### Modified Swift files

| File | Change |
|------|--------|
| `ABridge/Models/CapabilityCatalog.swift` | Add `visionCapabilities` |
| `ABridge/Models/AppSettings.swift` | `enabledVisionCapabilityIDs`; extend `serverEnabledMCPCapabilityIDs` |
| `ABridge/Models/PermissionsStore.swift` | Vision branch in `shouldApplySavedCapabilitiesAfterToggle` (no Apple gate) |
| `ABridge/Views/Settings/PermissionsSettingsComponents.swift` | `VisionMCPPermissionsGroup` |
| `ABridge/Views/Settings/PermissionsSettingsView.swift` | Vision MCP group; Apple Permissions footer note |
| `ABridge/Providers/AppleProviderBridge.swift` | Route `provider == "vision"` to `VisionProvider` |

### Explicitly unchanged

| File | Reason |
|------|--------|
| `project.yml` | No TCC usage strings for payload-only V1 |
| `ABridge/Models/AppStore.swift` | No Apple permission status for Vision |
| `ABridge/Models/SettingsStore.swift` | No new authorization parameter — existing `applySavedCapabilities` signature unchanged |
| `ABridge/Models/ApplePermissionAuthorization.swift` | No Vision authorization field |

---

## Server capability gating

`AppSettings.serverEnabledMCPCapabilityIDs(...)`:

- Always includes `diagnostics.read`
- Reminder / calendar / event / contacts / mapkit capabilities gated on their existing Apple authorization flags (unchanged)
- **Vision capabilities:** append `enabledVisionCapabilityIDs` **unconditionally** (no authorization parameter) when shipped and toggled

While all vision capabilities remain `shipped: false`, `enabledVisionCapabilityIDs` is always empty and the server receives no vision capability IDs — matching the contacts-unshipped pattern.

`PermissionsStore.shouldApplySavedCapabilitiesAfterToggle`:

- Vision capabilities: return `true` when enabling (no Apple permission prerequisite)
- Do **not** add `requiresAppleVisionAccess` — there is no Apple permission row

---

## VisionProvider stub

```swift
// provider: "vision"
// All operations return ProviderResponse(ok: false, errorJson: unknown_operation)
```

No business logic. Future subtasks add operations one at a time. Input images arrive as base64 in `payloadJson` per tool specs; the provider decodes in-memory only.

---

## Settings UI

### MCP Permissions — Vision group

Add `VisionMCPPermissionsGroup` in `PermissionsSettingsComponents.swift`, mirroring `MapKitMCPPermissionsGroup`:

```swift
struct VisionMCPPermissionsGroup: View { ... }
```

Wire into `PermissionsSettingsView` after `MapKitMCPPermissionsGroup`.

### Apple Permissions — footer note

Vision has **no** Apple permission row. Extend the existing Apple Permissions section footer (or add a second footer sentence) to explain:

> Vision tools analyze image data supplied by MCP clients. No macOS privacy permission is required for this foundation.

This prevents users from searching for a missing Vision row in System Settings.

---

## Acceptance criteria (from #151)

1. MCP Permissions shows Vision group with Text, Document, Barcodes, and Faces toggles; selections persist.
2. Unshipped Vision toggles do not register capabilities on the MCP server.
3. Apple Permissions footer documents that Vision has no macOS permission row (payload-only V1).
4. `AppleProviderBridge` routes `provider == "vision"` to `VisionProvider` stub returning `unknown_operation`.
5. `just test-swift` passes with Vision capability gating tests.

## Verification

```sh
TZ=UTC just test-swift
```

No `xcodegen generate` required unless `project.yml` changes (not expected for this subtask).

Manual (not CI-gating): toggle Vision capabilities in Settings and confirm persistence across relaunch.