# vision.detect_faces MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Approved  
**Issue:** #118 (Epic #103; depends on #114 `vision.recognize_text`)  
**Branch:** `feat/vision-detect-faces`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-30-vision-permissions-foundation-design.md`  
**Reference:** `docs/superpowers/specs/2026-06-30-vision-recognize-text-design.md`

---

## Summary

Implement `vision.detect_faces` MCP tool: face detection with bounding boxes and facial landmarks via **`VNDetectFaceLandmarksRequest`** / **`VNImageRequestHandler`**. Client supplies image bytes as **base64** (no camera or Photos TCC). Returns **exhaustive `VNFaceObservation` JSON projection** (mechanical snake_case serialization, shared `VisionSerialization` helpers from #114). Register in Rust tool catalog gated by **`vision.faces`**. Flip `vision-faces` capability to **`shipped: true`**. No Apple permission gate per #151 (payload-only V1).

**Pattern:** Mirrors `vision.recognize_text` (#114) — synchronous `VNImageRequestHandler.perform`, `VisionStore` protocol seam, dedicated provider operation file, Rust tool registration. `VNDetectFaceLandmarksRequest` runs face detection when no input observations are supplied, then populates `landmarks` on each `VNFaceObservation`.

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `vision.detect_faces` |
| Capability | `vision.faces` |
| Provider | `vision` |
| Operation | `detect_faces` |

### Vision API choice

Use **`VNImageRequestHandler`** with **`VNDetectFaceLandmarksRequest`** (same handler class as `recognize_text`, not `ImageRequestHandler`):

| MCP argument | Apple API |
|--------------|-----------|
| `image_data` | Decode base64 → `Data` → `CGImage` for `VNImageRequestHandler(cgImage:orientation:options:)` |
| `orientation` (optional) | `CGImagePropertyOrientation` on handler init (EXIF 1–8) |
| `revision` (optional) | `request.revision` |
| `region_of_interest` (optional) | `request.regionOfInterest` (`CGRect`, normalized) |
| `constellation` (optional) | `request.constellation` (`VNRequestFaceLandmarksConstellation`) |

**Fixed at implementation (not MCP arguments):**

| Behavior | Apple API |
|----------|-----------|
| No pre-supplied face boxes | Do **not** set `inputFaceObservations`; request performs detection then landmark extraction |

`VNImageRequestHandler.perform([request])` runs **synchronously** on the calling thread — no RunLoop pump required (same as `recognize_text`).

Do **not** read from camera, Photos, or filesystem paths; image input is **in-memory client payload only**.

Do **not** use `DetectFaceLandmarksRequest` / `FaceObservation` (macOS 26 Swift Vision API) in this subtask — that type path is distinct from the `VNFaceObservation` fidelity model documented in #151 and used by the `VN*` tools from #114. This tool projects legacy **`VNFaceObservation`** with nested **`VNFaceLandmarks2D`**.

Do **not** expose `input_face_observations` in V1 — clients supply only image bytes; the request performs integrated detection + landmarks.

### Input schema (Rust `input_schema`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `image_data` | string (`minLength: 1`) | **yes** | Base64-encoded image bytes (PNG, JPEG, HEIC, etc.) |
| `orientation` | integer | no | EXIF orientation `1`–`8`; omit for image metadata default |
| `revision` | integer | no | `VNDetectFaceLandmarksRequest` revision; omit for `defaultRevision` |
| `region_of_interest` | object | no | Normalized crop region |
| `region_of_interest.origin.x` | number | if `region_of_interest` | |
| `region_of_interest.origin.y` | number | if `region_of_interest` | |
| `region_of_interest.size.width` | number | if `region_of_interest` | |
| `region_of_interest.size.height` | number | if `region_of_interest` | |
| `constellation` | string enum | no | `not_defined`, `65_points`, `76_points`; omit for SDK default (`not_defined`) |

Empty/missing `image_data`, whitespace-only, or invalid base64 → Swift `invalid_arguments`.  
Invalid enum / out-of-range `orientation` or unsupported `constellation` for the chosen `revision` → `invalid_arguments`.

### Output

JSON **object** mirroring `VNDetectFaceLandmarksRequest.results` (not a bare array):

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
      "roll": null,
      "yaw": null,
      "pitch": null,
      "face_capture_quality": null,
      "landmarks": null
    }
  ]
}
```

