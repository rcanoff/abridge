# vision.read_qr_code Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vision.read_qr_code` MCP tool (#116) with exhaustive `VNBarcodeObservation` JSON projection.

**Architecture:** Extend `VisionStore` + `VisionSerialization` from #114; `VNDetectBarcodesRequest` via sync `VNImageRequestHandler` (same pattern as `recognize_text`); Rust tool registration with `vision.barcodes` capability; flip `vision-barcodes` to shipped; no Apple TCC gate per #151.

**Tech Stack:** Rust (`apple_bridge_core`), Swift 6 + Vision + CoreGraphics, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-vision-read-qr-code-design.md`

**Prerequisite:** #114 (`vision.recognize_text`) merged on `main`.

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/capabilities.rs` | `VISION_BARCODES` constant |
| `rust/apple_bridge_core/src/tools/mod.rs` | Tool registration + input schema |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `AppleBridge/Providers/Vision/VisionSerialization.swift` | `VNBarcodeObservation` JSON |
| `AppleBridge/Providers/Vision/VisionStore.swift` | Read-QR protocol seam |
| `AppleBridge/Providers/Vision/LiveVisionStore.swift` | `VNDetectBarcodesRequest` sync wrapper |
| `AppleBridge/Providers/Vision/VisionProvider.swift` | Provider shell + error helpers (unchanged) |
| `AppleBridge/Providers/Vision/VisionProviderRouting.swift` | Operation dispatch |
| `AppleBridge/Providers/Vision/VisionProviderReadQrCode.swift` | `read_qr_code` handler |
| `AppleBridgeTests/MockVisionStore.swift` | Deterministic QR barcode results |
| `AppleBridgeTests/VisionSerializationTests.swift` | Fidelity assertions |
| `AppleBridgeTests/VisionProviderReadQrCodeTests.swift` | Provider tests |
| `AppleBridge/Models/CapabilityCatalog.swift` | Ship `vision-barcodes` |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/apple_bridge_core/src/capabilities.rs`
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`
- Test: `rust/apple_bridge_core/tests/mcp_protocol.rs` (Task 2)

- [ ] **Step 1: Add `VISION_BARCODES` to capabilities.rs**

```rust
pub const VISION_BARCODES: &str = "vision.barcodes";
```

Add to `is_allowed_in_v1` match arm and test:

```rust
#[test]
fn accepts_vision_barcodes_capability_shape() {
  assert!(is_valid_capability_id(VISION_BARCODES));
  assert!(is_allowed_in_v1(VISION_BARCODES));
}
```

- [ ] **Step 2: Register tool in tools/mod.rs**

```rust
pub const TOOL_READ_QR_CODE: &str = "vision.read_qr_code";
```

Add to `ALL_TOOLS` (bump array length 54 → 55):

```rust
ToolDefinition {
  name: TOOL_READ_QR_CODE,
  capability: capabilities::VISION_BARCODES,
  provider: "vision",
  operation: "read_qr_code",
  description: "Read QR codes in a client-provided image using Vision framework barcode detection",
},
```

- [ ] **Step 3: Add input schema**

```rust
TOOL_READ_QR_CODE => serde_json::json!({
  "type": "object",
  "properties": {
    "image_data": { "type": "string", "minLength": 1 },
    "orientation": { "type": "integer", "minimum": 1, "maximum": 8 },
    "revision": { "type": "integer" },
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
    "coalesce_composite_symbologies": { "type": "boolean" }
  },
  "required": ["image_data"]
}),
```

- [ ] **Step 4: Add unit tests in tools/mod.rs tests module**

```rust
#[test]
fn lists_read_qr_code_tool_when_vision_barcodes_capability_enabled() {
  let tools = tools_for_capabilities(&["vision.barcodes".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_READ_QR_CODE]);
}

#[test]
fn read_qr_code_schema_requires_image_data() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_READ_QR_CODE)
    .expect("read_qr_code tool");
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
git add rust/apple_bridge_core/src/capabilities.rs rust/apple_bridge_core/src/tools/mod.rs
git commit -m "feat(vision): register vision.read_qr_code MCP tool in Rust"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Reuse `vision_config_on_port` helper** from #114 (add `vision.barcodes` variant or parameterize capability list — helper already accepts `enabled_capabilities: Vec<String>`).

- [ ] **Step 2: Write integration tests**

```rust
#[test]
fn mcp_tools_list_includes_read_qr_code_when_vision_barcodes_enabled() {
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
  assert!(resp.contains("vision.read_qr_code"));
}

