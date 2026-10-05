# vision.detect_faces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `vision.detect_faces` MCP tool (#118) with exhaustive `VNFaceObservation` JSON projection (bounding boxes + facial landmarks).

**Architecture:** Extend `VisionStore` + `VisionSerialization` from #114; `VNDetectFaceLandmarksRequest` via sync `VNImageRequestHandler` (same pattern as `recognize_text`); Rust tool registration with `vision.faces` capability; flip `vision-faces` to shipped; no Apple TCC gate per #151.

**Tech Stack:** Rust (`abridge_core`), Swift 6 + Vision + CoreGraphics, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-vision-detect-faces-design.md`

**Prerequisite:** #114 (`vision.recognize_text`) merged on `main`.

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/abridge_core/src/capabilities.rs` | `VISION_FACES` constant |
| `rust/abridge_core/src/tools/mod.rs` | Tool registration + input schema |
| `rust/abridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `ABridge/Providers/Vision/VisionFaceSerialization.swift` | `VNFaceObservation` / landmark JSON |
| `ABridge/Providers/Vision/VisionSerialization.swift` | `detectFacesResponseJSONObject` wrapper |
| `ABridge/Providers/Vision/VisionStore.swift` | Detect-faces protocol seam |
| `ABridge/Providers/Vision/LiveVisionStore.swift` | `VNDetectFaceLandmarksRequest` sync wrapper |
| `ABridge/Providers/Vision/VisionProviderDetectFaces.swift` | `detect_faces` handler |
| `ABridge/Providers/Vision/VisionProviderRouting.swift` | Operation dispatch |
| `ABridgeTests/MockVisionStore.swift` | Deterministic face results |
| `ABridgeTests/VisionFaceSerializationTests.swift` | Fidelity assertions |
| `ABridgeTests/VisionProviderDetectFacesTests.swift` | Provider tests |
| `ABridge/Models/CapabilityCatalog.swift` | Ship `vision-faces` |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/abridge_core/src/capabilities.rs`
- Modify: `rust/abridge_core/src/tools/mod.rs`
- Test: `rust/abridge_core/tests/mcp_protocol.rs` (Task 2)

- [ ] **Step 1: Add `VISION_FACES` to capabilities.rs**

```rust
pub const VISION_FACES: &str = "vision.faces";
```

Add to `is_valid_capability_id` early-return arm, `is_allowed_in_v1` match arm, and test:

```rust
#[test]
fn accepts_vision_faces_capability_shape() {
  assert!(is_valid_capability_id(VISION_FACES));
  assert!(is_allowed_in_v1(VISION_FACES));
}
```

- [ ] **Step 2: Register tool in tools/mod.rs**

```rust
pub const TOOL_DETECT_FACES: &str = "vision.detect_faces";
```

Add to `ALL_TOOLS` (bump array length 54 → 55):

```rust
ToolDefinition {
  name: TOOL_DETECT_FACES,
  capability: capabilities::VISION_FACES,
  provider: "vision",
  operation: "detect_faces",
  description: "Detect faces and facial landmarks in a client-provided image using Vision framework",
},
```

- [ ] **Step 3: Add input schema**

```rust
TOOL_DETECT_FACES => serde_json::json!({
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
    "constellation": {
      "type": "string",
      "enum": ["not_defined", "65_points", "76_points"]
    }
  },
  "required": ["image_data"]
}),
```

- [ ] **Step 4: Add unit tests in tools/mod.rs tests module**

```rust
#[test]
fn lists_detect_faces_tool_when_vision_faces_capability_enabled() {
  let tools = tools_for_capabilities(&["vision.faces".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_DETECT_FACES]);
}

#[test]
fn detect_faces_schema_requires_image_data() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_DETECT_FACES)
    .expect("detect_faces tool");
  let schema = input_schema(tool);
  assert_eq!(string_property_min_length(&schema, "image_data"), Some(1));
  assert_eq!(
    schema.get("required").and_then(|v| v.as_array()).map(|fields| {
      fields.iter().filter_map(|f| f.as_str().map(str::to_owned)).collect::<Vec<_>>()
    }),
    Some(vec!["image_data".to_string()])
  );
}
```

- [ ] **Step 5: Run Rust unit tests**

Run: `just test-rust`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/abridge_core/src/capabilities.rs rust/abridge_core/src/tools/mod.rs
git commit -m "feat(vision): register detect_faces tool and vision.faces capability"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/abridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Write failing integration tests**