`results` is an empty array when Vision finds no faces (success, not error).  
`landmarks` is `null` when the request revision/constellation yields no landmark data for an observation; when non-`null`, it is a complete `VNFaceLandmarks2D` projection (see below).

---

## Framework fidelity

Extend **`VisionSerialization`** from #114; reuse geometry / time-range / pixel-buffer helpers from `recognize_text`.

Every `results[]` element is a **complete `VNFaceObservation` projection** — all keys present, `null` for absent optionals, snake_case encoding. Never omit keys.

### `VNFaceObservation` keys (macOS 26 SDK)

Inheritance: `VNFaceObservation` → `VNDetectedObjectObservation` → `VNObservation`.

| Key | Source | Encoding |
|-----|--------|----------|
| `uuid` | `VNObservation.uuid` | UUID string |
| `confidence` | `VNObservation.confidence` | number (`VNConfidence`, 0–1) |
| `time_range` | `VNObservation.timeRange` | `CMTimeRange` object or zeroed object for still images |
| `request_revision` | `VNRequestRevisionProviding.requestRevision` | integer |
| `bounding_box` | `VNDetectedObjectObservation.boundingBox` | normalized `CGRect` object |
| `global_segmentation_mask` | `VNDetectedObjectObservation.globalSegmentationMask` | `VNPixelBufferObservation` object or `null` |
| `roll` | `VNFaceObservation.roll` | number (radians) or `null` |
| `yaw` | `VNFaceObservation.yaw` | number (radians) or `null` |
| `pitch` | `VNFaceObservation.pitch` | number (radians) or `null` |
| `face_capture_quality` | `VNFaceObservation.faceCaptureQuality` | number (0–1) or `null` |
| `landmarks` | `VNFaceObservation.landmarks` | `VNFaceLandmarks2D` object or `null` |

`VNFaceObservation` does **not** inherit `VNRectangleObservation` corner properties (`top_left`, etc.) — do not invent them.

### `VNFaceLandmarks2D` keys (`landmarks` when non-`null`)

Inheritance: `VNFaceLandmarks2D` → `VNFaceLandmarks` → `VNRequestRevisionProviding`.

| Key | Source | Encoding |
|-----|--------|----------|
| `confidence` | `VNFaceLandmarks.confidence` | number |
| `request_revision` | `VNRequestRevisionProviding.requestRevision` | integer |
| `all_points` | `VNFaceLandmarks2D.allPoints` | `VNFaceLandmarkRegion2D` object or `null` |
| `face_contour` | `VNFaceLandmarks2D.faceContour` | `VNFaceLandmarkRegion2D` object or `null` |
| `left_eye` | `VNFaceLandmarks2D.leftEye` | `VNFaceLandmarkRegion2D` object or `null` |
| `right_eye` | `VNFaceLandmarks2D.rightEye` | `VNFaceLandmarkRegion2D` object or `null` |
| `left_eyebrow` | `VNFaceLandmarks2D.leftEyebrow` | `VNFaceLandmarkRegion2D` object or `null` |
| `right_eyebrow` | `VNFaceLandmarks2D.rightEyebrow` | `VNFaceLandmarkRegion2D` object or `null` |
| `nose` | `VNFaceLandmarks2D.nose` | `VNFaceLandmarkRegion2D` object or `null` |
| `nose_crest` | `VNFaceLandmarks2D.noseCrest` | `VNFaceLandmarkRegion2D` object or `null` |
| `median_line` | `VNFaceLandmarks2D.medianLine` | `VNFaceLandmarkRegion2D` object or `null` |
| `outer_lips` | `VNFaceLandmarks2D.outerLips` | `VNFaceLandmarkRegion2D` object or `null` |
| `inner_lips` | `VNFaceLandmarks2D.innerLips` | `VNFaceLandmarkRegion2D` object or `null` |
| `left_pupil` | `VNFaceLandmarks2D.leftPupil` | `VNFaceLandmarkRegion2D` object or `null` |
| `right_pupil` | `VNFaceLandmarks2D.rightPupil` | `VNFaceLandmarkRegion2D` object or `null` |

### `VNFaceLandmarkRegion2D` keys (each landmark region)