#[test]
fn tools_call_dispatches_read_qr_code() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"vision.read_qr_code","arguments":{"image_data":"aGVsbG8="}}}"#;

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
  assert_eq!(recorded.operation, "read_qr_code");
  assert!(recorded.payload_json.contains("image_data"));
}
```

- [ ] **Step 3: Run tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add rust/apple_bridge_core/tests/mcp_protocol.rs
git commit -m "test(vision): add MCP integration tests for read_qr_code"
```

---

### Task 3: VisionSerialization (exhaustive VNBarcodeObservation)

**Files:**
- Modify: `AppleBridge/Providers/Vision/VisionSerialization.swift`
- Modify: `AppleBridgeTests/VisionSerializationTests.swift`

- [ ] **Step 1: Write failing serialization test**

Assert every top-level observation key from spec: `uuid`, `confidence`, `time_range`, `request_revision`, `bounding_box`, `global_segmentation_mask`, `top_left`, `top_right`, `bottom_left`, `bottom_right`, `symbology`, `payload_string_value`, `payload_data`.

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-swift`  
Expected: FAIL — `barcodeObservationJSONObject` not defined

- [ ] **Step 3: Implement serialization helpers in VisionSerialization.swift**

```swift
static func readQrCodeResponseJSONObject(observations: [VNBarcodeObservation]) -> [String: Any] {
    [
        "results": observations.map(barcodeObservationJSONObject(from:)),
    ]
}

static func barcodeObservationJSONObject(from observation: VNBarcodeObservation) -> [String: Any] {
    [
        "uuid": observation.uuid.uuidString,
        "confidence": observation.confidence,
        "time_range": cmTimeRangeJSONObject(from: observation.timeRange),
        "request_revision": observation.requestRevision,
        "bounding_box": cgRectJSONObject(from: observation.boundingBox),
        "global_segmentation_mask": pixelBufferObservationJSONObject(from: observation.globalSegmentationMask),
        "top_left": cgPointJSONObject(from: observation.topLeft),
        "top_right": cgPointJSONObject(from: observation.topRight),
        "bottom_left": cgPointJSONObject(from: observation.bottomLeft),
        "bottom_right": cgPointJSONObject(from: observation.bottomRight),
        "symbology": String(describing: observation.symbology),
        "payload_string_value": jsonValue(observation.payloadStringValue),
        "payload_data": observation.payloadData?.base64EncodedString() ?? NSNull(),
    ]
}
```

Reuse existing `cmTimeRangeJSONObject`, `cgRectJSONObject`, `cgPointJSONObject`, `pixelBufferObservationJSONObject`, `jsonValue` helpers from #114.

- [ ] **Step 4: Run tests**

Run: `just test-swift`  
Expected: PASS for VisionSerializationTests

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Providers/Vision/VisionSerialization.swift AppleBridgeTests/VisionSerializationTests.swift
git commit -m "feat(vision): add exhaustive VNBarcodeObservation serialization"
```

---

### Task 4: VisionStore + LiveVisionStore

**Files:**
- Modify: `AppleBridge/Providers/Vision/VisionStore.swift`
- Modify: `AppleBridge/Providers/Vision/LiveVisionStore.swift`
- Modify: `AppleBridgeTests/MockVisionStore.swift`

- [ ] **Step 1: Define protocol request type**

```swift
struct VisionReadQrCodeRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: Int?
    let regionOfInterest: CGRect?
    let coalesceCompositeSymbologies: Bool?
}

protocol VisionStoreing {
    // existing methods …
    func readQrCode(request: VisionReadQrCodeRequest) throws -> [VNBarcodeObservation]
}
```

- [ ] **Step 2: Implement LiveVisionStore.readQrCode**

Mirror `recognizeText` image decode path. Build `VNDetectBarcodesRequest`:

```swift
let detectRequest = VNDetectBarcodesRequest()
detectRequest.symbologies = [.qr]
if let revision = request.revision { detectRequest.revision = revision }
if let regionOfInterest = request.regionOfInterest {
    detectRequest.regionOfInterest = regionOfInterest
}
if let coalesce = request.coalesceCompositeSymbologies {
    detectRequest.coalesceCompositeSymbologies = coalesce
}
```

