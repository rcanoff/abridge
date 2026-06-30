# vision.scan_document Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vision.scan_document` MCP tool (#115) with exhaustive `DocumentObservation` JSON projection.

**Architecture:** Extend `VisionStore` + `VisionSerialization` from #114; `RecognizeDocumentsRequest` via async `ImageRequestHandler` bridged synchronously; Rust tool registration with `vision.document` capability; flip `vision-document` to shipped; no Apple TCC gate per #151.

**Tech Stack:** Rust (`apple_bridge_core`), Swift 6 + Vision + DataDetection + CoreGraphics, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-vision-scan-document-design.md`

**Prerequisite:** #114 (`vision.recognize_text`) merged on `main`.

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/capabilities.rs` | `VISION_DOCUMENT` constant |
| `rust/apple_bridge_core/src/tools/mod.rs` | Tool registration + input schema |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `AppleBridge/Providers/Vision/VisionSerialization.swift` | Document tree / barcode / contour / Swift text JSON |
| `AppleBridge/Providers/Vision/VisionAsyncBridge.swift` | Sync bridge for async Vision requests |
| `AppleBridge/Providers/Vision/VisionStore.swift` | Scan-document protocol seam |
| `AppleBridge/Providers/Vision/LiveVisionStore.swift` | `ImageRequestHandler` wrapper |
| `AppleBridge/Providers/Vision/VisionProviderScanDocument.swift` | `scan_document` handler |
| `AppleBridge/Providers/Vision/VisionProviderRouting.swift` | Operation dispatch |
| `AppleBridgeTests/MockVisionStore.swift` | Deterministic document results |
| `AppleBridgeTests/VisionDocumentSerializationTests.swift` | Fidelity assertions |
| `AppleBridgeTests/VisionProviderScanDocumentTests.swift` | Provider tests |
| `AppleBridge/Models/CapabilityCatalog.swift` | Ship `vision-document` |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/apple_bridge_core/src/capabilities.rs`
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`

- [ ] **Step 1: Add `VISION_DOCUMENT` to capabilities.rs**

```rust
pub const VISION_DOCUMENT: &str = "vision.document";
```

Add to `is_allowed_in_v1` match arm and test:

```rust
#[test]
fn accepts_vision_document_capability_shape() {
  assert!(is_valid_capability_id(VISION_DOCUMENT));
  assert!(is_allowed_in_v1(VISION_DOCUMENT));
}
```

- [ ] **Step 2: Register tool in tools/mod.rs**

```rust
pub const TOOL_SCAN_DOCUMENT: &str = "vision.scan_document";
```

Add to `ALL_TOOLS` (bump array length 53 → 54):

```rust
ToolDefinition {
  name: TOOL_SCAN_DOCUMENT,
  capability: capabilities::VISION_DOCUMENT,
  provider: "vision",
  operation: "scan_document",
  description: "Scan and recognize structured document content in a client-provided image using Vision framework",
},
```

- [ ] **Step 3: Add input schema**

```rust
TOOL_SCAN_DOCUMENT => serde_json::json!({
  "type": "object",
  "properties": {
    "image_data": { "type": "string", "minLength": 1 },
    "orientation": { "type": "integer", "minimum": 1, "maximum": 8 },
    "revision": { "type": "string", "enum": ["revision1"] },
    "region_of_interest": {
      "type": "object",
      "properties": {
        "origin": {
          "type": "object",
          "properties": {
            "x": { "type": "number" },
            "y": { "type": "number" }
          },
          "required": ["x", "y"]
        },
        "size": {
          "type": "object",
          "properties": {
            "width": { "type": "number" },
            "height": { "type": "number" }
          },
          "required": ["width", "height"]
        }
      },
      "required": ["origin", "size"]
    },
    "text_recognition_options": {
      "type": "object",
      "properties": {
        "minimum_text_height_fraction": { "type": "number", "minimum": 0 },
        "automatically_detect_language": { "type": "boolean" },
        "recognition_languages": {
          "type": "array",
          "items": { "type": "string" }
        },
        "use_language_correction": { "type": "boolean" },
        "custom_words": {
          "type": "array",
          "items": { "type": "string" }
        },
        "maximum_candidate_count": { "type": "integer", "minimum": 1, "maximum": 10 }
      }
    },
    "barcode_detection_options": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" },
        "symbologies": {
          "type": "array",
          "items": { "type": "string" }
        },
        "coalesce_composite_symbologies": { "type": "boolean" }
      }
    },
    "include_segmentation": { "type": "boolean" }
  },
  "required": ["image_data"]
}),
```

- [ ] **Step 4: Add unit tests in tools/mod.rs tests module**

