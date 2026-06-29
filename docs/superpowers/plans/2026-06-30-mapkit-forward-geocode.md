# mapkit.forward_geocode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `mapkit.forward_geocode` MCP tool (#107) with exhaustive `MKMapItem` JSON projection under the existing `mapkit.geocode` capability.

**Architecture:** Extend `MapKitStore` with `forwardGeocode`; use `MKGeocodingRequest` in `LiveMapKitStore`; reuse `MapKitSerialization` and region/address parsing from existing MapKit provider helpers; Rust tool registration on existing `mapkit.geocode` capability; CoreLocation when-in-use gate per #150.

**Tech Stack:** Rust (`apple_bridge_core`), Swift 6 + MapKit + CoreLocation, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-mapkit-forward-geocode-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/tools/mod.rs` | `TOOL_FORWARD_GEOCODE` registration + input schema |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `AppleBridge/Providers/MapKit/MapKitStore.swift` | `MapKitForwardGeocodeRequest` + protocol method |
| `AppleBridge/Providers/MapKit/LiveMapKitStore.swift` | `MKGeocodingRequest` blocking wrapper |
| `AppleBridge/Providers/MapKit/MapKitProviderForwardGeocode.swift` | `forward_geocode` handler |
| `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift` | Operation dispatch |
| `AppleBridgeTests/MockMapKitStore.swift` | Forward-geocode mock seam |
| `AppleBridgeTests/MapKitProviderForwardGeocodeTests.swift` | Provider tests |
| `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift` | Bridge routing test |
| `README.md` | Check off tool |

---

### Task 1: Rust tool registration

**Files:**
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`

- [ ] **Step 1: Register tool in tools/mod.rs**

```rust
pub const TOOL_FORWARD_GEOCODE: &str = "mapkit.forward_geocode";
```

Add to `ALL_TOOLS` (bump array length 46 → 47), after `TOOL_REVERSE_GEOCODE`:

```rust
ToolDefinition {
  name: TOOL_FORWARD_GEOCODE,
  capability: capabilities::MAPKIT_GEOCODE,
  provider: "mapkit",
  operation: "forward_geocode",
  description: "Resolve an address string to place representations",
},
```

- [ ] **Step 2: Add input schema**

```rust
TOOL_FORWARD_GEOCODE => serde_json::json!({
  "type": "object",
  "properties": {
    "address": { "type": "string", "minLength": 1 },
    "region": {
      "type": "object",
      "properties": {
        "center": {
          "type": "object",
          "properties": {
            "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
            "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
          },
          "required": ["latitude", "longitude"]
        },
        "span": {
          "type": "object",
          "properties": {
            "latitude_delta": { "type": "number", "exclusiveMinimum": 0 },
            "longitude_delta": { "type": "number", "exclusiveMinimum": 0 }
          },
          "required": ["latitude_delta", "longitude_delta"]
        }
      },
      "required": ["center", "span"]
    },
    "preferred_locale": { "type": "string", "minLength": 1 }
  },
  "required": ["address"]
}),
```

- [ ] **Step 3: Add unit tests in tools/mod.rs tests module**

Update existing geocode list test to expect both tools:

```rust
#[test]
fn lists_geocode_tools_when_mapkit_geocode_capability_enabled() {
  let tools = tools_for_capabilities(&["mapkit.geocode".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_REVERSE_GEOCODE, TOOL_FORWARD_GEOCODE]);
}

#[test]
fn forward_geocode_schema_requires_address() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_FORWARD_GEOCODE)
    .expect("forward_geocode tool");
  let schema = input_schema(tool);
  assert_eq!(
    schema
      .get("required")
      .and_then(|value| value.as_array())
      .map(|items| items.iter().filter_map(|item| item.as_str()).collect::<Vec<_>>()),
    Some(vec!["address"])
  );
  assert!(schema
    .get("properties")
    .and_then(|p| p.get("address"))
    .is_some());
}
```

Import `TOOL_FORWARD_GEOCODE` in the tests module `use super::{ ... }` block. Rename `lists_reverse_geocode_tool_when_mapkit_geocode_capability_enabled` → `lists_geocode_tools_when_mapkit_geocode_capability_enabled`.

- [ ] **Step 4: Run Rust tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/apple_bridge_core/src/tools/mod.rs
git commit -m "feat(mapkit): register mapkit.forward_geocode MCP tool in Rust"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Write integration tests** (reuse existing `mapkit_config_on_port`)

