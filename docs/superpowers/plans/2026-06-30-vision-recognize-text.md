# vision.recognize_text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vision.recognize_text` MCP tool (#114) with exhaustive `VNRecognizedTextObservation` JSON projection.

**Architecture:** `VisionStore` protocol seam; `VisionSerialization` for faithful Vision JSON; Rust tool registration with `vision.text` capability; flip `vision-text` to shipped; no Apple TCC gate per #151.

**Tech Stack:** Rust (`apple_bridge_core`), Swift 6 + Vision + CoreGraphics, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-vision-recognize-text-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/capabilities.rs` | `VISION_TEXT` constant |
| `rust/apple_bridge_core/src/tools/mod.rs` | Tool registration + input schema |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `AppleBridge/Providers/Vision/VisionSerialization.swift` | Observation / geometry / pixel buffer JSON |
| `AppleBridge/Providers/Vision/VisionStore.swift` | Recognize-text protocol seam |
| `AppleBridge/Providers/Vision/LiveVisionStore.swift` | `VNImageRequestHandler` sync wrapper |
| `AppleBridge/Providers/Vision/VisionProvider.swift` | Provider shell + error helpers |
| `AppleBridge/Providers/Vision/VisionProviderRouting.swift` | Operation dispatch |
| `AppleBridge/Providers/Vision/VisionProviderRecognizeText.swift` | `recognize_text` handler |
| `AppleBridgeTests/MockVisionStore.swift` | Deterministic OCR results |
| `AppleBridgeTests/VisionSerializationTests.swift` | Fidelity assertions |
| `AppleBridgeTests/VisionProviderRecognizeTextTests.swift` | Provider tests |
| `AppleBridge/Models/CapabilityCatalog.swift` | Ship `vision-text` |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/apple_bridge_core/src/capabilities.rs`
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`
- Test: `rust/apple_bridge_core/tests/mcp_protocol.rs` (Task 2)

- [ ] **Step 1: Add `VISION_TEXT` to capabilities.rs**

```rust
pub const VISION_TEXT: &str = "vision.text";
```

Add to `is_allowed_in_v1` match arm and add test:

```rust
#[test]
fn accepts_vision_text_capability_shape() {
  assert!(is_valid_capability_id(VISION_TEXT));
  assert!(is_allowed_in_v1(VISION_TEXT));
}
```

- [ ] **Step 2: Register tool in tools/mod.rs**

```rust
pub const TOOL_RECOGNIZE_TEXT: &str = "vision.recognize_text";
```

Add to `ALL_TOOLS` (bump array length 52 → 53):

```rust
ToolDefinition {
  name: TOOL_RECOGNIZE_TEXT,
  capability: capabilities::VISION_TEXT,
  provider: "vision",
  operation: "recognize_text",
  description: "Recognize text in a client-provided image using Vision framework OCR",
},
```

- [ ] **Step 3: Add input schema**

```rust
TOOL_RECOGNIZE_TEXT => serde_json::json!({
  "type": "object",
  "properties": {
    "image_data": { "type": "string", "minLength": 1 },
    "orientation": { "type": "integer", "minimum": 1, "maximum": 8 },
    "recognition_languages": {
      "type": "array",
      "items": { "type": "string" }
    },
    "custom_words": {
      "type": "array",
      "items": { "type": "string" }
    },
    "recognition_level": {
      "type": "string",
      "enum": ["accurate", "fast"]
    },
    "uses_language_correction": { "type": "boolean" },
    "automatically_detects_language": { "type": "boolean" },
    "minimum_text_height": { "type": "number", "minimum": 0 },
    "revision": { "type": "integer" },
    "prefer_background_processing": { "type": "boolean" },
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
    "max_candidate_count": { "type": "integer", "minimum": 1, "maximum": 10 }
  },
  "required": ["image_data"]
}),
```

- [ ] **Step 4: Add unit tests in tools/mod.rs tests module**

```rust
#[test]
fn lists_recognize_text_tool_when_vision_text_capability_enabled() {
  let tools = tools_for_capabilities(&["vision.text".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_RECOGNIZE_TEXT]);
}