```rust
#[test]
fn mcp_tools_list_includes_detect_faces_when_vision_faces_enabled() {
  // mirror scan_document / recognize_text pattern
  assert!(resp.contains("vision.detect_faces"));
}

#[test]
fn tools_call_dispatches_detect_faces() {
  let body = r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"vision.detect_faces","arguments":{"image_data":"aGVsbG8="}}}"#;
  // assert recorded.operation == "detect_faces"
}
```

- [ ] **Step 2: Run tests**

Run: `just test-rust`  
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add rust/abridge_core/tests/mcp_protocol.rs
git commit -m "test(vision): add MCP integration tests for detect_faces"
```

---

### Task 3: Face observation serialization

**Files:**
- Create: `ABridge/Providers/Vision/VisionFaceSerialization.swift`
- Modify: `ABridge/Providers/Vision/VisionSerialization.swift`
- Create: `ABridgeTests/VisionFaceSerializationTests.swift`

- [ ] **Step 1: Write failing serialization tests**

Assert every `VNFaceObservation` key from spec is present on serialized object. Assert nested `landmarks` region keys (`all_points`, `left_eye`, …) and `VNFaceLandmarkRegion2D` keys (`point_count`, `normalized_points`, `precision_estimates_per_point`, `points_classification`, `request_revision`).

- [ ] **Step 2: Implement VisionFaceSerialization**

```swift
enum VisionFaceSerialization {
    static func detectFacesResponseJSONObject(observations: [VNFaceObservation]) -> [String: Any] {
        ["results": observations.map(faceObservationJSONObject(from:))]
    }

    static func faceObservationJSONObject(from observation: VNFaceObservation) -> [String: Any] {
        [
            "uuid": observation.uuid.uuidString,
            "confidence": observation.confidence,
            "time_range": VisionSerialization.cmTimeRangeJSONObject(from: observation.timeRange),
            "request_revision": observation.requestRevision,
            "bounding_box": VisionSerialization.cgRectJSONObject(from: observation.boundingBox),
            "global_segmentation_mask": VisionSerialization.pixelBufferObservationJSONObject(
                from: observation.globalSegmentationMask
            ),
            "roll": VisionSerialization.jsonValue(observation.roll),
            "yaw": VisionSerialization.jsonValue(observation.yaw),
            "pitch": VisionSerialization.jsonValue(observation.pitch),
            "face_capture_quality": VisionSerialization.jsonValue(observation.faceCaptureQuality),
            "landmarks": faceLandmarksJSONObject(from: observation.landmarks),
        ]
    }
}
```

Implement `faceLandmarksJSONObject` and `faceLandmarkRegionJSONObject` projecting all region properties. Serialize `normalizedPoints` buffer as `[{x,y}, …]` with length `pointCount`. Map `VNPointsClassification` → `disconnected` / `open_path` / `closed_path`.

- [ ] **Step 3: Add wrapper to VisionSerialization**

```swift
static func detectFacesResponseJSONObject(observations: [VNFaceObservation]) -> [String: Any] {
    VisionFaceSerialization.detectFacesResponseJSONObject(observations: observations)
}
```

- [ ] **Step 4: Run tests**

Run: `just test-swift`  
Expected: PASS for VisionFaceSerializationTests

- [ ] **Step 5: Commit**

```bash
git add ABridge/Providers/Vision/VisionFaceSerialization.swift \
  ABridge/Providers/Vision/VisionSerialization.swift \
  ABridgeTests/VisionFaceSerializationTests.swift
git commit -m "feat(vision): add exhaustive VNFaceObservation serialization"
```

---

### Task 4: VisionStore + LiveVisionStore

**Files:**
- Modify: `ABridge/Providers/Vision/VisionStore.swift`
- Modify: `ABridge/Providers/Vision/LiveVisionStore.swift`
- Modify: `ABridgeTests/MockVisionStore.swift`
- Modify: `ABridgeTests/VisionTestFixtures.swift`

- [ ] **Step 1: Define protocol request type**

```swift
struct VisionDetectFacesRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: Int?
    let regionOfInterest: CGRect?
    let constellation: VNRequestFaceLandmarksConstellation
}