```rust
#[test]
fn mcp_tools_list_includes_forward_geocode_when_mapkit_geocode_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":15,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    mapkit_config_on_port(port, vec!["mapkit.geocode".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("mapkit.forward_geocode"));
}

#[test]
fn tools_call_dispatches_forward_geocode() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"mapkit.forward_geocode","arguments":{"address":"1 Apple Park Way, Cupertino, CA"}}}"#;

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
  assert_eq!(recorded.operation, "forward_geocode");
  assert!(recorded.payload_json.contains("1 Apple Park Way"));
}
```

- [ ] **Step 2: Run tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add rust/apple_bridge_core/tests/mcp_protocol.rs
git commit -m "test(mapkit): add MCP integration tests for forward_geocode"
```

---

### Task 3: MapKitStore seam

**Files:**
- Modify: `AppleBridge/Providers/MapKit/MapKitStore.swift`
- Modify: `AppleBridge/Providers/MapKit/LiveMapKitStore.swift`
- Modify: `AppleBridgeTests/MockMapKitStore.swift`

- [ ] **Step 1: Extend MapKitStore types**

```swift
struct MapKitForwardGeocodeRequest {
    let address: String
    let region: MKCoordinateRegion?
    let preferredLocale: Locale?
}

@MainActor
protocol MapKitStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult
    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult
    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem]
    func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem]
}
```

- [ ] **Step 2: Implement LiveMapKitStore.forwardGeocode**

```swift
func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem] {
    guard let mkRequest = MKGeocodingRequest(addressString: request.address) else {
        throw MapKitProviderError.mapkitError("MapKit forward geocode request could not be created")
    }
    if let region = request.region {
        mkRequest.region = region
    }
    if let preferredLocale = request.preferredLocale {
        mkRequest.preferredLocale = preferredLocale
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
        throw MapKitProviderError.mapkitError("MapKit forward geocode returned no response")
    }
    return mapItems
}
```

- [ ] **Step 3: Extend MockMapKitStore**

```swift
var forwardGeocodeResults: [[MKMapItem]] = []
private(set) var lastForwardGeocodeRequest: MapKitForwardGeocodeRequest?

func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem] {
    lastForwardGeocodeRequest = request
    if let first = forwardGeocodeResults.first {
        return first
    }
    return []
}
```

- [ ] **Step 4: Run Swift tests**

Run: `just test-swift`  
Expected: PASS (existing tests unchanged)

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Providers/MapKit/MapKitStore.swift \
  AppleBridge/Providers/MapKit/LiveMapKitStore.swift \
  AppleBridgeTests/MockMapKitStore.swift
git commit -m "feat(mapkit): add MapKitStore forward_geocode seam"
```

---

### Task 4: MapKitProvider forward_geocode operation

**Files:**
- Create: `AppleBridge/Providers/MapKit/MapKitProviderForwardGeocode.swift`
- Modify: `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift`
- Create: `AppleBridgeTests/MapKitProviderForwardGeocodeTests.swift`
- Modify: `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift`
- Modify: `AppleBridge.xcodeproj/project.pbxproj` (add new Swift files)

- [ ] **Step 1: Write failing provider tests**

```swift
@Suite("MapKitProviderForwardGeocode")
struct MapKitProviderForwardGeocodeTests {
    @Test
    @MainActor
    func forwardGeocodeReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "forward_geocode",
            payloadJson: #"{"address":"1 Apple Park Way, Cupertino, CA"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func forwardGeocodeRequiresAddress() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "forward_geocode", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func forwardGeocodeReturnsSerializedResponse() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let item = MKMapItem(placemark: placemark)
        item.name = "Apple Park"
        let store = MockMapKitStore()
        store.forwardGeocodeResults = [[item]]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "forward_geocode",
            payloadJson: #"{"address":"1 Apple Park Way, Cupertino, CA"}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Apple Park")
        #expect(store.lastForwardGeocodeRequest?.address == "1 Apple Park Way, Cupertino, CA")
    }
}
```

- [ ] **Step 2: Implement forward_geocode handler**

