# vision_detect_barcodes MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Approved  
**Issue:** #117 (Epic #103; depends on #151 Vision permissions foundation)  
**Branch:** `feat/vision-detect-barcodes`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-30-vision-permissions-foundation-design.md`  
**Sibling:** `docs/superpowers/specs/2026-06-30-vision-recognize-text-design.md`, `docs/superpowers/specs/2026-06-30-vision-recognize-documents-design.md`

---

## Summary

Implement `vision_detect_barcodes` MCP tool: barcode and QR detection via **`DetectBarcodesRequest`** / **`ImageRequestHandler`** (macOS 26 Swift Vision API). Client supplies image bytes as **base64** (no camera or Photos TCC). Returns **exhaustive `BarcodeObservation` JSON projection** (mechanical snake_case serialization, reuse `VisionDocumentObservationSerialization` from #115). Register in Rust tool catalog gated by **`vision.barcodes`**. Flip `vision-barcodes` capability to **`shipped: true`**. No Apple permission gate per #151 (payload-only V1). Depends on #114 for Vision provider scaffolding and #115 for barcode observation serialization helpers.

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `vision_detect_barcodes` |
| Capability | `vision.barcodes` |
| Provider | `vision` |
| Operation | `detect_barcodes` |

### Vision API choice

Use **`ImageRequestHandler`** with **`DetectBarcodesRequest`** (macOS 26+ Swift Vision API):

| MCP argument | Apple API |
|--------------|-----------|
| `image_data` | Decode base64 → `Data` → `ImageRequestHandler(_:orientation:)` |
| `orientation` (optional) | `CGImagePropertyOrientation` on handler init (EXIF 1–8) |
| `revision` (optional) | `DetectBarcodesRequest.Revision` (`revision1`); omit for default |
| `region_of_interest` (optional) | `request.regionOfInterest` (`NormalizedRect`) |
| `symbologies` (optional) | `request.symbologies` (`[BarcodeSymbology]`) |
| `coalesce_composite_symbologies` (optional) | `request.coalesceCompositeSymbologies` |

`ImageRequestHandler.perform(_:)` is **async**. Bridge to the synchronous `ProviderBridge` path using the existing **`VisionAsyncBridge.waitForCompletion`** pattern from #115 (`DispatchQueue.main.async` + `Task` + run-loop pump).

Do **not** use the legacy **`VNDetectBarcodesRequest`** + **`VNImageRequestHandler`** pipeline as the primary path — that yields `VNBarcodeObservation`, not the Swift `BarcodeObservation` type already projected by #115.

Do **not** read from camera, Photos, or filesystem paths; image input is **in-memory client payload only**.

### Input schema (Rust `input_schema`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `image_data` | string (`minLength: 1`) | **yes** | Base64-encoded image bytes (PNG, JPEG, HEIC, etc.) |
| `orientation` | integer | no | EXIF orientation `1`–`8`; omit for image metadata default |
| `revision` | string enum | no | `revision1`; omit for SDK default |
| `region_of_interest` | object | no | Normalized crop region |
| `region_of_interest.origin.x` | number | if `region_of_interest` | |
| `region_of_interest.origin.y` | number | if `region_of_interest` | |
| `region_of_interest.size.width` | number | if `region_of_interest` | |
| `region_of_interest.size.height` | number | if `region_of_interest` | |
| `symbologies` | string array | no | `BarcodeSymbology` raw values (e.g. `qr`, `code128`); omit for all supported symbologies |
| `coalesce_composite_symbologies` | boolean | no | Apple default when omitted |

Empty/missing `image_data`, whitespace-only, or invalid base64 → Swift `invalid_arguments`.  
Invalid enum / out-of-range `orientation` or unknown symbology strings → `invalid_arguments`.

### Output

JSON **object** mirroring `DetectBarcodesRequest` results (not a bare array):

```json
{
  "results": [
    {
      "uuid": "…",
      "confidence": 1.0,
      "time_range": { "start_seconds": 0.0, "duration_seconds": 0.0 },
      "originating_request_descriptor": null,
      "payload_string": "…",
      "payload_data": null,
      "supplemental_payload_string": null,
      "supplemental_payload_data": null,
      "supplemental_composite_type": null,
      "is_gs1_data_carrier": false,
      "symbology": "qr",
      "is_color_inverted": false,
      "top_left": { "x": 0.0, "y": 0.0 },
      "top_right": { "x": 0.0, "y": 0.0 },
      "bottom_right": { "x": 0.0, "y": 0.0 },
      "bottom_left": { "x": 0.0, "y": 0.0 },
      "bounding_region": { }
    }
  ]
}
```

`results` is an empty array when Vision finds no barcodes (success, not error).

---

## Framework fidelity

Reuse **`VisionDocumentObservationSerialization.barcodeObservationJSONObject(from:boundingRegion:)`** from #115; add a thin **`VisionBarcodeSerialization`** (or extend `VisionDocumentSerialization`) for the top-level `detect_barcodes` response wrapper. Reuse geometry / time-range helpers from `VisionSerialization`.

Every `results[]` element is a **complete `BarcodeObservation` projection** — all keys present, `null` for absent optionals, snake_case encoding. Never omit keys.

### `BarcodeObservation` keys (macOS 26 SDK)

Same projection as #115 `recognize_documents` nested barcodes (see `docs/superpowers/specs/2026-06-30-vision-recognize-documents-design.md` § `BarcodeObservation`):

| Key | Source | Encoding |
|-----|--------|----------|
| `uuid` | `uuid` | UUID string |
| `confidence` | `confidence` | number |
| `time_range` | `timeRange` | `CMTimeRange` object or zeroed |
| `originating_request_descriptor` | `originatingRequestDescriptor` | object or `null` |
| `payload_string` | `payloadString` | string or `null` |
| `payload_data` | `payloadData` | base64 or `null` |
| `supplemental_payload_string` | `supplementalPayloadString` | string or `null` |
| `supplemental_payload_data` | `supplementalPayloadData` | base64 or `null` |
| `supplemental_composite_type` | `supplementalCompositeType` | enum string or `null` |
| `is_gs1_data_carrier` | `isGS1DataCarrier` | boolean |
| `symbology` | `symbology` | string (raw symbology identifier) |
| `is_color_inverted` | `isColorInverted` | boolean |
| `top_left` | `topLeft` | `NormalizedPoint` object |
| `top_right` | `topRight` | `NormalizedPoint` object |
| `bottom_right` | `bottomRight` | `NormalizedPoint` object |
| `bottom_left` | `bottomLeft` | `NormalizedPoint` object |
| `bounding_region` | `boundingRegion` | `NormalizedRegion` object |

`CompositeType` values: `gs1_type_a`, `gs1_type_b`, `gs1_type_c`, `linked`.

`bounding_region` is serialized from `observation.boundingRegion` via `normalizedRegionJSONObject(from:)` — same helper as #115.

### Shared geometry helpers

Reuse from #115:

#### `NormalizedPoint`

| Key | Encoding |
|-----|----------|
| `x` | number |
| `y` | number |

#### `NormalizedRect` (input `region_of_interest`)

| Key | Encoding |
|-----|----------|
| `origin.x` | number |
| `origin.y` | number |
| `size.width` | number |
| `size.height` | number |

#### `NormalizedRegion` (`bounding_region`)

| Key | Source | Encoding |
|-----|--------|----------|
| `aspect_ratio` | `aspectRatio` | number |
| `index_path` | `indexPath` | array of integers |
| `point_count` | `pointCount` | integer |
| `normalized_points` | `normalizedPoints` | array of `{ "x": number, "y": number }` |
| `child_contours` | `childContours` | recursive array of `NormalizedRegion` objects |

#### `RequestDescriptor`

| Key | Encoding |
|-----|----------|
| `identifier` | string (mechanical `String(describing:)` or stable descriptor id from SDK) |

---

## Architecture

```
Rust tools/call → ProviderBridge → VisionProvider.detect_barcodes
                                        ↓
                              VisionStore (protocol)
                                        ↓
                         LiveVisionStore / MockVisionStore
                                        ↓
              ImageRequestHandler.perform(DetectBarcodesRequest)
