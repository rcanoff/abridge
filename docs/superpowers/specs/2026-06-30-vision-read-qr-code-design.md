# vision.read_qr_code MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Approved  
**Issue:** #116 (Epic #103; depends on #114 `vision.recognize_text`)  
**Branch:** `feat/vision-read-qr-code`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-30-vision-permissions-foundation-design.md`  
**Reference:** `docs/superpowers/specs/2026-06-30-vision-recognize-text-design.md`

---

## Summary

Implement `vision.read_qr_code` MCP tool: QR code detection via **`VNDetectBarcodesRequest`** / **`VNImageRequestHandler`**. Client supplies image bytes as **base64** (no camera or Photos TCC). Returns **exhaustive `VNBarcodeObservation` JSON projection** (mechanical snake_case serialization, shared `VisionSerialization` helpers from #114). Register in Rust tool catalog gated by **`vision.barcodes`**. Flip `vision-barcodes` capability to **`shipped: true`**. No Apple permission gate per #151 (payload-only V1).

**Pattern:** Mirrors `vision.recognize_text` (#114) — synchronous `VNImageRequestHandler.perform`, `VisionStore` protocol seam, dedicated provider operation file, Rust tool registration. Symbologies are **hardcoded to QR** (no client `symbologies` argument); sibling `vision.detect_barcodes` (#117) will expose multi-symbology detection later under the same capability.

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `vision.read_qr_code` |
| Capability | `vision.barcodes` |
| Provider | `vision` |
| Operation | `read_qr_code` |

### Vision API choice

Use **`VNImageRequestHandler`** with **`VNDetectBarcodesRequest`** (same handler class as `recognize_text`, not `ImageRequestHandler`):

| MCP argument | Apple API |
|--------------|-----------|
| `image_data` | Decode base64 → `Data` → `CGImage` for `VNImageRequestHandler(cgImage:orientation:options:)` |
| `orientation` (optional) | `CGImagePropertyOrientation` on handler init (EXIF 1–8) |
| `revision` (optional) | `request.revision` |
| `region_of_interest` (optional) | `request.regionOfInterest` (`CGRect`, normalized) |
| `coalesce_composite_symbologies` (optional) | `request.coalesceCompositeSymbologies` |

**Fixed at implementation (not MCP arguments):**

| Behavior | Apple API |
|----------|-----------|
| QR-only detection | `request.symbologies = [.qr]` always |

`VNImageRequestHandler.perform([request])` runs **synchronously** on the calling thread — no RunLoop pump required (same as `recognize_text`).

Do **not** read from camera, Photos, or filesystem paths; image input is **in-memory client payload only**.

Do **not** use `DetectBarcodesRequest` / `BarcodeObservation` (macOS 26 Swift Vision API) in this subtask — that type is owned by `vision.scan_document` (#115) nested barcodes and future `vision.detect_barcodes` (#117). This tool projects legacy **`VNBarcodeObservation`** to match the `VNRecognizedTextObservation` fidelity path from #114.

### Input schema (Rust `input_schema`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `image_data` | string (`minLength: 1`) | **yes** | Base64-encoded image bytes (PNG, JPEG, HEIC, etc.) |
| `orientation` | integer | no | EXIF orientation `1`–`8`; omit for image metadata default |
| `revision` | integer | no | `VNDetectBarcodesRequest` revision; omit for `defaultRevision` |
| `region_of_interest` | object | no | Normalized crop region |
| `region_of_interest.origin.x` | number | if `region_of_interest` | |
| `region_of_interest.origin.y` | number | if `region_of_interest` | |
| `region_of_interest.size.width` | number | if `region_of_interest` | |
| `region_of_interest.size.height` | number | if `region_of_interest` | |
| `coalesce_composite_symbologies` | boolean | no | Apple default when omitted |

Empty/missing `image_data`, whitespace-only, or invalid base64 → Swift `invalid_arguments`.  
Invalid enum / out-of-range `orientation` → `invalid_arguments`.

### Output

JSON **object** mirroring `VNDetectBarcodesRequest.results` (not a bare array):

```json
{
  "results": [
    {
      "uuid": "…",
      "confidence": 1.0,
      "time_range": {
        "start_seconds": 0.0,
        "duration_seconds": 0.0
      },
      "request_revision": 3,
      "bounding_box": {
        "origin": { "x": 0.0, "y": 0.0 },
        "size": { "width": 0.0, "height": 0.0 }
      },
      "global_segmentation_mask": null,
      "top_left": { "x": 0.0, "y": 0.0 },
      "top_right": { "x": 0.0, "y": 0.0 },
      "bottom_left": { "x": 0.0, "y": 0.0 },
      "bottom_right": { "x": 0.0, "y": 0.0 },
      "symbology": "VNBarcodeSymbologyQR",
      "payload_string_value": "…",
      "payload_data": "…"
    }
  ]
}
```

`results` is an empty array when Vision finds no QR codes (success, not error).

---

## Framework fidelity

Extend **`VisionSerialization`** from #114; reuse geometry / time-range / pixel-buffer helpers from `recognize_text`.

Every `results[]` element is a **complete `VNBarcodeObservation` projection** — all keys present, `null` for absent optionals, snake_case encoding. Never omit keys.

### `VNBarcodeObservation` keys (macOS 26 SDK)

Inheritance: `VNBarcodeObservation` → `VNRectangleObservation` → `VNDetectedObjectObservation` → `VNObservation`.

| Key | Source | Encoding |
|-----|--------|----------|
| `uuid` | `VNObservation.uuid` | UUID string |
| `confidence` | `VNObservation.confidence` | number (`VNConfidence`, 0–1) |
| `time_range` | `VNObservation.timeRange` | `CMTimeRange` object or zeroed object for still images |
| `request_revision` | `VNRequestRevisionProviding.requestRevision` | integer |
| `bounding_box` | `VNDetectedObjectObservation.boundingBox` | normalized `CGRect` object |
| `global_segmentation_mask` | `VNDetectedObjectObservation.globalSegmentationMask` | `VNPixelBufferObservation` object or `null` |
| `top_left` | `VNRectangleObservation.topLeft` | `CGPoint` object |
| `top_right` | `VNRectangleObservation.topRight` | `CGPoint` object |
| `bottom_left` | `VNRectangleObservation.bottomLeft` | `CGPoint` object |
| `bottom_right` | `VNRectangleObservation.bottomRight` | `CGPoint` object |
| `symbology` | `VNBarcodeObservation.symbology` | string (`VNBarcodeSymbology.rawValue`, e.g. `"VNBarcodeSymbologyQR"` for QR; not the short Codable key used by Swift Vision `BarcodeObservation`, e.g. `"qr"`) |
| `payload_string_value` | `VNBarcodeObservation.payloadStringValue` | string or `null` |
| `payload_data` | `VNBarcodeObservation.payloadData` | base64 string or `null` |

`vision.detect_barcodes` and `vision.scan_document` use the macOS 26 Swift Vision `BarcodeObservation` type with different key names per their specs — intentional; symbology strings are not normalized across tools.

`VNPixelBufferObservation` nested encoding reuses the helper from `recognize_text` (`uuid`, `confidence`, `time_range`, `request_revision`, `pixel_buffer` with `width`, `height`, `pixel_format`, `bytes_per_row`, `data`).

### Nested `CMTimeRange` (`time_range`)

| Key | Source | Encoding |
|-----|--------|----------|
| `start_seconds` | `CMTimeRange.start` | number (`CMTimeGetSeconds`) |
| `duration_seconds` | `CMTimeRange.duration` | number (`CMTimeGetSeconds`) |

### Nested `CGRect` (`bounding_box`, `region_of_interest` input)

| Key | Encoding |
|-----|----------|
| `origin.x` | number |
| `origin.y` | number |
| `size.width` | number |
| `size.height` | number |

### Nested `CGPoint` (corner keys)

| Key | Encoding |
|-----|----------|
| `x` | number |
| `y` | number |

---

## Architecture

```
Rust tools/call → ProviderBridge → VisionProvider.read_qr_code
                                        ↓
                              VisionStore (protocol)
                                        ↓
                         LiveVisionStore / MockVisionStore
                                        ↓
                    VNImageRequestHandler.perform([VNDetectBarcodesRequest])