#[test]
fn recognize_text_schema_requires_image_data() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_RECOGNIZE_TEXT)
    .expect("recognize_text tool");
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
git commit -m "feat(vision): register vision.recognize_text MCP tool in Rust"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Add vision config helper** (mirror `mapkit_config_on_port`)

```rust
fn vision_config_on_port(port: u16, enabled_capabilities: Vec<String>) -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port,
    bearer_token: TEST_TOKEN.into(),
    enabled_capabilities,
  }
}
```

- [ ] **Step 2: Write integration tests**

```rust
#[test]
fn mcp_tools_list_includes_recognize_text_when_vision_text_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    vision_config_on_port(port, vec!["vision.text".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("vision.recognize_text"));
}

#[test]
fn tools_call_dispatches_recognize_text() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"vision.recognize_text","arguments":{"image_data":"aGVsbG8="}}}"#;

  let handle = create_server(
    vision_config_on_port(port, vec!["vision.text".into()]),
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
  assert_eq!(recorded.operation, "recognize_text");
  assert!(recorded.payload_json.contains("image_data"));
}
```

- [ ] **Step 3: Run tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add rust/apple_bridge_core/tests/mcp_protocol.rs
git commit -m "test(vision): add MCP integration tests for recognize_text"
```

---

### Task 3: VisionSerialization (exhaustive VNRecognizedTextObservation)

**Files:**
- Create: `AppleBridge/Providers/Vision/VisionSerialization.swift`
- Create: `AppleBridgeTests/VisionSerializationTests.swift`

- [ ] **Step 1: Write failing serialization test**

Assert every top-level observation key from spec: `uuid`, `confidence`, `time_range`, `request_revision`, `bounding_box`, `global_segmentation_mask`, `top_left`, `top_right`, `bottom_left`, `bottom_right`, `candidates`. Assert each `candidates[]` element includes `string`, `confidence`, `request_revision`.

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-swift`  
Expected: FAIL — `VisionSerialization` not defined

- [ ] **Step 3: Implement VisionSerialization.swift**

Helpers:
- `jsonString(from:)`
- `recognizeTextResponseJSONObject(observations:maxCandidateCount:)`
- `recognizedTextObservationJSONObject(from:maxCandidateCount:)`
- `recognizedTextJSONObject(from:)`
- `cgRectJSONObject`, `cgPointJSONObject`, `cmTimeRangeJSONObject`
- `pixelBufferObservationJSONObject(from:)` (for non-nil `global_segmentation_mask`)
- `NSNull()` for nil optionals — all keys always present

- [ ] **Step 4: Run tests**

Run: `just test-swift`  
Expected: PASS for VisionSerializationTests

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Providers/Vision/VisionSerialization.swift AppleBridgeTests/VisionSerializationTests.swift
git commit -m "feat(vision): add exhaustive Vision serialization"
```

---

### Task 4: VisionStore + LiveVisionStore

**Files:**
- Create: `AppleBridge/Providers/Vision/VisionStore.swift`
- Create: `AppleBridge/Providers/Vision/LiveVisionStore.swift`
- Create: `AppleBridgeTests/MockVisionStore.swift`

- [ ] **Step 1: Define protocol and request type**

```swift
import Vision

struct VisionRecognizeTextRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let recognitionLanguages: [String]?
    let customWords: [String]?
    let recognitionLevel: VNRequestTextRecognitionLevel
    let usesLanguageCorrection: Bool?
    let automaticallyDetectsLanguage: Bool?
    let minimumTextHeight: Float?
    let revision: UInt?
    let preferBackgroundProcessing: Bool?
    let regionOfInterest: CGRect?
    let maxCandidateCount: Int
}

