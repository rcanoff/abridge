# mapkit.search_nearby Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `mapkit.search_nearby` MCP tool (#105) with exhaustive `MKMapItem` JSON projection, mirroring #104 `search_places` patterns.

**Architecture:** Extend `MapKitStore` with `searchNearby`; reuse `MapKitSerialization` and `MapKitSearchFetch`; Rust tool registration with existing `mapkit.search` capability; shared argument parsing extracted from `search_places`.

**Tech Stack:** Rust (`apple_bridge_core`), Swift 6 + MapKit + CoreLocation, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-29-mapkit-search-nearby-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/tools/mod.rs` | `TOOL_SEARCH_NEARBY` registration + input schema |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `AppleBridge/Providers/MapKit/MapKitProviderSearchArguments.swift` | Shared region/coordinate/category parsing |
| `AppleBridge/Providers/MapKit/MapKitStore.swift` | `MapKitSearchNearbyRequest` + protocol method |
| `AppleBridge/Providers/MapKit/LiveMapKitStore.swift` | `MKLocalSearch` POI-nearby blocking wrapper |
| `AppleBridge/Providers/MapKit/MapKitProviderSearchNearby.swift` | `search_nearby` handler |
| `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift` | Operation dispatch |
| `AppleBridge/Providers/MapKit/MapKitProviderSearchPlaces.swift` | Refactor to shared argument helpers |
| `AppleBridgeTests/MockMapKitStore.swift` | Nearby mock seam |
| `AppleBridgeTests/MapKitProviderSearchNearbyTests.swift` | Provider tests |
| `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift` | Bridge routing test |
| `README.md` | Check off tool |

---

### Task 1: Rust tool registration

**Files:**
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`
- Test: `rust/apple_bridge_core/tests/mcp_protocol.rs` (no changes yet)

- [ ] **Step 1: Add constant and tool definition**

```rust
pub const TOOL_SEARCH_NEARBY: &str = "mapkit.search_nearby";
```

Add to `ALL_TOOLS` (bump array length 44 → 45), immediately after `TOOL_SEARCH_PLACES`:

```rust
ToolDefinition {
  name: TOOL_SEARCH_NEARBY,
  capability: capabilities::MAPKIT_SEARCH,
  provider: "mapkit",
  operation: "search_nearby",
  description: "Search for points of interest near a coordinate or region",
},
```

- [ ] **Step 2: Add input schema**

```rust
TOOL_SEARCH_NEARBY => serde_json::json!({
  "type": "object",
  "properties": {
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
    "coordinate": {
      "type": "object",
      "properties": {
        "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
        "longitude": { "type": "number", "minimum": -180, "maximum": 180 }
      },
      "required": ["latitude", "longitude"]
    },
    "radius_meters": { "type": "number", "exclusiveMinimum": 0 },
    "including_categories": {
      "type": "array",
      "items": { "type": "string", "minLength": 1 }
    },
    "excluding_categories": {
      "type": "array",
      "items": { "type": "string", "minLength": 1 }
    }
  }
}),
```

No `required` array at schema root — Swift enforces `region` XOR `coordinate`.

- [ ] **Step 3: Add unit tests in tools/mod.rs tests module**

```rust
#[test]
fn lists_mapkit_search_tools_when_mapkit_search_capability_enabled() {
  let tools = tools_for_capabilities(&["mapkit.search".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_SEARCH_PLACES, TOOL_SEARCH_NEARBY]);
}

#[test]
fn search_nearby_schema_has_region_and_coordinate_properties() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_SEARCH_NEARBY)
    .expect("search_nearby tool");
  let schema = input_schema(tool);
  assert!(schema
    .get("properties")
    .and_then(|p| p.get("region"))
    .is_some());
  assert!(schema
    .get("properties")
    .and_then(|p| p.get("coordinate"))
    .is_some());
  assert!(schema
    .get("properties")
    .and_then(|p| p.get("including_categories"))
    .is_some());
}
```

