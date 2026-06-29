# mapkit.reverse_geocode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `mapkit.reverse_geocode` MCP tool (#106) with exhaustive `MKMapItem` JSON projection and ship the `mapkit.geocode` capability.

**Architecture:** Extend `MapKitStore` with `reverseGeocode`; use `MKReverseGeocodingRequest` in `LiveMapKitStore`; reuse `MapKitSerialization` and coordinate parsing from `MapKitProviderSearchArguments`; Rust tool registration with new `mapkit.geocode` capability; flip `mapkit-geocode` to shipped; CoreLocation when-in-use gate per #150.

**Tech Stack:** Rust (`apple_bridge_core`), Swift 6 + MapKit + CoreLocation, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-mapkit-reverse-geocode-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/capabilities.rs` | `MAPKIT_GEOCODE` constant |
| `rust/apple_bridge_core/src/tools/mod.rs` | `TOOL_REVERSE_GEOCODE` registration + input schema |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `AppleBridge/Providers/MapKit/MapKitStore.swift` | `MapKitReverseGeocodeRequest` + protocol method |
| `AppleBridge/Providers/MapKit/LiveMapKitStore.swift` | `MKReverseGeocodingRequest` blocking wrapper |
| `AppleBridge/Providers/MapKit/MapKitSerialization.swift` | `reverseGeocodeResponseJSONObject(mapItems:)` |
| `AppleBridge/Providers/MapKit/MapKitProviderReverseGeocode.swift` | `reverse_geocode` handler |
| `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift` | Operation dispatch |
| `AppleBridgeTests/MockMapKitStore.swift` | Reverse-geocode mock seam |
| `AppleBridgeTests/MapKitProviderReverseGeocodeTests.swift` | Provider tests |
| `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift` | Bridge routing test |
| `AppleBridge/Models/CapabilityCatalog.swift` | Ship `mapkit-geocode` |
| `AppleBridgeTests/PermissionsStoreMapKitTests.swift` | Shipped geocode toggle expectations |
| `AppleBridgeTests/AppSettingsMapKitTests.swift` | Server gating for `mapkit.geocode` |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/apple_bridge_core/src/capabilities.rs`
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`
- Test: `rust/apple_bridge_core/tests/mcp_protocol.rs` (no changes yet)

- [ ] **Step 1: Add `MAPKIT_GEOCODE` to capabilities.rs**

```rust
pub const MAPKIT_GEOCODE: &str = "mapkit.geocode";
```

Add to `is_valid_capability_id` early-return arm and `is_allowed_in_v1` match arm:

```rust
|| id == MAPKIT_GEOCODE
```

```rust
| MAPKIT_GEOCODE
```

Add test:

```rust
#[test]
fn accepts_mapkit_geocode_capability_shape() {
  assert!(is_valid_capability_id(MAPKIT_GEOCODE));
  assert!(is_allowed_in_v1(MAPKIT_GEOCODE));
}
```

Import `MAPKIT_GEOCODE` in the tests module `use super::{ ... }` block.

- [ ] **Step 2: Register tool in tools/mod.rs**

```rust
pub const TOOL_REVERSE_GEOCODE: &str = "mapkit.reverse_geocode";
```

Add to `ALL_TOOLS` (bump array length 45 → 46), after `TOOL_SEARCH_NEARBY`:

```rust
ToolDefinition {
  name: TOOL_REVERSE_GEOCODE,
  capability: capabilities::MAPKIT_GEOCODE,
  provider: "mapkit",
  operation: "reverse_geocode",
  description: "Resolve a coordinate to address representations",
},
```

- [ ] **Step 3: Add input schema**

```rust
TOOL_REVERSE_GEOCODE => serde_json::json!({
  "type": "object",
  "properties": {
    "coordinate": {
      "type": "object",
      "properties": {
        "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
        "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
      },
      "required": ["latitude", "longitude"]
    }
  },
  "required": ["coordinate"]
}),
```

- [ ] **Step 4: Add unit tests in tools/mod.rs tests module**

```rust
#[test]
fn lists_reverse_geocode_tool_when_mapkit_geocode_capability_enabled() {
  let tools = tools_for_capabilities(&["mapkit.geocode".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_REVERSE_GEOCODE]);
}

#[test]
fn reverse_geocode_schema_requires_coordinate() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_REVERSE_GEOCODE)
    .expect("reverse_geocode tool");
  let schema = input_schema(tool);
  assert_eq!(
    schema
      .get("required")
      .and_then(|value| value.as_array())
      .map(|items| items.iter().filter_map(|item| item.as_str()).collect::<Vec<_>>()),
    Some(vec!["coordinate"])
  );
  assert!(schema
    .get("properties")
    .and_then(|p| p.get("coordinate"))
    .is_some());
}
```

- [ ] **Step 5: Run Rust tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/apple_bridge_core/src/capabilities.rs rust/apple_bridge_core/src/tools/mod.rs
git commit -m "feat(mapkit): register mapkit.reverse_geocode MCP tool in Rust"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Write integration tests** (reuse existing `mapkit_config_on_port`)

```rust
#[test]
fn mcp_tools_list_includes_reverse_geocode_when_mapkit_geocode_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":13,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    mapkit_config_on_port(port, vec!["mapkit.geocode".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("mapkit.reverse_geocode"));
}