| Key | Source | Encoding |
|-----|--------|----------|
| `point_count` | `VNFaceLandmarkRegion.pointCount` | integer |
| `request_revision` | `VNRequestRevisionProviding.requestRevision` | integer |
| `normalized_points` | `VNFaceLandmarkRegion2D.normalizedPoints` | array of `{ "x": number, "y": number }` (length `point_count`) |
| `precision_estimates_per_point` | `VNFaceLandmarkRegion2D.precisionEstimatesPerPoint` | array of numbers or `null` (populated for 76-point constellation) |
| `points_classification` | `VNFaceLandmarkRegion2D.pointsClassification` | enum string (`disconnected`, `open_path`, `closed_path`) |

`pointsInImageOfSize(_:)` is a **parameterized method** — not serialized in V1 read responses.

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

### Nested `VNPixelBufferObservation` (`global_segmentation_mask`)

Reuse the helper from #114 (`uuid`, `confidence`, `time_range`, `request_revision`, `pixel_buffer`, `feature_name`).

---

## Architecture

```
Rust tools/call → ProviderBridge → VisionProvider.detect_faces
                                        ↓
                              VisionStore (protocol)
                                        ↓
                         LiveVisionStore / MockVisionStore
                                        ↓
              VNImageRequestHandler.perform([VNDetectFaceLandmarksRequest])
```

### Swift files (new)

| File | Role |
|------|------|
| `ABridge/Providers/Vision/VisionFaceSerialization.swift` | `VNFaceObservation` / landmark region JSON |
| `ABridge/Providers/Vision/VisionProviderDetectFaces.swift` | Operation handler |
| `ABridgeTests/VisionFaceSerializationTests.swift` | Landmark projection completeness |
| `ABridgeTests/VisionProviderDetectFacesTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `ABridge/Providers/Vision/VisionSerialization.swift` | `detectFacesResponseJSONObject` wrapper delegating to face serialization |
| `ABridge/Providers/Vision/VisionStore.swift` | `VisionDetectFacesRequest` + `detectFaces` on protocol |
| `ABridge/Providers/Vision/LiveVisionStore.swift` | `VNDetectFaceLandmarksRequest` sync wrapper |
| `ABridge/Providers/Vision/VisionProviderRouting.swift` | `detect_faces` dispatch |
| `ABridgeTests/MockVisionStore.swift` | Fake face results for CI |
| `ABridgeTests/AppleProviderBridgeVisionTests.swift` | Success path for `detect_faces` |
| `ABridgeTests/AppSettingsVisionTests.swift` | Shipped capability server gating |
| `ABridge/Models/CapabilityCatalog.swift` | `vision-faces` → `shipped: true` |
| `README.md` | Check off `vision.detect_faces` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/abridge_core/src/capabilities.rs` | `VISION_FACES` constant + `is_allowed_in_v1` |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_DETECT_FACES`, registration, input schema, unit tests |
| `rust/abridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `vision.faces` is in server enabled capabilities |
| Apple TCC | **None** — client-provided image bytes only (#151) |
| Settings | `vision-faces` shipped → no Apple Vision TCC row; `serverEnabledMCPCapabilityIDs` includes `vision.faces` when toggled on |

| Condition | Error code |
|-----------|------------|
| Invalid JSON / missing `image_data` / bad base64 | `invalid_arguments` |
| Undecodable image bytes | `invalid_arguments` |
| `VNImageRequestHandler.perform` failure | `vision_error` |
| Serialization failure | `vision_error` |

Rust: tool absent from `tools/list` when `vision.faces` not enabled; `tools/call` with disabled capability returns typed MCP error without provider dispatch (existing pattern).

---

## Dependency on #114 (`vision.recognize_text`)

| #114 deliverable | #118 reuse |
|------------------|------------|
| `VisionProvider` + routing shell | Add `detect_faces` case |
| `VisionSerialization` geometry helpers | Extend for face / landmark regions |
| `VisionStore` protocol seam | Add `detectFaces` method |
| `MockVisionStore` pattern | Add canned `VNFaceObservation` fixtures |
| Capability / MCP test patterns | Mirror for `vision.faces` |

#118 does **not** require other Vision capabilities to be enabled — only that #114 code is merged on `main`.

---

## Acceptance criteria (#118)

1. `vision.detect_faces` in `tools/list` when `vision.faces` enabled.
2. Valid `tools/call` succeeds against mock/live Vision per tests.
3. Disabled capability → typed MCP error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `vision-faces` capability `shipped: true`.
6. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): enable Vision Faces in Settings, call tool with a portrait image as base64.