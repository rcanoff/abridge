# vision_detect_barcodes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vision_detect_barcodes` MCP tool (#117) with exhaustive `BarcodeObservation` JSON projection.

**Architecture:** Extend `VisionStore` from #114/#115; `DetectBarcodesRequest` via async `ImageRequestHandler` bridged synchronously; reuse `VisionDocumentObservationSerialization` barcode projection; Rust tool registration with `vision.barcodes` capability; flip `vision-barcodes` to shipped; no Apple TCC gate per #151.

**Tech Stack:** Rust (`abridge_core`), Swift 6 + Vision + CoreGraphics, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-vision-detect-barcodes-design.md`

**Prerequisite:** #114 (`vision_recognize_text`) and #115 (`vision_recognize_documents`) merged on `main`.

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/abridge_core/src/capabilities.rs` | `VISION_BARCODES` constant |
| `rust/abridge_core/src/tools/mod.rs` | Tool registration + input schema |
| `rust/abridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `ABridge/Providers/Vision/VisionBarcodeSerialization.swift` | `detect_barcodes` response wrapper |
| `ABridge/Providers/Vision/VisionStore.swift` | Detect-barcodes protocol seam |
| `ABridge/Providers/Vision/LiveVisionStore.swift` | `DetectBarcodesRequest` via `ImageRequestHandler` |
| `ABridge/Providers/Vision/VisionProviderDetectBarcodes.swift` | `detect_barcodes` handler |
| `ABridge/Providers/Vision/VisionProviderRouting.swift` | Operation dispatch |
| `ABridgeTests/MockVisionStore.swift` | Deterministic barcode results |
| `ABridgeTests/VisionBarcodeSerializationTests.swift` | Fidelity assertions |
| `ABridgeTests/VisionProviderDetectBarcodesTests.swift` | Provider tests |
| `ABridge/Models/CapabilityCatalog.swift` | Ship `vision-barcodes` |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/abridge_core/src/capabilities.rs`
- Modify: `rust/abridge_core/src/tools/mod.rs`
- Test: `rust/abridge_core/tests/mcp_protocol.rs` (Task 2)

- [ ] **Step 1: Add `VISION_BARCODES` to capabilities.rs**

```rust
pub const VISION_BARCODES: &str = "vision.barcodes";
```

Add to `is_valid_capability_id` early-return arm, `is_allowed_in_v1` match arm, and test:

```rust
#[test]
fn accepts_vision_barcodes_capability_shape() {
  assert!(is_valid_capability_id(VISION_BARCODES));
  assert!(is_allowed_in_v1(VISION_BARCODES));
}
```

- [ ] **Step 2: Register tool in tools/mod.rs**

```rust
pub const TOOL_DETECT_BARCODES: &str = "vision_detect_barcodes";
```

Add to `ALL_TOOLS` (bump array length 54 → 55):

```rust
ToolDefinition {
  name: TOOL_DETECT_BARCODES,
  capability: capabilities::VISION_BARCODES,
  provider: "vision",
  operation: "detect_barcodes",
  description: "Detect barcodes and QR codes in a client-provided image using Vision framework",
},
```

- [ ] **Step 3: Add input schema**

```rust
TOOL_DETECT_BARCODES => serde_json::json!({
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
    "symbologies": {
      "type": "array",
      "items": { "type": "string" }
    },
    "coalesce_composite_symbologies": { "type": "boolean" }
  },
  "required": ["image_data"]
}),
```

- [ ] **Step 4: Add unit tests in tools/mod.rs tests module**

```rust
#[test]
fn lists_detect_barcodes_tool_when_vision_barcodes_capability_enabled() {
  let tools = tools_for_capabilities(&["vision.barcodes".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_DETECT_BARCODES]);
}

#[test]
fn detect_barcodes_schema_requires_image_data() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_DETECT_BARCODES)
    .expect("detect_barcodes tool");
  let schema = input_schema(tool);
  assert_eq!(string_property_min_length(&schema, "image_data"), Some(1));
  assert_eq!(
    schema.get("required").and_then(|v| v.as_array()).map(|fields| {
      fields.iter().filter_map(|f| f.as_str().map(str::to_owned)).collect::<Vec<_>>()
    }),
    Some(vec!["image_data".to_owned()])
  );
}
```