- [ ] **Step 4: Update existing test** — rename `lists_search_places_tool_when_mapkit_search_capability_enabled` to `lists_mapkit_search_tools_when_mapkit_search_capability_enabled` and assert both tool names.

- [ ] **Step 5: Run Rust tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/apple_bridge_core/src/tools/mod.rs
git commit -m "feat(mapkit): register mapkit.search_nearby MCP tool in Rust"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Write failing integration tests** (reuse existing `mapkit_config_on_port`)

```rust
#[test]
fn mcp_tools_list_includes_search_nearby_when_mapkit_search_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    mapkit_config_on_port(port, vec!["mapkit.search".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("mapkit.search_nearby"));
}

#[test]
fn tools_call_dispatches_search_nearby() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"mapkit.search_nearby","arguments":{"coordinate":{"latitude":37.3346,"longitude":-122.0090},"radius_meters":500}}}"#;

  let handle = create_server(
    mapkit_config_on_port(port, vec!["mapkit.search".into()]),
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
  assert_eq!(recorded.operation, "search_nearby");
  assert!(recorded.payload_json.contains("37.3346"));
}
```

- [ ] **Step 2: Run tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add rust/apple_bridge_core/tests/mcp_protocol.rs
git commit -m "test(mapkit): add MCP integration tests for search_nearby"
```

---

### Task 3: Shared argument parsing + MapKitStore seam

**Files:**
- Create: `AppleBridge/Providers/MapKit/MapKitProviderSearchArguments.swift`
- Modify: `AppleBridge/Providers/MapKit/MapKitStore.swift`
- Modify: `AppleBridge/Providers/MapKit/LiveMapKitStore.swift`
- Modify: `AppleBridge/Providers/MapKit/MapKitProviderSearchPlaces.swift`
- Modify: `AppleBridgeTests/MockMapKitStore.swift`
- Modify: `AppleBridge.xcodeproj/project.pbxproj` (add new Swift file)

- [ ] **Step 1: Extend MapKitStore types**

```swift
struct MapKitSearchNearbyRequest {
    let region: MKCoordinateRegion
    let pointOfInterestFilter: MKPointOfInterestFilter?
}

@MainActor
protocol MapKitStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult
    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult
}
```

- [ ] **Step 2: Extract shared parsers into MapKitProviderSearchArguments.swift**

Move from `MapKitProviderSearchPlaces.swift` (keep behavior identical):

- `parseJSONObject(from:)`
- `optionalRegionArgument(in:)` / `requiredRegionArgument(in:)`
- `requiredCoordinateArgument(in:)`
- `coordinateRegion(from:radiusMeters:)` — default radius **1000**
- `optionalPOICategoryFilter(in:)` — maps `including_categories` / `excluding_categories` to `MKPointOfInterestFilter`
- `requiredGeographicAnchor(in:)` — returns `MKCoordinateRegion`; enforces XOR `region` / `coordinate`

Category mapping: `MKPointOfInterestCategory(rawValue:)`; reject unknown raw values with `invalid_arguments`.

- [ ] **Step 3: Refactor MapKitProviderSearchPlaces** to call shared helpers (no behavior change; `just test-swift` must stay green).

- [ ] **Step 4: Implement LiveMapKitStore.searchNearby**

```swift
func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult {
    let mkRequest = MKLocalSearch.Request()
    mkRequest.region = request.region
    mkRequest.regionPriority = .required
    mkRequest.resultTypes = .pointOfInterest
    mkRequest.pointOfInterestFilter = request.pointOfInterestFilter

    let search = MKLocalSearch(request: mkRequest)
    var response: MKLocalSearch.Response?
    var searchError: Error?

    try MapKitSearchFetch.waitForCompletion { complete in
        search.start { result, error in
            response = result
            searchError = error
            complete()
        }
    }

    if let searchError { throw searchError }
    guard let response else {
        throw MapKitProviderError.mapkitError("MapKit search returned no response")
    }
    return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
}
```

- [ ] **Step 5: Extend MockMapKitStore**

```swift
var nearbyResults: [MapKitSearchResult] = []
private(set) var lastNearbyRequest: MapKitSearchNearbyRequest?