```

### Swift files (new)

| File | Role |
|------|------|
| `ABridge/Providers/Vision/VisionBarcodeSerialization.swift` | Top-level `detect_barcodes` response wrapper |
| `ABridge/Providers/Vision/VisionProviderDetectBarcodes.swift` | Operation handler |
| `ABridgeTests/VisionBarcodeSerializationTests.swift` | `BarcodeObservation` projection completeness |
| `ABridgeTests/VisionProviderDetectBarcodesTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `ABridge/Providers/Vision/VisionStore.swift` | `VisionDetectBarcodesRequest` + `detectBarcodes` protocol method |
| `ABridge/Providers/Vision/LiveVisionStore.swift` | `DetectBarcodesRequest` via `ImageRequestHandler` |
| `ABridge/Providers/Vision/VisionProviderRouting.swift` | `detect_barcodes` dispatch |
| `ABridge/Models/CapabilityCatalog.swift` | `vision-barcodes` → `shipped: true` |
| `ABridgeTests/MockVisionStore.swift` | Canned `BarcodeObservation` results |
| `ABridgeTests/AppleProviderBridgeVisionTests.swift` | Success path with mock provider |
| `ABridgeTests/AppSettingsVisionTests.swift` | Shipped capability server gating |
| `README.md` | Check off `vision_detect_barcodes` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/abridge_core/src/capabilities.rs` | `VISION_BARCODES` constant + `is_allowed_in_v1` |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_DETECT_BARCODES`, registration, input schema, unit tests |
| `rust/abridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `vision.barcodes` is in server enabled capabilities |
| Apple TCC | **None** — client-provided image bytes only (#151) |
| Settings | `vision-barcodes` shipped → no `requiresAppleVisionAccess`; `serverEnabledMCPCapabilityIDs` includes `vision.barcodes` when toggled on |

| Condition | Error code |
|-----------|------------|
| Invalid JSON / missing `image_data` / bad base64 | `invalid_arguments` |
| Undecodable image bytes | `invalid_arguments` |
| Invalid symbology / region / revision | `invalid_arguments` |
| `ImageRequestHandler.perform` failure | `vision_error` |
| Serialization failure | `vision_error` |

Rust: tool absent from `tools/list` when `vision.barcodes` not enabled; `tools/call` with disabled capability returns typed MCP error without provider dispatch (existing pattern).

---

## QR codes

`vision_detect_barcodes` covers every symbology, QR included: pass `symbologies: ["qr"]` to scope detection to QR codes. There is no separate QR tool.

---

## Acceptance criteria (#117)

1. `vision_detect_barcodes` in `tools/list` when `vision.barcodes` enabled.
2. Valid `tools/call` succeeds against mock/live Vision per tests.
3. Disabled capability → typed MCP error (not silent success).
4. Responses use exhaustive `BarcodeObservation` projection (snake_case keys).
5. `vision-barcodes` capability `shipped: true`.
6. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): enable Vision Barcodes in Settings, call tool with a small PNG/JPEG image containing a QR or Code128 barcode as base64.