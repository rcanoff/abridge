# vision.scan_document MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Approved  
**Issue:** #115 (Epic #103; depends on #114 `vision.recognize_text`)  
**Branch:** `feat/vision-scan-document`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-30-vision-permissions-foundation-design.md`  
**Sibling:** `docs/superpowers/specs/2026-06-30-vision-recognize-text-design.md`

---

## Summary

Implement `vision.scan_document` MCP tool: structured document recognition via **`RecognizeDocumentsRequest`** / **`ImageRequestHandler`** (macOS 26 Swift Vision API). Client supplies image bytes as **base64** (no camera or Photos TCC). Returns **exhaustive `DocumentObservation` JSON projection** (recursive `Container` tree, nested Swift `RecognizedTextObservation`, `BarcodeObservation`, `DataDetectorMatch`, geometry helpers in shared `VisionSerialization`). Register in Rust tool catalog gated by **`vision.document`**. Flip `vision-document` capability to **`shipped: true`**. No Apple permission gate per #151 (payload-only V1). Depends on #114 for Vision provider scaffolding and serialization helpers.

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `vision.scan_document` |
| Capability | `vision.document` |
| Provider | `vision` |
| Operation | `scan_document` |

### Vision API choice

Use **`ImageRequestHandler`** with **`RecognizeDocumentsRequest`** (macOS 26+ Swift Vision API):

| MCP argument | Apple API |
|--------------|-----------|
| `image_data` | Decode base64 → `Data` → `ImageRequestHandler(_:orientation:)` |
| `orientation` (optional) | `CGImagePropertyOrientation` on handler init (EXIF 1–8) |
| `revision` (optional) | `RecognizeDocumentsRequest.Revision` (`revision1`); omit for default |
| `region_of_interest` (optional) | `request.regionOfInterest` (`NormalizedRect`) |
| `text_recognition_options` (optional) | `request.textRecognitionOptions` (`TextRecognitionOptions`) |
| `text_recognition_options.minimum_text_height_fraction` | `minimumTextHeightFraction` |
| `text_recognition_options.automatically_detect_language` | `automaticallyDetectLanguage` |
| `text_recognition_options.recognition_languages` | `recognitionLanguages` (`[Locale.Language]` from BCP-47 strings) |
| `text_recognition_options.use_language_correction` | `useLanguageCorrection` |
| `text_recognition_options.custom_words` | `customWords` |
| `text_recognition_options.maximum_candidate_count` | `maximumCandidateCount` (argument to `topCandidates(_:)` when serializing nested text) |
| `barcode_detection_options` (optional) | `request.barcodeDetectionOptions` (`BarcodeDetectionOptions`) |
| `barcode_detection_options.enabled` | `enabled` |
| `barcode_detection_options.symbologies` | `symbologies` (`[BarcodeSymbology]`) |
| `barcode_detection_options.coalesce_composite_symbologies` | `coalesceCompositeSymbologies` |
| `include_segmentation` (optional) | When `true`, also run **`DetectDocumentSegmentationRequest`** on same handler and return `segmentation` |

`ImageRequestHandler.perform(_:)` is **async**. Bridge to the synchronous `ProviderBridge` path using the existing **`MapKitSearchFetch.waitForCompletion`** pattern (`DispatchQueue.main.async` + `Task` + run-loop pump) — same deadlock avoidance as MapKit live store.

Do **not** use the legacy **`VNDetectDocumentSegmentationRequest`** + **`VNRecognizeTextRequest`** pipeline as the primary path — that yields flat rectangles / OCR without structured document content (`title`, `tables`, `lists`, nested `Container`).

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
| `text_recognition_options` | object | no | Maps to `TextRecognitionOptions` |
| `text_recognition_options.minimum_text_height_fraction` | number (`minimum: 0`) | no | Relative to image height |
| `text_recognition_options.automatically_detect_language` | boolean | no | Apple default when omitted |
| `text_recognition_options.recognition_languages` | string array | no | BCP-47 language tags |
| `text_recognition_options.use_language_correction` | boolean | no | Apple default when omitted |
| `text_recognition_options.custom_words` | string array | no | Lexicon additions |
| `text_recognition_options.maximum_candidate_count` | integer (`minimum: 1`, `maximum: 10`) | no | Default `1`; caps `topCandidates` on nested text observations |
| `barcode_detection_options` | object | no | Maps to `BarcodeDetectionOptions` |
| `barcode_detection_options.enabled` | boolean | no | Apple default when omitted |
| `barcode_detection_options.symbologies` | string array | no | `BarcodeSymbology` raw values (e.g. `qr`, `code128`) |
| `barcode_detection_options.coalesce_composite_symbologies` | boolean | no | Apple default when omitted |
| `include_segmentation` | boolean | no | Default `false`; when `true`, run `DetectDocumentSegmentationRequest` |

Empty/missing `image_data`, whitespace-only, or invalid base64 → Swift `invalid_arguments`.  
Invalid enum / out-of-range `orientation` or `maximum_candidate_count` → `invalid_arguments`.

### Output

JSON **object** mirroring `RecognizeDocumentsRequest` results (not a bare array):

```json
{
  "results": [
    {
      "uuid": "…",
      "confidence": 1.0,
      "time_range": { "start_seconds": 0.0, "duration_seconds": 0.0 },
      "originating_request_descriptor": null,
      "document": { }
    }
  ],
  "segmentation": null
}
```

`results` is an empty array when Vision finds no documents (success, not error).  
`segmentation` is `null` when `include_segmentation` is `false` or omitted; otherwise a complete `DetectedDocumentObservation` projection or `null` when segmentation finds no document.

---

## Framework fidelity

Extend **`VisionSerialization`** from #114; reuse geometry / time-range helpers. Add Swift Vision type projections alongside existing `VN*` paths from `recognize_text`.

Every response object uses **complete key projection** — all keys present, `null` for absent optionals, snake_case encoding. Never omit keys.

### `DocumentObservation` keys (macOS 26 SDK)

| Key | Source | Encoding |
|-----|--------|----------|
| `uuid` | `DocumentObservation.uuid` | UUID string |
| `confidence` | `DocumentObservation.confidence` | number (`0`–`1`) |
| `time_range` | `DocumentObservation.timeRange` | `CMTimeRange` object or zeroed object when `nil` |
| `originating_request_descriptor` | `DocumentObservation.originatingRequestDescriptor` | `RequestDescriptor` object or `null` |
| `document` | `DocumentObservation.document` | `Container` object (see below) |

`description` is **not** serialized (debug string; not stable contract data).

### `DocumentObservation.Container` (recursive)

| Key | Source | Encoding |
|-----|--------|----------|
| `title` | `Container.title` | `Text` object or `null` |
| `text` | `Container.text` | `Text` object |
| `paragraphs` | `Container.paragraphs` | array of `Text` objects |
| `tables` | `Container.tables` | array of `Table` objects |
| `lists` | `Container.lists` | array of `List` objects |
| `barcodes` | `Container.barcodes` | array of `BarcodeObservation` objects |
| `bounding_region` | `Container.boundingRegion` | `NormalizedRegion` object |

#### `Container.Text`

| Key | Source | Encoding |
|-----|--------|----------|
| `transcript` | `Text.transcript` | string |
| `text_alignment` | `Text.textAlignment` | enum string (`center`, `leading`, `trailing`) or `null` |
| `detected_data` | `Text.detectedData` | array of `DataDetectorMatch` objects |
| `lines` | `Text.lines` | array of Swift `RecognizedTextObservation` objects |
| `words` | `Text.words` | array of Swift `RecognizedTextObservation` objects or `null` |
| `bounding_region` | `Text.boundingRegion` | `NormalizedRegion` object |

`boundingRegion(for:)` is a **range-parameterized method** — not serialized in V1 read responses.

#### `Container.Table`

| Key | Source | Encoding |
|-----|--------|----------|
| `rows` | `Table.rows` | 2D array of `Cell` objects |
| `columns` | `Table.columns` | 2D array of `Cell` objects |
| `bounding_region` | `Table.boundingRegion` | `NormalizedRegion` object |

`cell(row:col:)` is a **parameterized accessor** — not serialized; use `rows` / `columns` arrays.

#### `Container.Table.Cell`

| Key | Source | Encoding |
|-----|--------|----------|
| `content` | `Cell.content` | nested `Container` object |
| `row_range` | `Cell.rowRange` | `{ "lower": int, "upper": int }` |
| `column_range` | `Cell.columnRange` | `{ "lower": int, "upper": int }` |

#### `Container.List`

| Key | Source | Encoding |
|-----|--------|----------|
| `items` | `List.items` | array of `Item` objects |
| `bounding_region` | `List.boundingRegion` | `NormalizedRegion` object |

#### `Container.List.Item`

| Key | Source | Encoding |
|-----|--------|----------|
| `content` | `Item.content` | nested `Container` object |
| `marker_type` | `Item.markerType` | enum string or `null` |
| `marker_string` | `Item.markerString` | string |
| `item_string` | `Item.itemString` | string |

`Marker` enum values: `bullet`, `hyphen`, `lowercase_latin`, `uppercase_latin`, `decimal`, `decorative_decimal`, `composite_decimal`.

#### `Container.DataDetectorMatch`

| Key | Source | Encoding |
|-----|--------|----------|
| `match` | `DataDetectorMatch.match` | `DataDetector.Match` object |
| `bounding_region` | `DataDetectorMatch.boundingRegion` | `NormalizedRegion` object |

##### `DataDetector.Match`

| Key | Source | Encoding |
|-----|--------|----------|
| `range` | `Match.range` | `{ "location": int, "length": int }` relative to parent transcript, or `null` |
| `preferred_highlight_style` | `Match.preferredHighlightStyle` | enum string (`hidden`, `url`, `regular`) |
| `details` | `Match.details` | tagged union object (see below) |

`details` tagged union (`type` + payload):

| `type` | Payload keys |
|--------|----------------|
| `link` | `url` (string) |
| `email_address` | `email_address`, `label` |
| `phone_number` | `phone_number`, `label` |
| `postal_address` | `full_address`, `street`, `city`, `state`, `postal_code`, `region`, `region_code`, `label` |
| `calendar_event` | `all_day`, `start_date` (ISO8601), `start_time_zone`, `end_date`, `end_time_zone` |
| `money_amount` | `currency` (identifier string), `amount` (string decimal) |
| `flight_number` | `airline_code`, `flight_number` |
| `shipment_tracking_number` | `carrier`, `tracking_number`, `tracking_url` |
| `measurement` | `value`, `possible_dimensions` (array of unit symbol strings) |
| `payment_identifier` | `identifier`, `payment_system` (`unified_payments_interface`) |

### Swift `RecognizedTextObservation` (nested in document text; macOS 26)

Distinct from `VNRecognizedTextObservation` used by `recognize_text`. Project all properties:

| Key | Source | Encoding |
|-----|--------|----------|
| `uuid` | `uuid` | UUID string |
| `confidence` | `confidence` | number |
| `time_range` | `timeRange` | `CMTimeRange` object or zeroed |
| `originating_request_descriptor` | `originatingRequestDescriptor` | object or `null` |
| `top_left` | `topLeft` | `NormalizedPoint` object |
| `top_right` | `topRight` | `NormalizedPoint` object |
| `bottom_right` | `bottomRight` | `NormalizedPoint` object |
| `bottom_left` | `bottomLeft` | `NormalizedPoint` object |
| `bounding_region` | `boundingRegion` | `NormalizedRegion` object |
| `transcript` | `transcript` | string |
| `recognition_languages` | `recognitionLanguages` | array of BCP-47 language strings |
| `is_title` | `isTitle` | boolean |
| `should_wrap_to_next_line` | `shouldWrapToNextLine` | boolean or `null` |
| `text_direction` | `textDirection` | enum string (`left_to_right`, `right_to_left`, `top_to_bottom`) or `null` |
| `candidates` | `topCandidates(maximum_candidate_count)` | array of `RecognizedText` objects |

#### Nested `RecognizedText` (`candidates[]`)

| Key | Source | Encoding |
|-----|--------|----------|
| `string` | `string` | string |
| `confidence` | `confidence` | number |

`boundingBox(for:)` is a **range-parameterized method** — not serialized.

### `BarcodeObservation` (nested in document or standalone)

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

### `DetectedDocumentObservation` (`segmentation` when requested)

| Key | Source | Encoding |
|-----|--------|----------|
| `uuid` | `uuid` | UUID string |
| `confidence` | `confidence` | number |
| `time_range` | `timeRange` | `CMTimeRange` object or zeroed |
| `originating_request_descriptor` | `originatingRequestDescriptor` | object or `null` |
| `global_segmentation_mask` | `globalSegmentationMask` | `PixelBufferObservation` object |
| `top_left` | `topLeft` | `NormalizedPoint` object |
| `top_right` | `topRight` | `NormalizedPoint` object |
| `bottom_right` | `bottomRight` | `NormalizedPoint` object |
| `bottom_left` | `bottomLeft` | `NormalizedPoint` object |

### Shared geometry / buffer helpers

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

#### `NormalizedRegion` (`ContoursObservation.Contour`)

| Key | Source | Encoding |
|-----|--------|----------|
| `aspect_ratio` | `aspectRatio` | number |
| `index_path` | `indexPath` | array of integers |
| `point_count` | `pointCount` | integer |
| `normalized_points` | `normalizedPoints` | array of `{ "x": number, "y": number }` |
| `child_contours` | `childContours` | recursive array of `NormalizedRegion` objects |

`normalizedPath` (`CGPath`) is **not** serialized separately when `normalized_points` is available.

#### `PixelBufferObservation` (`global_segmentation_mask`)

| Key | Source | Encoding |
|-----|--------|----------|
| `uuid` | `uuid` | UUID string |
| `confidence` | `confidence` | number |
| `time_range` | `timeRange` | `CMTimeRange` object or zeroed |
| `originating_request_descriptor` | `originatingRequestDescriptor` | object or `null` |
| `size.width` | `size.width` | number |
| `size.height` | `size.height` | number |
| `pixel_format` | `pixelFormat` | FourCC string |
| `pixel_buffer` | `withUnsafePointer` plane bytes | object (width, height, pixel_format, bytes_per_row, data base64) or `null` on lock failure |

#### `RequestDescriptor`

| Key | Encoding |
|-----|----------|
| `identifier` | string (mechanical `String(describing:)` or stable descriptor id from SDK) |

---

## Architecture

```
Rust tools/call → ProviderBridge → VisionProvider.scan_document
                                        ↓
                              VisionStore (protocol)
                                        ↓
                         LiveVisionStore / MockVisionStore
                                        ↓
              ImageRequestHandler.perform(RecognizeDocumentsRequest)
              [+ DetectDocumentSegmentationRequest when include_segmentation]