```

### Swift files (new)

| File | Role |
|------|------|
| `ABridge/Providers/Vision/VisionProviderReadQrCode.swift` | Operation handler |
| `ABridgeTests/VisionProviderReadQrCodeTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `ABridge/Providers/Vision/VisionSerialization.swift` | `readQrCodeResponseJSONObject`, `barcodeObservationJSONObject` |
| `ABridge/Providers/Vision/VisionStore.swift` | `VisionReadQrCodeRequest` + `readQrCode` on protocol |
| `ABridge/Providers/Vision/LiveVisionStore.swift` | `VNDetectBarcodesRequest` sync wrapper |
| `ABridge/Providers/Vision/VisionProviderRouting.swift` | `read_qr_code` dispatch |
| `ABridgeTests/MockVisionStore.swift` | Fake QR barcode results for CI |
| `ABridgeTests/VisionSerializationTests.swift` | `VNBarcodeObservation` projection completeness |
| `ABridgeTests/AppleProviderBridgeVisionTests.swift` | Success path with mock provider |
| `ABridgeTests/AppSettingsVisionTests.swift` | Shipped capability server gating |
| `ABridge/Models/CapabilityCatalog.swift` | `vision-barcodes` → `shipped: true` |
| `README.md` | Check off `vision.read_qr_code` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/abridge_core/src/capabilities.rs` | `VISION_BARCODES` constant + `is_allowed_in_v1` |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_READ_QR_CODE`, registration, input schema, unit tests |
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
| `VNImageRequestHandler.perform` failure | `vision_error` |
| Serialization failure | `vision_error` |

Rust: tool absent from `tools/list` when `vision.barcodes` not enabled; `tools/call` with disabled capability returns typed MCP error without provider dispatch (existing pattern).

**Capability shipping note:** Shipping `vision-barcodes` with only `vision.read_qr_code` registered is intentional (same pattern as #114 shipping `vision.text` before other text tools). `vision.detect_barcodes` (#117) adds a second tool under the same capability later without re-flipping the toggle.

---

## Relationship to sibling tools

| Tool | Issue | API | Symbologies |
|------|-------|-----|-------------|
| `vision.read_qr_code` | #116 | `VNDetectBarcodesRequest` | QR only (fixed) |
| `vision.detect_barcodes` | #117 | TBD (`DetectBarcodesRequest` or `VNDetectBarcodesRequest`) | Client-configurable |
| `vision.scan_document` | #115 | `RecognizeDocumentsRequest` + optional `BarcodeDetectionOptions` | Nested `BarcodeObservation` (Swift Vision API) |

`read_qr_code` does **not** reuse `VisionDocumentObservationSerialization.barcodeObservationJSONObject` — that projects Swift `BarcodeObservation`, not `VNBarcodeObservation`.

---

## Acceptance criteria (#116)

1. `vision.read_qr_code` in `tools/list` when `vision.barcodes` enabled.
2. Valid `tools/call` succeeds against mock/live Vision per tests.
3. Disabled capability → typed MCP error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `vision-barcodes` capability `shipped: true`.
6. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): enable Vision Barcodes in Settings, call tool with a small PNG/JPEG image containing a QR code as base64.