protocol VisionStoreing: Sendable {
    func recognizeText(request: VisionRecognizeTextRequest) throws -> [VNRecognizedTextObservation]
}
```

- [ ] **Step 2: Implement LiveVisionStore**

Decode `Data` → `CGImage` via `CGImageSource` or `UIImage` equivalent on macOS (`NSImage`/`CGImage`). Build `VNRecognizeTextRequest`, apply optional properties, create `VNImageRequestHandler(cgImage:orientation:options:)`, call `perform([request])` synchronously, return `request.results ?? []`.

- [ ] **Step 3: Implement MockVisionStore**

Hold canned `[VNRecognizedTextObservation]` (synthesized via `VNRecognizedTextObservation` rectangle helpers + `VNRecognizedText` if needed, or pre-built fixtures). Record `lastRequest`.

- [ ] **Step 4: Commit**

```bash
git add AppleBridge/Providers/Vision/VisionStore.swift \
  AppleBridge/Providers/Vision/LiveVisionStore.swift \
  AppleBridgeTests/MockVisionStore.swift
git commit -m "feat(vision): add VisionStore recognize_text seam"
```

---

### Task 5: VisionProvider recognize_text operation

**Files:**
- Modify: `AppleBridge/Providers/Vision/VisionProvider.swift`
- Create: `AppleBridge/Providers/Vision/VisionProviderRouting.swift`
- Create: `AppleBridge/Providers/Vision/VisionProviderRecognizeText.swift`
- Create: `AppleBridgeTests/VisionProviderRecognizeTextTests.swift`
- Modify: `AppleBridgeTests/AppleProviderBridgeVisionTests.swift`

- [ ] **Step 1: Write failing provider tests**

Cases:
- Missing `image_data` → `invalid_arguments`
- Invalid base64 → `invalid_arguments`
- Mock store returns observations → success JSON with `results` array
- `max_candidate_count` forwarded to serialization

- [ ] **Step 2: Refactor VisionProvider**

```swift
enum VisionProviderError: Error, Equatable {
    case serializationFailed
    case visionError(String)
    case invalidArguments(String)
}

@MainActor
struct VisionProvider {
    let store: any VisionStoreing

    init(store: any VisionStoreing = LiveVisionStore()) {
        self.store = store
    }
}
```

- [ ] **Step 3: Implement recognize_text handler**

Parse base64 `image_data`; map optional request fields to `VisionRecognizeTextRequest`; call store; serialize via `VisionSerialization.recognizeTextResponseJSONObject`.

- [ ] **Step 4: Add routing**

```swift
extension VisionProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "recognize_text":
            recognizeText(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown vision operation: \(operation)")
        }
    }
}
```

Update `LiveVisionEnvironment.sharedProvider` to use store-backed provider.

- [ ] **Step 5: Update AppleProviderBridgeVisionTests** — inject mock provider returning success for `recognize_text`.

- [ ] **Step 6: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add AppleBridge/Providers/Vision/ AppleBridgeTests/VisionProviderRecognizeTextTests.swift \
  AppleBridgeTests/AppleProviderBridgeVisionTests.swift
git commit -m "feat(vision): implement recognize_text provider operation"
```

---

### Task 6: Ship capability + README

**Files:**
- Modify: `AppleBridge/Models/CapabilityCatalog.swift`
- Modify: `README.md`
- Modify: `AppleBridgeTests/AppSettingsVisionTests.swift`

- [ ] **Step 1: Flip capability shipped**

```swift
CapabilityDefinition(id: "vision-text", capabilityID: "vision.text", label: "Text", shipped: true),
```

- [ ] **Step 2: Update AppSettingsVisionTests** — when `vision-text` toggled on, `serverEnabledMCPCapabilityIDs` includes `vision.text` (no authorization gate).

- [ ] **Step 3: README checkoff**

```markdown
- [x] `vision.recognize_text`
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
git commit -m "feat(vision): ship vision.text capability for recognize_text"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `VISION_TEXT` + `TOOL_RECOGNIZE_TEXT` Rust registration | Task 1 |
| Input schema (`image_data` + optional Vision request fields) | Task 1 |
| MCP integration tests | Task 2 |
| `VNRecognizeTextRequest` via VisionStore | Task 4 |
| Exhaustive `VNRecognizedTextObservation` JSON | Task 3 |
| No Apple permission gate | Task 5 |
| `vision-text` shipped | Task 6 |
| `just test-all` | Task 6 |