func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult {
    lastNearbyRequest = request
    if let first = nearbyResults.first { return first }
    return MapKitSearchResult(mapItems: [], boundingRegion: nil)
}
```

- [ ] **Step 6: Run Swift tests**

Run: `just test-swift`  
Expected: PASS (search_places unchanged)

- [ ] **Step 7: Commit**

```bash
git add AppleBridge/Providers/MapKit/ AppleBridgeTests/MockMapKitStore.swift AppleBridge.xcodeproj/project.pbxproj
git commit -m "feat(mapkit): add MapKitStore search_nearby seam and shared parsers"
```

---

### Task 4: MapKitProvider search_nearby operation

**Files:**
- Create: `AppleBridge/Providers/MapKit/MapKitProviderSearchNearby.swift`
- Modify: `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift`
- Create: `AppleBridgeTests/MapKitProviderSearchNearbyTests.swift`
- Modify: `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift`
- Modify: `AppleBridge.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing provider tests**

```swift
@Suite("MapKitProviderSearchNearby")
struct MapKitProviderSearchNearbyTests {
    @Test @MainActor
    func searchNearbyReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0}}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test @MainActor
    func searchNearbyRequiresRegionOrCoordinate() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "search_nearby", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test @MainActor
    func searchNearbyRejectsBothRegionAndCoordinate() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: #"{"region":{"center":{"latitude":37.0,"longitude":-122.0},"span":{"latitude_delta":0.1,"longitude_delta":0.1}},"coordinate":{"latitude":37.0,"longitude":-122.0}}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test @MainActor
    func searchNearbyReturnsSerializedResponse() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let item = MKMapItem(placemark: placemark)
        item.name = "Nearby Cafe"
        let store = MockMapKitStore()
        store.nearbyResults = [MapKitSearchResult(mapItems: [item], boundingRegion: nil)]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0},"radius_meters":800}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Nearby Cafe")
        #expect(store.lastNearbyRequest != nil)
    }
}
```

- [ ] **Step 2: Implement search_nearby handler**

```swift
extension MapKitProvider {
    func searchNearby(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

        do {
            let arguments = try parseSearchNearbyArguments(payloadJson)
            let result = try store.searchNearby(request: arguments)
            let payloadObject = MapKitSerialization.searchResponseJSONObject(
                mapItems: result.mapItems,
                boundingRegion: result.boundingRegion
            )
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 3: Add routing**

```swift
case "search_nearby":
    searchNearby(payloadJson: payloadJson)
```

- [ ] **Step 4: Update AppleProviderBridgeMapKitTests** — add success path for `search_nearby` (mirror `search_places` test).

- [ ] **Step 5: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add AppleBridge/Providers/MapKit/ AppleBridgeTests/MapKitProviderSearchNearbyTests.swift \
  AppleBridgeTests/AppleProviderBridgeMapKitTests.swift AppleBridge.xcodeproj/project.pbxproj
git commit -m "feat(mapkit): implement search_nearby provider operation"
```

---

### Task 5: README + full verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README checkoff**

```markdown
- [x] `mapkit.search_nearby`
```

- [ ] **Step 2: Run full verification**

Run: `TZ=UTC just test-all`  
Expected: PASS

Run: `TZ=UTC just ci`  
Expected: PASS (before merge)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "feat(mapkit): ship mapkit.search_nearby MCP tool"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `TOOL_SEARCH_NEARBY` Rust registration | Task 1 |
| Input schema (`region` XOR `coordinate`, categories, radius) | Task 1 |
| MCP integration tests | Task 2 |
| `MKLocalSearch` POI nearby via MapKitStore | Task 3 |
| Reuse exhaustive `MKMapItem` JSON (`MapKitSerialization`) | Task 4 |
| Location `permission_denied` gate | Task 4 |
| `mapkit.search` capability (no new capability) | — (already shipped #104) |
| `just test-all` | Task 5 |