```

### Swift files (new)

| File | Role |
|------|------|
| `ABridge/Providers/Vision/VisionProviderScanDocument.swift` | Operation handler + argument parsing |
| `ABridge/Providers/Vision/VisionAsyncBridge.swift` | Async `ImageRequestHandler` → sync bridge (extract MapKit pattern) |
| `ABridgeTests/VisionProviderScanDocumentTests.swift` | Provider end-to-end tests |
| `ABridgeTests/VisionDocumentSerializationTests.swift` | `DocumentObservation` projection completeness |

### Swift files (modify)

| File | Change |
|------|--------|
| `ABridge/Providers/Vision/VisionSerialization.swift` | Add document / barcode / contour / Swift text projections |
| `ABridge/Providers/Vision/VisionStore.swift` | `scanDocument` protocol method + request type |
| `ABridge/Providers/Vision/LiveVisionStore.swift` | `ImageRequestHandler` async wrapper |
| `ABridge/Providers/Vision/VisionProviderRouting.swift` | `scan_document` dispatch |
| `ABridge/Models/CapabilityCatalog.swift` | `vision-document` → `shipped: true` |
| `ABridgeTests/MockVisionStore.swift` | Fake document results for CI |
| `ABridgeTests/AppleProviderBridgeVisionTests.swift` | Success path for `scan_document` (replace `unknown_operation` expectation) |
| `ABridgeTests/AppSettingsVisionTests.swift` | Shipped capability server gating |
| `README.md` | Check off `vision.scan_document` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/abridge_core/src/capabilities.rs` | `VISION_DOCUMENT` constant + `is_allowed_in_v1` |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_SCAN_DOCUMENT`, registration, input schema, unit tests |
| `rust/abridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `vision.document` is in server enabled capabilities |
| Apple TCC | **None** — client-provided image bytes only (#151) |
| Settings | `vision-document` shipped → no Apple Vision TCC row; `serverEnabledMCPCapabilityIDs` includes `vision.document` when toggled on |

| Condition | Error code |
|-----------|------------|
| Invalid JSON / missing `image_data` / bad base64 | `invalid_arguments` |
| Undecodable image bytes | `invalid_arguments` |
| `ImageRequestHandler.perform` failure | `vision_error` |
| Serialization failure | `vision_error` |

Rust: tool absent from `tools/list` when `vision.document` not enabled; `tools/call` with disabled capability returns typed MCP error without provider dispatch (existing pattern).

---

## Dependency on #114 (`vision.recognize_text`)

| #114 deliverable | #115 reuse |
|------------------|------------|
| `VisionProvider` + routing shell | Add `scan_document` case |
| `VisionSerialization` geometry helpers | Extend for document tree |
| `VisionStore` protocol seam | Add `scanDocument` method |
| `MockVisionStore` pattern | Add canned `DocumentObservation` fixtures |
| Capability / MCP test patterns | Mirror for `vision.document` |

#115 does **not** require `vision.text` capability to be enabled — only that #114 code is merged on `main`.

---

## Acceptance criteria (#115)

1. `vision.scan_document` in `tools/list` when `vision.document` enabled.
2. Valid `tools/call` succeeds against mock/live Vision per tests.
3. Disabled capability → typed MCP error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `vision-document` capability `shipped: true`.
6. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): enable Vision Document in Settings, call tool with a photo of a printed page as base64.