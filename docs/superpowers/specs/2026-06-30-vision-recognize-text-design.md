# vision.recognize_text MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Approved  
**Issue:** #114 (Epic #103; depends on #151 Vision permissions foundation)  
**Branch:** `feat/vision-recognize-text`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-30-vision-permissions-foundation-design.md`

---

## Summary

Implement `vision.recognize_text` MCP tool: optical character recognition via **`VNRecognizeTextRequest`** / **`VNImageRequestHandler`**. Client supplies image bytes as **base64** (no camera or Photos TCC). Returns **exhaustive `VNRecognizedTextObservation` JSON projection** (mechanical snake_case serialization, shared `VisionSerialization` for future Vision tools). Register in Rust tool catalog gated by **`vision.text`**. Flip `vision-text` capability to **`shipped: true`**. No Apple permission gate per #151 (payload-only V1).

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `vision.recognize_text` |
| Capability | `vision.text` |
| Provider | `vision` |
| Operation | `recognize_text` |

### Vision API choice

Use **`VNImageRequestHandler`** with **`VNRecognizeTextRequest`**:

| MCP argument | Apple API |
|--------------|-----------|
| `image_data` | Decode base64 → `Data` → `CGImage` for `VNImageRequestHandler(cgImage:orientation:options:)` |
| `orientation` (optional) | `CGImagePropertyOrientation` on handler init (EXIF 1–8) |
| `recognition_languages` (optional) | `request.recognitionLanguages` |
| `custom_words` (optional) | `request.customWords` |
| `recognition_level` (optional) | `request.recognitionLevel` (`VNRequestTextRecognitionLevel`) |
| `uses_language_correction` (optional) | `request.usesLanguageCorrection` |
| `automatically_detects_language` (optional) | `request.automaticallyDetectsLanguage` |
| `minimum_text_height` (optional) | `request.minimumTextHeight` |
| `revision` (optional) | `request.revision` |
| `prefer_background_processing` (optional) | `request.preferBackgroundProcessing` |
| `region_of_interest` (optional) | `request.regionOfInterest` (`CGRect`, normalized) |
| `max_candidate_count` (optional) | Argument to `observation.topCandidates(_:)` when building each result element |

`VNImageRequestHandler.perform([request])` runs **synchronously** on the calling thread — no RunLoop pump required (unlike MapKit `MKLocalSearch`).

Do **not** read from camera, Photos, or filesystem paths; image input is **in-memory client payload only**.

### Input schema (Rust `input_schema`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `image_data` | string (`minLength: 1`) | **yes** | Base64-encoded image bytes (PNG, JPEG, HEIC, etc.) |
| `orientation` | integer | no | EXIF orientation `1`–`8`; omit for image metadata default |
| `recognition_languages` | string array | no | ISO language codes; order defines processing priority |
| `custom_words` | string array | no | Lexicon additions for word recognition |
| `recognition_level` | string enum | no | `accurate` (default), `fast` |
| `uses_language_correction` | boolean | no | Apple default when omitted |
| `automatically_detects_language` | boolean | no | Effective on revision ≥ 3; Apple default when omitted |
| `minimum_text_height` | number (`minimum: 0`) | no | Relative to image height; `0.0` = highest resolution |
| `revision` | integer | no | `VNRecognizeTextRequest` revision; omit for `defaultRevision` |
| `prefer_background_processing` | boolean | no | Reduces resource contention at cost of latency |
| `region_of_interest` | object | no | Normalized crop region |
| `region_of_interest.origin.x` | number | if `region_of_interest` | |
| `region_of_interest.origin.y` | number | if `region_of_interest` | |
| `region_of_interest.size.width` | number | if `region_of_interest` | |
| `region_of_interest.size.height` | number | if `region_of_interest` | |
| `max_candidate_count` | integer (`minimum: 1`, `maximum: 10`) | no | Default `1`; caps `topCandidates` per observation |

Empty/missing `image_data`, whitespace-only, or invalid base64 → Swift `invalid_arguments`.  
Invalid enum / out-of-range `orientation` or `max_candidate_count` → `invalid_arguments`.

### Output

JSON **object** mirroring `VNRecognizeTextRequest.results` (not a bare array):

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
      "candidates": [
        {
          "string": "…",
          "confidence": 0.0,
          "request_revision": 3
        }
      ]
    }
  ]
}
```

`results` is an empty array when Vision finds no text (success, not error).

---

## Framework fidelity

Define **`VisionSerialization`** once; reuse for `scan_document`, barcode, and face tools.

Every `results[]` element is a **complete `VNRecognizedTextObservation` projection** — all keys present, `null` for absent optionals, snake_case encoding. Never omit keys.

### `VNRecognizedTextObservation` keys (macOS 26 SDK)