- [ ] **Step 5: Run Rust tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/abridge_core/src/capabilities.rs rust/abridge_core/src/tools/mod.rs
git commit -m "feat(vision): register vision_detect_barcodes MCP tool in Rust"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/abridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Write integration tests** (reuse `vision_config_on_port` from #114)

```rust
#[test]
fn mcp_tools_list_includes_detect_barcodes_when_vision_barcodes_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    vision_config_on_port(port, vec!["vision.barcodes".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("vision_detect_barcodes"));
}

#[test]
fn tools_call_dispatches_detect_barcodes() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"vision_detect_barcodes","arguments":{"image_data":"aGVsbG8="}}}"#;

  let handle = create_server(
    vision_config_on_port(port, vec!["vision.barcodes".into()]),
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
  assert_eq!(recorded.operation, "detect_barcodes");
  assert!(recorded.payload_json.contains("image_data"));
}
```

- [ ] **Step 2: Run tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add rust/abridge_core/tests/mcp_protocol.rs
git commit -m "test(vision): add MCP integration tests for detect_barcodes"
```

---

### Task 3: VisionBarcodeSerialization (exhaustive BarcodeObservation)

**Files:**
- Create: `ABridge/Providers/Vision/VisionBarcodeSerialization.swift`
- Create: `ABridgeTests/VisionBarcodeSerializationTests.swift`

- [ ] **Step 1: Write failing serialization test**

Assert every top-level response key: `results`.  
Assert every `results[]` element includes all `BarcodeObservation` keys from spec: `uuid`, `confidence`, `time_range`, `originating_request_descriptor`, `payload_string`, `payload_data`, `supplemental_payload_string`, `supplemental_payload_data`, `supplemental_composite_type`, `is_gs1_data_carrier`, `symbology`, `is_color_inverted`, `top_left`, `top_right`, `bottom_right`, `bottom_left`, `bounding_region`.

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-swift`  
Expected: FAIL — `VisionBarcodeSerialization` not defined

- [ ] **Step 3: Implement VisionBarcodeSerialization.swift**

```swift
enum VisionBarcodeSerialization {
    static func detectBarcodesResponseJSONObject(observations: [BarcodeObservation]) -> [String: Any] {
        [
            "results": observations.map(barcodeObservationJSONObject(from:)),
        ]
    }

    static func barcodeObservationJSONObject(from observation: BarcodeObservation) -> [String: Any] {
        VisionDocumentObservationSerialization.barcodeObservationJSONObject(
            from: observation,
            boundingRegion: VisionDocumentObservationSerialization.normalizedRegionJSONObject(
                from: observation.boundingRegion
            )
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run: `just test-swift`  
Expected: PASS for VisionBarcodeSerializationTests

- [ ] **Step 5: Commit**

```bash
git add ABridge/Providers/Vision/VisionBarcodeSerialization.swift \
  ABridgeTests/VisionBarcodeSerializationTests.swift
git commit -m "feat(vision): add exhaustive barcode serialization for detect_barcodes"
```

---

### Task 4: VisionStore + LiveVisionStore

**Files:**
- Modify: `ABridge/Providers/Vision/VisionStore.swift`
- Modify: `ABridge/Providers/Vision/LiveVisionStore.swift`
- Modify: `ABridgeTests/MockVisionStore.swift`

- [ ] **Step 1: Define request type and extend protocol**

```swift
struct VisionDetectBarcodesRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: DetectBarcodesRequest.Revision?
    let regionOfInterest: NormalizedRect?
    let symbologies: [BarcodeSymbology]?
    let coalesceCompositeSymbologies: Bool?
}

@MainActor
protocol VisionStoreing {
    // existing methods …
    func detectBarcodes(request: VisionDetectBarcodesRequest) throws -> [BarcodeObservation]
}
```

- [ ] **Step 2: Implement LiveVisionStore.detectBarcodes**

Decode image via existing `imageSource` helper. Build `ImageRequestHandler(request.imageData, orientation:)`. Construct `DetectBarcodesRequest(request.revision)`, apply optional `regionOfInterest`, `symbologies`, `coalesceCompositeSymbologies`. Call `performVisionAsync` + `handler.perform(request)` (same bridge as `recognizeDocuments`).

- [ ] **Step 3: Extend MockVisionStore**

Hold canned `[BarcodeObservation]`; record `lastDetectBarcodesRequest`.

- [ ] **Step 4: Commit**

```bash
git add ABridge/Providers/Vision/VisionStore.swift \
  ABridge/Providers/Vision/LiveVisionStore.swift \
  ABridgeTests/MockVisionStore.swift