protocol VisionStoreing {
    // existing methods …
    func detectFaces(request: VisionDetectFacesRequest) throws -> [VNFaceObservation]
}
```

- [ ] **Step 2: Implement LiveVisionStore.detectFaces**

Mirror `recognizeText` image decode path. Build `VNDetectFaceLandmarksRequest`:

```swift
let detectRequest = VNDetectFaceLandmarksRequest()
if let revision = request.revision { detectRequest.revision = revision }
if let regionOfInterest = request.regionOfInterest {
    detectRequest.regionOfInterest = regionOfInterest
}
detectRequest.constellation = request.constellation
```

`VNImageRequestHandler(cgImage:orientation:options:).perform([detectRequest])` synchronously; return `detectRequest.results ?? []`.

- [ ] **Step 3: Implement MockVisionStore + fixtures**

Hold canned `[VNFaceObservation]` (synthesized via `VNFaceObservation.faceObservationWithRequestRevision(_:boundingBox:roll:yaw:pitch:)` where needed). Record `lastDetectFacesRequest`.

- [ ] **Step 4: Commit**

```bash
git add ABridge/Providers/Vision/VisionStore.swift \
  ABridge/Providers/Vision/LiveVisionStore.swift \
  ABridgeTests/MockVisionStore.swift \
  ABridgeTests/VisionTestFixtures.swift
git commit -m "feat(vision): add VisionStore detect_faces seam"
```

---

### Task 5: VisionProvider detect_faces operation

**Files:**
- Create: `ABridge/Providers/Vision/VisionProviderDetectFaces.swift`
- Modify: `ABridge/Providers/Vision/VisionProviderRouting.swift`
- Create: `ABridgeTests/VisionProviderDetectFacesTests.swift`
- Modify: `ABridgeTests/AppleProviderBridgeVisionTests.swift`

- [ ] **Step 1: Write failing provider tests**

Cases (mirror `VisionProviderRecognizeTextTests`):
- Missing `image_data` → `invalid_arguments`
- Invalid base64 → `invalid_arguments`
- Invalid `constellation` enum → `invalid_arguments`
- Mock store returns observations → success JSON with `results` array containing `bounding_box` and `landmarks`
- `region_of_interest` and `constellation` forwarded to store

- [ ] **Step 2: Implement detect_faces handler**

Copy argument-parsing helpers from `VisionProviderRecognizeText.swift`. Add `optionalConstellationArgument` mapping MCP strings to `VNRequestFaceLandmarksConstellation`. Parse into `VisionDetectFacesRequest`; call store; serialize via `VisionSerialization.detectFacesResponseJSONObject`.

- [ ] **Step 3: Add routing**

```swift
case "detect_faces":
    detectFaces(payloadJson: payloadJson)
```

- [ ] **Step 4: Update AppleProviderBridgeVisionTests** — inject mock provider returning success for `detect_faces`.

- [ ] **Step 5: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add ABridge/Providers/Vision/VisionProviderDetectFaces.swift \
  ABridge/Providers/Vision/VisionProviderRouting.swift \
  ABridgeTests/VisionProviderDetectFacesTests.swift \
  ABridgeTests/AppleProviderBridgeVisionTests.swift
git commit -m "feat(vision): implement detect_faces provider operation"
```

---

### Task 6: Ship capability + README

**Files:**
- Modify: `ABridge/Models/CapabilityCatalog.swift`
- Modify: `README.md`
- Modify: `ABridgeTests/AppSettingsVisionTests.swift`

- [ ] **Step 1: Flip capability shipped**

```swift
CapabilityDefinition(
    id: "vision-faces",
    capabilityID: "vision.faces",
    label: "Faces",
    shipped: true
),
```

- [ ] **Step 2: Update AppSettingsVisionTests** — when `vision-faces` toggled on, `serverEnabledMCPCapabilityIDs` includes `vision.faces` (no authorization gate).

- [ ] **Step 3: README checkoff**

```markdown
- [x] `vision.detect_faces`
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
git add ABridge/Models/CapabilityCatalog.swift README.md ABridgeTests/AppSettingsVisionTests.swift project.yml
git commit -m "feat(vision): ship vision.faces capability for detect_faces"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `VISION_FACES` + `TOOL_DETECT_FACES` Rust registration | Task 1 |
| Input schema (`image_data` + optional Vision request fields) | Task 1 |
| MCP integration tests | Task 2 |
| `VNDetectFaceLandmarksRequest` via VisionStore (sync `VNImageRequestHandler`) | Task 4 |
| Exhaustive `VNFaceObservation` + `VNFaceLandmarks2D` JSON | Task 3 |
| No Apple permission gate | Task 5 |
| `vision-faces` shipped | Task 6 |
| `just test-all` | Task 6 |