```swift
extension MapKitProvider {
    func forwardGeocode(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

        do {
            let arguments = try parseForwardGeocodeArguments(payloadJson)
            let mapItems = try store.forwardGeocode(request: arguments)
            let payloadObject = MapKitSerialization.reverseGeocodeResponseJSONObject(mapItems: mapItems)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseForwardGeocodeArguments(_ payloadJson: String) throws -> MapKitForwardGeocodeRequest {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MapKitProviderError.invalidArguments("address is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let address = try requiredAddressArgument(in: dictionary)
        let region = try optionalRegionArgument(in: dictionary)
        let preferredLocale = try optionalPreferredLocaleArgument(in: dictionary)
        return MapKitForwardGeocodeRequest(
            address: address,
            region: region,
            preferredLocale: preferredLocale
        )
    }

    private func requiredAddressArgument(in dictionary: [String: Any]) throws -> String {
        guard dictionary.keys.contains("address") else {
            throw MapKitProviderError.invalidArguments("address is required")
        }

        if dictionary["address"] is NSNull {
            throw MapKitProviderError.invalidArguments("address is required")
        }

        guard let address = dictionary["address"] as? String else {
            throw MapKitProviderError.invalidArguments("address must be a string")
        }

        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MapKitProviderError.invalidArguments("address must not be empty")
        }

        return trimmed
    }

    private func optionalPreferredLocaleArgument(in dictionary: [String: Any]) throws -> Locale? {
        guard dictionary.keys.contains("preferred_locale") else {
            return nil
        }

        if dictionary["preferred_locale"] is NSNull {
            return nil
        }

        guard let identifier = dictionary["preferred_locale"] as? String else {
            throw MapKitProviderError.invalidArguments("preferred_locale must be a string or null")
        }

        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MapKitProviderError.invalidArguments("preferred_locale must not be empty")
        }

        return Locale(identifier: trimmed)
    }
}
```

- [ ] **Step 3: Add routing**

```swift
case "forward_geocode":
    forwardGeocode(payloadJson: payloadJson)
```

- [ ] **Step 4: Update AppleProviderBridgeMapKitTests**

```swift
@Test
@MainActor
func callProviderMapKitForwardGeocodeSucceedsWithMockStore() throws {
    let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
    let item = MKMapItem(placemark: placemark)
    item.name = "Forward Mock Address"
    let store = MockMapKitStore()
    store.authorizationStatus = .authorized
    store.forwardGeocodeResults = [[item]]
    let bridge = AppleProviderBridge(mapKitProvider: MapKitProvider(store: store))

    let request = ProviderRequest(
        provider: "mapkit",
        operation: "forward_geocode",
        payloadJson: #"{"address":"1 Apple Park Way, Cupertino, CA"}"#
    )
    let response = bridge.callProvider(request: request)

    #expect(response.ok == true)
    let data = try #require(response.payloadJson.data(using: .utf8))
    let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let mapItems = decoded?["map_items"] as? [[String: Any]]
    #expect(mapItems?.first?["name"] as? String == "Forward Mock Address")
}
```

- [ ] **Step 5: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add AppleBridge/Providers/MapKit/MapKitProviderForwardGeocode.swift \
  AppleBridge/Providers/MapKit/MapKitProviderRouting.swift \
  AppleBridgeTests/MapKitProviderForwardGeocodeTests.swift \
  AppleBridgeTests/AppleProviderBridgeMapKitTests.swift \
  AppleBridge.xcodeproj/project.pbxproj
git commit -m "feat(mapkit): implement forward_geocode provider operation"
```

---

### Task 5: README + full verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README checkoff**

```markdown
- [x] `mapkit.forward_geocode`
```

- [ ] **Step 2: Run full verification**

Run: `TZ=UTC just test-all`  
Expected: PASS

Run: `TZ=UTC just ci`  
Expected: PASS (before merge)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "feat(mapkit): ship mapkit.forward_geocode tool"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `TOOL_FORWARD_GEOCODE` Rust registration (existing `MAPKIT_GEOCODE`) | Task 1 |
| Input schema (`address` required; optional `region`, `preferred_locale`) | Task 1 |
| MCP integration tests | Task 2 |
| `MKGeocodingRequest` via MapKitStore | Task 3 |
| Reuse exhaustive `MKMapItem` JSON (`MapKitSerialization`) | Task 3–4 |
| Location `permission_denied` gate | Task 4 |
| README checkoff | Task 5 |
| `just test-all` | Task 5 |