git commit -m "feat(vision): add VisionStore detect_barcodes seam"
```

---

### Task 5: VisionProvider detect_barcodes operation

**Files:**
- Create: `ABridge/Providers/Vision/VisionProviderDetectBarcodes.swift`
- Modify: `ABridge/Providers/Vision/VisionProviderRouting.swift`
- Create: `ABridgeTests/VisionProviderDetectBarcodesTests.swift`
- Modify: `ABridgeTests/AppleProviderBridgeVisionTests.swift`

- [ ] **Step 1: Write failing provider tests**

Cases:
- Missing `image_data` → `invalid_arguments`
- Invalid base64 → `invalid_arguments`
- Mock store returns observations → success JSON with `results` array
- Optional `symbologies` / `region_of_interest` forwarded to store

- [ ] **Step 2: Implement detect_barcodes handler**

Mirror `VisionProviderRecognizeText` / `VisionProviderRecognizeDocuments` argument parsing:
- Parse base64 `image_data`
- Map optional `orientation`, `revision`, `region_of_interest`, `symbologies`, `coalesce_composite_symbologies`
- Decode `symbologies` strings to `[BarcodeSymbology]` via `BarcodeSymbology(rawValue:)` or SDK-appropriate initializer
- Call store; serialize via `VisionBarcodeSerialization.detectBarcodesResponseJSONObject`

- [ ] **Step 3: Add routing**

```swift
extension VisionProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "recognize_text":
            recognizeText(payloadJson: payloadJson)
        case "recognize_documents":
            recognizeDocuments(payloadJson: payloadJson)
        case "detect_barcodes":
            detectBarcodes(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown vision operation: \(operation)")
        }
    }
}
```

- [ ] **Step 4: Update AppleProviderBridgeVisionTests** — inject mock provider returning success for `detect_barcodes`.

- [ ] **Step 5: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add ABridge/Providers/Vision/VisionProviderDetectBarcodes.swift \
  ABridge/Providers/Vision/VisionProviderRouting.swift \
  ABridgeTests/VisionProviderDetectBarcodesTests.swift \
  ABridgeTests/AppleProviderBridgeVisionTests.swift
git commit -m "feat(vision): implement detect_barcodes provider operation"
```

---

### Task 6: Ship capability + README

**Files:**
- Modify: `ABridge/Models/CapabilityCatalog.swift`
- Modify: `README.md`
- Modify: `ABridgeTests/AppSettingsVisionTests.swift`

- [ ] **Step 1: Flip capability shipped**

```swift
CapabilityDefinition(id: "vision-barcodes", capabilityID: "vision.barcodes", label: "Barcodes", shipped: true),
```

- [ ] **Step 2: Update AppSettingsVisionTests**

When `vision-barcodes` toggled on, `serverEnabledMCPCapabilityIDs` includes `vision.barcodes` (no authorization gate).

- [ ] **Step 3: README checkoff**

```markdown
- [x] `vision_detect_barcodes`
```

- [ ] **Step 4: Regenerate Xcode project if new Swift files added**

Run: `xcodegen generate` (if `project.yml` source globs do not auto-pickup)

- [ ] **Step 5: Run full verification**

Run: `TZ=UTC just test-all`  
Expected: PASS

Run: `TZ=UTC just ci`  
Expected: PASS (before merge)

- [ ] **Step 6: Commit**

```bash
git add ABridge/Models/CapabilityCatalog.swift README.md \
  ABridgeTests/AppSettingsVisionTests.swift project.yml
git commit -m "feat(vision): ship vision.barcodes capability for detect_barcodes"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `VISION_BARCODES` + `TOOL_DETECT_BARCODES` Rust registration | Task 1 |
| Input schema (`image_data` + optional DetectBarcodesRequest fields) | Task 1 |
| MCP integration tests | Task 2 |
| `DetectBarcodesRequest` via VisionStore + async bridge | Task 4 |
| Exhaustive `BarcodeObservation` JSON | Task 3 |
| Reuse `VisionDocumentObservationSerialization` barcode projection | Task 3 |
| No Apple permission gate | Task 5 |
| `vision-barcodes` shipped | Task 6 |
| `just test-all` | Task 6 |