#[test]
fn tools_call_dispatches_reverse_geocode() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"mapkit.reverse_geocode","arguments":{"coordinate":{"latitude":37.3346,"longitude":-122.0090}}}}"#;

  let handle = create_server(
    mapkit_config_on_port(port, vec!["mapkit.geocode".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains(r#""isError":false"#));
  let recorded = mock.last_request.lock().expect("lock").clone().expect("request");
  assert_eq!(recorded.provider, "mapkit");
  assert_eq!(recorded.operation, "reverse_geocode");
  assert!(recorded.payload_json.contains("37.3346"));
}
```

- [ ] **Step 2: Run tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add rust/apple_bridge_core/tests/mcp_protocol.rs
git commit -m "test(mapkit): add MCP integration tests for reverse_geocode"
```

---

### Task 3: MapKitStore seam + serialization helper

**Files:**
- Modify: `AppleBridge/Providers/MapKit/MapKitStore.swift`
- Modify: `AppleBridge/Providers/MapKit/LiveMapKitStore.swift`
- Modify: `AppleBridge/Providers/MapKit/MapKitSerialization.swift`
- Modify: `AppleBridgeTests/MockMapKitStore.swift`

- [ ] **Step 1: Extend MapKitStore types**

```swift
struct MapKitReverseGeocodeRequest {
    let coordinate: CLLocationCoordinate2D
}

@MainActor
protocol MapKitStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult
    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult
    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem]
}
```

- [ ] **Step 2: Add serialization helper**

```swift
static func reverseGeocodeResponseJSONObject(mapItems: [MKMapItem]) -> [String: Any] {
    [
        "map_items": mapItems.map(mapItemJSONObject(from:)),
    ]
}
```

- [ ] **Step 3: Implement LiveMapKitStore.reverseGeocode**

```swift
func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem] {
    let location = CLLocation(
        latitude: request.coordinate.latitude,
        longitude: request.coordinate.longitude
    )
    guard let mkRequest = MKReverseGeocodingRequest(location: location) else {
        throw MapKitProviderError.mapkitError("MapKit reverse geocode request could not be created")
    }
    var mapItems: [MKMapItem]?
    var geocodeError: Error?

    try MapKitSearchFetch.waitForCompletion { complete in
        Task { @MainActor in
            defer { complete() }
            do {
                mapItems = try await mkRequest.mapItems
            } catch {
                geocodeError = error
            }
        }
    }

    if let geocodeError {
        throw geocodeError
    }
    guard let mapItems else {
        throw MapKitProviderError.mapkitError("MapKit reverse geocode returned no response")
    }
    return mapItems
}
```

- [ ] **Step 4: Extend MockMapKitStore**

```swift
var reverseGeocodeResults: [[MKMapItem]] = []
private(set) var lastReverseGeocodeRequest: MapKitReverseGeocodeRequest?

func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem] {
    lastReverseGeocodeRequest = request
    if let first = reverseGeocodeResults.first {
        return first
    }
    return []
}
```

- [ ] **Step 5: Run Swift tests**

Run: `just test-swift`  
Expected: PASS (existing tests unchanged)

- [ ] **Step 6: Commit**

```bash
git add AppleBridge/Providers/MapKit/MapKitStore.swift \
  AppleBridge/Providers/MapKit/LiveMapKitStore.swift \
  AppleBridge/Providers/MapKit/MapKitSerialization.swift \
  AppleBridgeTests/MockMapKitStore.swift
git commit -m "feat(mapkit): add MapKitStore reverse_geocode seam"
```

---

### Task 4: MapKitProvider reverse_geocode operation

**Files:**
- Create: `AppleBridge/Providers/MapKit/MapKitProviderReverseGeocode.swift`
- Modify: `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift`
- Create: `AppleBridgeTests/MapKitProviderReverseGeocodeTests.swift`
- Modify: `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift`
- Modify: `AppleBridge.xcodeproj/project.pbxproj` (add new Swift files)

- [ ] **Step 1: Write failing provider tests**

```swift
@Suite("MapKitProviderReverseGeocode")
struct MapKitProviderReverseGeocodeTests {
    @Test
    @MainActor
    func reverseGeocodeReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "reverse_geocode",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0}}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func reverseGeocodeRequiresCoordinate() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "reverse_geocode", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func reverseGeocodeReturnsSerializedResponse() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let item = MKMapItem(placemark: placemark)
        item.name = "1 Apple Park Way"
        let store = MockMapKitStore()
        store.reverseGeocodeResults = [[item]]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "reverse_geocode",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0}}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "1 Apple Park Way")
        #expect(store.lastReverseGeocodeRequest?.coordinate.latitude == 37.0)
    }
}
```

- [ ] **Step 2: Implement reverse_geocode handler**

```swift
extension MapKitProvider {
    func reverseGeocode(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

        do {
            let arguments = try parseReverseGeocodeArguments(payloadJson)
            let mapItems = try store.reverseGeocode(request: arguments)
            let payloadObject = MapKitSerialization.reverseGeocodeResponseJSONObject(mapItems: mapItems)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseReverseGeocodeArguments(_ payloadJson: String) throws -> MapKitReverseGeocodeRequest {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MapKitProviderError.invalidArguments("coordinate is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let coordinate = try requiredCoordinateArgument(in: dictionary)
        return MapKitReverseGeocodeRequest(coordinate: coordinate)
    }
}
```

- [ ] **Step 3: Add routing**

```swift
case "reverse_geocode":
    reverseGeocode(payloadJson: payloadJson)
```

- [ ] **Step 4: Update AppleProviderBridgeMapKitTests**

```swift
@Test
@MainActor
func callProviderMapKitReverseGeocodeSucceedsWithMockStore() throws {
    let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
    let item = MKMapItem(placemark: placemark)
    item.name = "Reverse Mock Address"
    let store = MockMapKitStore()
    store.authorizationStatus = .authorized
    store.reverseGeocodeResults = [[item]]
    let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

    let request = ProviderRequest(
        provider: "mapkit",
        operation: "reverse_geocode",
        payloadJson: #"{"coordinate":{"latitude":37.3346,"longitude":-122.0090}}"#
    )
    let response = bridge.callProvider(request: request)

    #expect(response.ok == true)
    let data = try #require(response.payloadJson.data(using: .utf8))
    let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let mapItems = decoded?["map_items"] as? [[String: Any]]
    #expect(mapItems?.first?["name"] as? String == "Reverse Mock Address")
}
```

- [ ] **Step 5: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add AppleBridge/Providers/MapKit/MapKitProviderReverseGeocode.swift \
  AppleBridge/Providers/MapKit/MapKitProviderRouting.swift \
  AppleBridgeTests/MapKitProviderReverseGeocodeTests.swift \
  AppleBridgeTests/AppleProviderBridgeMapKitTests.swift \
  AppleBridge.xcodeproj/project.pbxproj
git commit -m "feat(mapkit): implement reverse_geocode provider operation"
```

---

### Task 5: Ship capability + README + full verification

**Files:**
- Modify: `AppleBridge/Models/CapabilityCatalog.swift`
- Modify: `README.md`
- Modify: `AppleBridgeTests/PermissionsStoreMapKitTests.swift`
- Modify: `AppleBridgeTests/AppSettingsMapKitTests.swift`

- [ ] **Step 1: Flip capability shipped**

```swift
CapabilityDefinition(id: "mapkit-geocode", capabilityID: "mapkit.geocode", label: "Geocode", shipped: true),
```

- [ ] **Step 2: Add PermissionsStoreMapKit test for geocode toggle**

```swift
@Test
@MainActor
func requiresAppleLocationAccessIsTrueForShippedMapKitGeocodeToggle() throws {
    let suiteName = "PermissionsStoreMapKitTests.geocodeShipped"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
    store.setChecked(true, for: "mapkit-geocode")

    #expect(store.requiresAppleLocationAccess == true)
}
```

- [ ] **Step 3: Extend AppSettingsMapKit server gating test**

Add assertions that when `mapkit-geocode` is saved and location is authorized, `mapkit.geocode` appears in `serverEnabledMCPCapabilityIDs`:

```swift
appSettings.saveCapabilityIDs(["mapkit-geocode"])
#expect(appSettings.enabledMapKitCapabilityIDs == ["mapkit.geocode"])
#expect(
    appSettings.serverEnabledMCPCapabilityIDs(
        remindersAuthorized: false,
        eventsAuthorized: false,
        contactsAuthorized: false,
        locationAuthorized: true
    ).contains("mapkit.geocode")
)
```

- [ ] **Step 4: README checkoff**

```markdown
- [x] `mapkit.reverse_geocode`
```

- [ ] **Step 5: Run full verification**

Run: `TZ=UTC just test-all`  
Expected: PASS

Run: `TZ=UTC just ci`  
Expected: PASS (before merge)

- [ ] **Step 6: Commit**

```bash
git add AppleBridge/Models/CapabilityCatalog.swift README.md \
  AppleBridgeTests/PermissionsStoreMapKitTests.swift \
  AppleBridgeTests/AppSettingsMapKitTests.swift
git commit -m "feat(mapkit): ship mapkit.geocode capability for reverse_geocode"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `MAPKIT_GEOCODE` + `TOOL_REVERSE_GEOCODE` Rust registration | Task 1 |
| Input schema (`coordinate` required) | Task 1 |
| MCP integration tests | Task 2 |
| `MKReverseGeocodingRequest` via MapKitStore | Task 3 |
| Reuse exhaustive `MKMapItem` JSON (`MapKitSerialization`) | Task 3–4 |
| Location `permission_denied` gate | Task 4 |
| `mapkit-geocode` shipped | Task 5 |
| `just test-all` | Task 5 |