`VNImageRequestHandler(cgImage:orientation:options:).perform([detectRequest])` synchronously; return `detectRequest.results ?? []`.

- [ ] **Step 3: Implement MockVisionStore**

Hold canned `[VNBarcodeObservation]` (synthesized via test fixtures). Record `lastReadQrCodeRequest`.

- [ ] **Step 4: Commit**

```bash
git add AppleBridge/Providers/Vision/VisionStore.swift \
  AppleBridge/Providers/Vision/LiveVisionStore.swift \
  AppleBridgeTests/MockVisionStore.swift
git commit -m "feat(vision): add VisionStore read_qr_code seam"
```

---

### Task 5: VisionProvider read_qr_code operation

**Files:**
- Create: `AppleBridge/Providers/Vision/VisionProviderReadQrCode.swift`
- Modify: `AppleBridge/Providers/Vision/VisionProviderRouting.swift`
- Create: `AppleBridgeTests/VisionProviderReadQrCodeTests.swift`
- Modify: `AppleBridgeTests/AppleProviderBridgeVisionTests.swift`

- [ ] **Step 1: Write failing provider tests**

Cases (mirror `VisionProviderRecognizeTextTests`):
- Missing `image_data` → `invalid_arguments`
- Invalid base64 → `invalid_arguments`
- Mock store returns observations → success JSON with `results` array containing `symbology` and `payload_string_value`
- `region_of_interest` forwarded to store

- [ ] **Step 2: Implement read_qr_code handler**

Copy argument-parsing helpers from `VisionProviderRecognizeText.swift` (`requiredImageDataArgument`, `optionalOrientationArgument`, `optionalRegionOfInterestArgument`, `optionalIntArgument`, `optionalBoolArgument`). Parse into `VisionReadQrCodeRequest`; call store; serialize via `VisionSerialization.readQrCodeResponseJSONObject`.

- [ ] **Step 3: Add routing**

```swift
extension VisionProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "recognize_text":
            recognizeText(payloadJson: payloadJson)
        case "scan_document":
            scanDocument(payloadJson: payloadJson)
        case "read_qr_code":
            readQrCode(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown vision operation: \(operation)")
        }
    }
}
```

- [ ] **Step 4: Update AppleProviderBridgeVisionTests** — inject mock provider returning success for `read_qr_code`.

- [ ] **Step 5: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add AppleBridge/Providers/Vision/VisionProviderReadQrCode.swift \
  AppleBridge/Providers/Vision/VisionProviderRouting.swift \
  AppleBridgeTests/VisionProviderReadQrCodeTests.swift \
  AppleBridgeTests/AppleProviderBridgeVisionTests.swift
git commit -m "feat(vision): implement read_qr_code provider operation"
```

---

### Task 6: Ship capability + README

**Files:**
- Modify: `AppleBridge/Models/CapabilityCatalog.swift`
- Modify: `README.md`
- Modify: `AppleBridgeTests/AppSettingsVisionTests.swift`

- [ ] **Step 1: Flip capability shipped**

```swift
CapabilityDefinition(
    id: "vision-barcodes",
    capabilityID: "vision.barcodes",
    label: "Barcodes",
    shipped: true
),
```

- [ ] **Step 2: Update AppSettingsVisionTests** — when `vision-barcodes` toggled on, `serverEnabledMCPCapabilityIDs` includes `vision.barcodes` (no authorization gate).

- [ ] **Step 3: README checkoff**

```markdown
- [x] `vision.read_qr_code`
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
git add AppleBridge/Models/CapabilityCatalog.swift README.md AppleBridgeTests/AppSettingsVisionTests.swift project.yml
git commit -m "feat(vision): ship vision.barcodes capability for read_qr_code"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `VISION_BARCODES` + `TOOL_READ_QR_CODE` Rust registration | Task 1 |
| Input schema (`image_data` + optional Vision request fields) | Task 1 |
| MCP integration tests | Task 2 |
| `VNDetectBarcodesRequest` via VisionStore (symbologies fixed to `.qr`) | Task 4 |
| Exhaustive `VNBarcodeObservation` JSON | Task 3 |
| No Apple permission gate | Task 5 |
| `vision-barcodes` shipped | Task 6 |
| `just test-all` | Task 6 |