Inheritance: `VNRecognizedTextObservation` → `VNRectangleObservation` → `VNDetectedObjectObservation` → `VNObservation`.

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
| `candidates` | `topCandidates(max_candidate_count)` | array of `VNRecognizedText` objects (see below) |

`VNRecognizedTextObservation` exposes recognized text only via **`topCandidates(_:)`** (no stored string property). `candidates` is the mechanical serialization of that API call using tool input `max_candidate_count` (default `1`, max `10` per Apple). This is not an invented field — it is the sole framework surface for text on this observation type.

`VNRecognizedText.boundingBox(for:)` is a **range-parameterized method** — not serialized in V1 read responses (no stable property to project).

### Nested `VNRecognizedText` (`candidates[]`)

| Key | Source | Encoding |
|-----|--------|----------|
| `string` | `VNRecognizedText.string` | string |
| `confidence` | `VNRecognizedText.confidence` | number |
| `request_revision` | `VNRequestRevisionProviding.requestRevision` | integer |

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

### Nested `VNPixelBufferObservation` (`global_segmentation_mask`)

Included when non-`nil` (typically `null` for text observations). Project all serializable properties:

| Key | Source | Encoding |
|-----|--------|----------|
| `uuid` | `VNObservation.uuid` | UUID string |
| `confidence` | `VNObservation.confidence` | number |
| `time_range` | `VNObservation.timeRange` | `CMTimeRange` object |
| `request_revision` | `VNRequestRevisionProviding.requestRevision` | integer |
| `pixel_buffer` | `VNPixelBufferObservation.pixelBuffer` | object (see below) or `null` on lock failure |
| `feature_name` | `VNPixelBufferObservation.featureName` | string or `null` |

#### `pixel_buffer` object

| Key | Encoding |
|-----|----------|
| `width` | integer |
| `height` | integer |
| `pixel_format` | FourCC string (e.g. `"420f"`) |
| `bytes_per_row` | integer |
| `data` | base64 of plane 0 bytes |

---

## Architecture

```
Rust tools/call → ProviderBridge → VisionProvider.recognize_text
                                        ↓
                              VisionStore (protocol)
                                        ↓
                         LiveVisionStore / MockVisionStore
                                        ↓
                    VNImageRequestHandler.perform([VNRecognizeTextRequest])
```

### Swift files (new)

| File | Role |
|------|------|
| `AppleBridge/Providers/Vision/VisionSerialization.swift` | Exhaustive Vision type → JSON |
| `AppleBridge/Providers/Vision/VisionStore.swift` | Protocol + request/result types |
| `AppleBridge/Providers/Vision/LiveVisionStore.swift` | `VNImageRequestHandler` wrapper |
| `AppleBridge/Providers/Vision/VisionProviderRecognizeText.swift` | Operation handler |
| `AppleBridge/Providers/Vision/VisionProviderRouting.swift` | `handle(operation:)` dispatch |
| `AppleBridgeTests/MockVisionStore.swift` | Fake OCR results for CI |
| `AppleBridgeTests/VisionSerializationTests.swift` | Projection completeness |
| `AppleBridgeTests/VisionProviderRecognizeTextTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `AppleBridge/Providers/Vision/VisionProvider.swift` | Store injection + error helpers |
| `AppleBridge/Models/CapabilityCatalog.swift` | `vision-text` → `shipped: true` |
| `AppleBridgeTests/AppleProviderBridgeVisionTests.swift` | Success path with mock provider |
| `AppleBridgeTests/AppSettingsVisionTests.swift` | Shipped capability server gating |
| `README.md` | Check off `vision.recognize_text` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/apple_bridge_core/src/capabilities.rs` | `VISION_TEXT` constant + `is_allowed_in_v1` |
| `rust/apple_bridge_core/src/tools/mod.rs` | `TOOL_RECOGNIZE_TEXT`, registration, input schema, unit tests |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `vision.text` is in server enabled capabilities |
| Apple TCC | **None** — client-provided image bytes only (#151) |
| Settings | `vision-text` shipped → no `requiresAppleVisionAccess`; `serverEnabledMCPCapabilityIDs` includes `vision.text` when toggled on |

| Condition | Error code |
|-----------|------------|
| Invalid JSON / missing `image_data` / bad base64 | `invalid_arguments` |
| Undecodable image bytes | `invalid_arguments` |
| `VNImageRequestHandler.perform` failure | `vision_error` |
| Serialization failure | `vision_error` |

Rust: tool absent from `tools/list` when `vision.text` not enabled; `tools/call` with disabled capability returns typed MCP error without provider dispatch (existing pattern).

---

## Acceptance criteria (#114)

1. `vision.recognize_text` in `tools/list` when `vision.text` enabled.
2. Valid `tools/call` succeeds against mock/live Vision per tests.
3. Disabled capability → typed MCP error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `vision-text` capability `shipped: true`.
6. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): enable Vision Text in Settings, call tool with a small PNG/JPEG image as base64.