```rust
#[test]
fn lists_scan_document_tool_when_vision_document_capability_enabled() {
  let tools = tools_for_capabilities(&["vision.document".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_SCAN_DOCUMENT]);
}

#[test]
fn scan_document_schema_requires_image_data() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_SCAN_DOCUMENT)
    .expect("scan_document tool");
  let schema = input_schema(tool);
  assert_eq!(string_property_min_length(&schema, "image_data"), Some(1));
}
```

- [ ] **Step 5: Run Rust tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/apple_bridge_core/src/capabilities.rs rust/apple_bridge_core/src/tools/mod.rs
git commit -m "feat(vision): register vision.scan_document MCP tool in Rust"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Write integration tests** (reuse `vision_config_on_port` from #114)

```rust
#[test]
fn mcp_tools_list_includes_scan_document_when_vision_document_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    vision_config_on_port(port, vec!["vision.document".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("vision.scan_document"));
}

#[test]
fn tools_call_dispatches_scan_document() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"vision.scan_document","arguments":{"image_data":"aGVsbG8="}}}"#;

  let handle = create_server(
    vision_config_on_port(port, vec!["vision.document".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains(r#""isError":false"#));
  let recorded = mock.last_request.lock().expect("lock").clone().expect("request");
  assert_eq!(recorded.provider, "vision");
  assert_eq!(recorded.operation, "scan_document");
  assert!(recorded.payload_json.contains("image_data"));
}
```

- [ ] **Step 2: Run tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add rust/apple_bridge_core/tests/mcp_protocol.rs
git commit -m "test(vision): add MCP integration tests for scan_document"
```

---

### Task 3: VisionAsyncBridge + document serialization

**Files:**
- Create: `AppleBridge/Providers/Vision/VisionAsyncBridge.swift`
- Modify: `AppleBridge/Providers/Vision/VisionSerialization.swift`
- Create: `AppleBridgeTests/VisionDocumentSerializationTests.swift`

- [ ] **Step 1: Extract async bridge from MapKit pattern**

`VisionAsyncBridge` with `AsyncBridgeResult<T>` + `waitForCompletion(operation:work:)` — mirror `MapKitSearchFetch` (GCD `DispatchQueue.main.async` + `Task` + run-loop pump).

- [ ] **Step 2: Write failing serialization tests**

Assert `scanDocumentResponseJSONObject` top-level keys: `results`, `segmentation`.  
Assert each `DocumentObservation` element includes spec keys.  
Assert recursive `Container` coverage for `title`, `text`, `paragraphs`, `tables`, `lists`, `barcodes`, `bounding_region`.  
Assert Swift `RecognizedTextObservation` nested keys differ from `VN*` path (includes `transcript`, `bounding_region`, no `request_revision`).

- [ ] **Step 3: Implement document serialization in VisionSerialization.swift**

Add helpers:
- `scanDocumentResponseJSONObject(observations:segmentation:maximumCandidateCount:)`
- `documentObservationJSONObject(from:maximumCandidateCount:)`
- `documentContainerJSONObject(from:maximumCandidateCount:)` (recursive)
- `documentTextJSONObject`, `documentTableJSONObject`, `documentListJSONObject`, `dataDetectorMatchJSONObject`
- `swiftRecognizedTextObservationJSONObject(from:maximumCandidateCount:)`
- `barcodeObservationJSONObject(from:)`
- `normalizedRegionJSONObject(from:)` (recursive contours)
- `normalizedPointJSONObject(from:)`
- `pixelBufferObservationJSONObject(from:)` (Swift `PixelBufferObservation`)
- `detectedDocumentObservationJSONObject(from:)`
- `dataDetectorMatchDetailsJSONObject(from:)`

Reuse existing `cmTimeRangeJSONObject`, `cgRectJSONObject` where applicable.

- [ ] **Step 4: Run tests**

Run: `just test-swift`  
Expected: PASS for VisionDocumentSerializationTests

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Providers/Vision/VisionAsyncBridge.swift \
  AppleBridge/Providers/Vision/VisionSerialization.swift \
  AppleBridgeTests/VisionDocumentSerializationTests.swift
git commit -m "feat(vision): add document observation serialization"
```

---

### Task 4: VisionStore scan_document seam

**Files:**
- Modify: `AppleBridge/Providers/Vision/VisionStore.swift`
- Modify: `AppleBridge/Providers/Vision/LiveVisionStore.swift`
- Modify: `AppleBridgeTests/MockVisionStore.swift`

- [ ] **Step 1: Define request/result types**

```swift
struct VisionScanDocumentRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: RecognizeDocumentsRequest.Revision?
    let regionOfInterest: NormalizedRect?
    let textRecognitionOptions: RecognizeDocumentsRequest.TextRecognitionOptions?
    let barcodeDetectionOptions: RecognizeDocumentsRequest.BarcodeDetectionOptions?
    let includeSegmentation: Bool
    let maximumCandidateCount: Int
}

struct VisionScanDocumentResult: Equatable {
    let observations: [DocumentObservation]
    let segmentation: DetectedDocumentObservation?
}
```

- [ ] **Step 2: Extend VisionStoreing protocol**

```swift
func scanDocument(request: VisionScanDocumentRequest) throws -> VisionScanDocumentResult
```

- [ ] **Step 3: Implement LiveVisionStore**

Build `ImageRequestHandler(data:orientation:)`. Configure `RecognizeDocumentsRequest` from request fields. Use `VisionAsyncBridge.waitForCompletion` to call `try await handler.perform(recognizeRequest)`. When `includeSegmentation`, also `try await handler.perform(DetectDocumentSegmentationRequest())` and map result.

- [ ] **Step 4: Extend MockVisionStore**

Hold canned `VisionScanDocumentResult`; record `lastScanDocumentRequest`.

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Providers/Vision/VisionStore.swift \
  AppleBridge/Providers/Vision/LiveVisionStore.swift \
  AppleBridgeTests/MockVisionStore.swift
git commit -m "feat(vision): add VisionStore scan_document seam"
```

---

### Task 5: VisionProvider scan_document operation

**Files:**
- Create: `AppleBridge/Providers/Vision/VisionProviderScanDocument.swift`
- Modify: `AppleBridge/Providers/Vision/VisionProviderRouting.swift`
- Create: `AppleBridgeTests/VisionProviderScanDocumentTests.swift`
- Modify: `AppleBridgeTests/AppleProviderBridgeVisionTests.swift`

- [ ] **Step 1: Write failing provider tests**

Cases:
- Missing `image_data` → `invalid_arguments`
- Invalid base64 → `invalid_arguments`
- Mock store returns observations → success JSON with `results` array and `segmentation: null`
- `include_segmentation: true` forwarded to store
- `text_recognition_options.maximum_candidate_count` forwarded to serialization

- [ ] **Step 2: Implement scan_document handler**

Parse arguments mirroring `VisionProviderRecognizeText` helpers (reuse shared image/orientation/region parsers where possible). Map to `VisionScanDocumentRequest`. Call store. Serialize via `VisionSerialization.scanDocumentResponseJSONObject`.

- [ ] **Step 3: Add routing**

```swift
case "scan_document":
    scanDocument(payloadJson: payloadJson)
```

- [ ] **Step 4: Update AppleProviderBridgeVisionTests**

Replace `unknown_operation` test with success path using mock store returning document observations.

- [ ] **Step 5: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add AppleBridge/Providers/Vision/VisionProviderScanDocument.swift \
  AppleBridge/Providers/Vision/VisionProviderRouting.swift \
  AppleBridgeTests/VisionProviderScanDocumentTests.swift \
  AppleBridgeTests/AppleProviderBridgeVisionTests.swift
git commit -m "feat(vision): implement scan_document provider operation"
```

---

### Task 6: Ship capability + README + full verification

**Files:**
- Modify: `AppleBridge/Models/CapabilityCatalog.swift`
- Modify: `README.md`
- Modify: `AppleBridgeTests/AppSettingsVisionTests.swift`

- [ ] **Step 1: Flip capability shipped**

```swift
CapabilityDefinition(id: "vision-document", capabilityID: "vision.document", label: "Document", shipped: true),
```

- [ ] **Step 2: Update AppSettingsVisionTests**

When `vision-document` toggled on, `serverEnabledMCPCapabilityIDs` includes `vision.document` (no authorization gate).

- [ ] **Step 3: README checkoff**

```markdown
- [x] `vision.scan_document`
```

- [ ] **Step 4: Regenerate Xcode project if needed**

Run: `xcodegen generate`

- [ ] **Step 5: Run full verification**

Run: `TZ=UTC just test-all`  
Expected: PASS

Run: `TZ=UTC just ci`  
Expected: PASS (before merge)

- [ ] **Step 6: Commit**

```bash
git add AppleBridge/Models/CapabilityCatalog.swift README.md \
  AppleBridgeTests/AppSettingsVisionTests.swift project.yml
git commit -m "feat(vision): ship vision.document capability for scan_document"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `VISION_DOCUMENT` + `TOOL_SCAN_DOCUMENT` Rust registration | Task 1 |
| Input schema (`image_data` + optional RecognizeDocumentsRequest fields) | Task 1 |
| MCP integration tests | Task 2 |
| `RecognizeDocumentsRequest` via VisionStore + async bridge | Task 4 |
| Optional `DetectDocumentSegmentationRequest` when `include_segmentation` | Task 4 |
| Exhaustive `DocumentObservation` JSON tree | Task 3 |
| Swift `RecognizedTextObservation` nested serialization | Task 3 |
| No Apple permission gate | Task 5 |
| `vision-document` shipped | Task 6 |
| `just test-all` | Task 6 |