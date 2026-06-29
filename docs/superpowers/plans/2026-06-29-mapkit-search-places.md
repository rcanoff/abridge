# mapkit.search_places Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `mapkit.search_places` MCP tool (#104) with exhaustive `MKMapItem` JSON projection.

**Architecture:** `MapKitStore` protocol seam; `MapKitSerialization` for faithful MapKit JSON; Rust tool registration with `mapkit.search` capability; flip `mapkit-search` to shipped; CoreLocation when-in-use gate per #150.

**Tech Stack:** Rust (`apple_bridge_core`), Swift 6 + MapKit + CoreLocation, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-29-mapkit-search-places-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/capabilities.rs` | `MAPKIT_SEARCH` constant |
| `rust/apple_bridge_core/src/tools/mod.rs` | Tool registration + input schema |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `AppleBridge/Providers/MapKit/MapKitSerialization.swift` | MKMapItem / MKPlacemark / region JSON |
| `AppleBridge/Providers/MapKit/MapKitStore.swift` | Search protocol + auth seam |
| `AppleBridge/Providers/MapKit/LiveMapKitStore.swift` | `MKLocalSearch` blocking wrapper |
| `AppleBridge/Providers/MapKit/MapKitProvider.swift` | Provider shell + error helpers |
| `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift` | Operation dispatch |
| `AppleBridge/Providers/MapKit/MapKitProviderSearchPlaces.swift` | `search_places` handler |
| `AppleBridgeTests/MockMapKitStore.swift` | Deterministic search results |
| `AppleBridgeTests/MapKitSerializationTests.swift` | Fidelity assertions |
| `AppleBridgeTests/MapKitProviderSearchPlacesTests.swift` | Provider tests |
| `AppleBridge/Models/CapabilityCatalog.swift` | Ship `mapkit-search` |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/apple_bridge_core/src/capabilities.rs`
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`
- Test: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Add `MAPKIT_SEARCH` to capabilities.rs**

```rust
pub const MAPKIT_SEARCH: &str = "mapkit.search";
```

Add to `is_allowed_in_v1` match arm and add test:

```rust
#[test]
fn accepts_mapkit_search_capability_shape() {
  assert!(is_valid_capability_id(MAPKIT_SEARCH));
  assert!(is_allowed_in_v1(MAPKIT_SEARCH));
}
```

- [ ] **Step 2: Register tool in tools/mod.rs**

```rust
pub const TOOL_SEARCH_PLACES: &str = "mapkit.search_places";
```

Add to `ALL_TOOLS` (bump array length 43 → 44):

```rust
ToolDefinition {
  name: TOOL_SEARCH_PLACES,
  capability: capabilities::MAPKIT_SEARCH,
  provider: "mapkit",
  operation: "search_places",
  description: "Search for places by natural-language query with optional region bias",
},
```

- [ ] **Step 3: Add input schema**

```rust
TOOL_SEARCH_PLACES => serde_json::json!({
  "type": "object",
  "properties": {
    "query": { "type": "string", "minLength": 1 },
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
    "region_priority": {
      "type": "string",
      "enum": ["default", "required"]
    },
    "result_types": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": [
          "address",
          "point_of_interest",
          "query",
          "physical_feature",
          "physical_feature_query"
        ]
      }
    }
  },
  "required": ["query"]
}),
```

- [ ] **Step 4: Add unit test in tools/mod.rs tests module**

```rust
#[test]
fn lists_search_places_tool_when_mapkit_search_capability_enabled() {
  let tools = tools_for_capabilities(&["mapkit.search".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(names, vec![TOOL_SEARCH_PLACES]);
}

#[test]
fn search_places_schema_requires_query() {
  let tool = all_tools()
    .iter()
    .find(|tool| tool.name == TOOL_SEARCH_PLACES)
    .expect("search_places tool");
  let schema = input_schema(tool);
  assert_eq!(string_property_min_length(&schema, "query"), Some(1));
  assert_eq!(
    schema.get("required").and_then(|v| v.as_array()).map(|fields| {
      fields.iter().filter_map(|f| f.as_str().map(str::to_owned)).collect::<Vec<_>>()
    }),
    Some(vec!["query".to_owned()])
  );
}
```

- [ ] **Step 5: Run Rust tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/apple_bridge_core/src/capabilities.rs rust/apple_bridge_core/src/tools/mod.rs
git commit -m "feat(mapkit): register mapkit.search_places MCP tool in Rust"
```

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1: Add mapkit config helper** (mirror `contacts_config_on_port`)

```rust
fn mapkit_config_on_port(port: u16, enabled_capabilities: Vec<String>) -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port,
    bearer_token: TEST_TOKEN.into(),
    enabled_capabilities,
  }
}
```

- [ ] **Step 2: Write failing integration tests**

```rust
#[test]
fn mcp_tools_list_includes_search_places_when_mapkit_search_enabled() {
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
  assert!(resp.contains("mapkit.search_places"));
}

#[test]
fn tools_call_dispatches_search_places() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"mapkit.search_places","arguments":{"query":"coffee"}}}"#;

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
  assert_eq!(recorded.operation, "search_places");
  assert!(recorded.payload_json.contains("coffee"));
}
```

- [ ] **Step 3: Run tests**

Run: `TZ=UTC just test-rust`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add rust/apple_bridge_core/tests/mcp_protocol.rs
git commit -m "test(mapkit): add MCP integration tests for search_places"
```

---

### Task 3: MapKitSerialization (exhaustive MKMapItem)

**Files:**
- Create: `AppleBridge/Providers/MapKit/MapKitSerialization.swift`
- Create: `AppleBridgeTests/MapKitSerializationTests.swift`

- [ ] **Step 1: Write failing serialization test**

```swift
import MapKit
import Testing
@testable import AppleBridge

@Suite("MapKitSerialization")
struct MapKitSerializationTests {
    @Test
    func mapItemJSONObjectIncludesTopLevelKeys() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let item = MKMapItem(placemark: placemark)
        item.name = "Test Place"
        item.phoneNumber = "+1 555 0100"

        let json = MapKitSerialization.mapItemJSONObject(from: item)
        #expect(json["name"] as? String == "Test Place")
        #expect(json["phone_number"] as? String == "+1 555 0100")
        #expect(json.keys.contains("placemark"))
        #expect(json.keys.contains("is_current_location"))
        #expect(json.keys.contains("location"))
        #expect(json.keys.contains("address"))
        #expect(json.keys.contains("address_representations"))
        #expect(json.keys.contains("point_of_interest_category"))
        #expect(json.keys.contains("time_zone"))
        #expect(json.keys.contains("url"))
        #expect(json.keys.contains("identifier"))
    }

    @Test
    func coordinateRegionJSONObjectPreservesSpan() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 2),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        )
        let json = MapKitSerialization.coordinateRegionJSONObject(from: region)
        let center = json["center"] as? [String: Any]
        #expect(center?["latitude"] as? Double == 1)
        #expect(center?["longitude"] as? Double == 2)
        let span = json["span"] as? [String: Any]
        #expect(span?["latitude_delta"] as? Double == 0.1)
        #expect(span?["longitude_delta"] as? Double == 0.2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-swift`  
Expected: FAIL — `MapKitSerialization` not defined

- [ ] **Step 3: Implement MapKitSerialization.swift**

```swift
import Contacts
import CoreLocation
import Foundation
import MapKit

enum MapKitSerialization {
    static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MapKitProviderError.serializationFailed
        }
        return string
    }

    static func mapItemJSONObject(from item: MKMapItem) -> [String: Any] {
        [
            "name": jsonValueString(item.name),
            "phone_number": jsonValueString(item.phoneNumber),
            "url": jsonValueURL(item.url),
            "time_zone": jsonValueTimeZone(item.timeZone),
            "point_of_interest_category": jsonValuePOICategory(item.pointOfInterestCategory),
            "is_current_location": item.isCurrentLocation,
            "identifier": jsonValueMapItemIdentifier(item.identifier),
            "location": locationJSONObject(from: item.location),
            "placemark": placemarkJSONObject(from: item.placemark),
            "address": addressJSONObject(from: item.address),
            "address_representations": addressRepresentationsJSONArray(from: item.addressRepresentations),
        ]
    }

    static func coordinateRegionJSONObject(from region: MKCoordinateRegion) -> [String: Any] {
        [
            "center": coordinateJSONObject(from: region.center),
            "span": [
                "latitude_delta": region.span.latitudeDelta,
                "longitude_delta": region.span.longitudeDelta,
            ],
        ]
    }

    static func searchResponseJSONObject(
        mapItems: [MKMapItem],
        boundingRegion: MKCoordinateRegion?
    ) -> [String: Any] {
        [
            "map_items": mapItems.map(mapItemJSONObject(from:)),
            "bounding_region": boundingRegion.map(coordinateRegionJSONObject(from:)) ?? NSNull(),
        ]
    }

    // Implement placemarkJSONObject, locationJSONObject, addressJSONObject,
    // postalAddressJSONObject (CNPostalAddress), coordinateJSONObject,
    // jsonValueString/URL/TimeZone/POICategory helpers — all keys present, NSNull for nil.
}
```

- [ ] **Step 4: Run tests**

Run: `just test-swift`  
Expected: PASS for MapKitSerializationTests

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Providers/MapKit/MapKitSerialization.swift AppleBridgeTests/MapKitSerializationTests.swift
git commit -m "feat(mapkit): add exhaustive MapKit serialization"
```

---

### Task 4: MapKitStore + LiveMapKitStore

**Files:**
- Create: `AppleBridge/Providers/MapKit/MapKitStore.swift`
- Create: `AppleBridge/Providers/MapKit/LiveMapKitStore.swift`
- Create: `AppleBridgeTests/MockMapKitStore.swift`

- [ ] **Step 1: Define protocol and result type**

```swift
import CoreLocation
import MapKit

struct MapKitSearchResult: Equatable {
    let mapItems: [MKMapItem]
    let boundingRegion: MKCoordinateRegion?
}

struct MapKitSearchRequest: Equatable {
    let query: String
    let region: MKCoordinateRegion?
    let regionPriority: MKLocalSearchRegionPriority
    let resultTypes: MKLocalSearchResultType
}

protocol MapKitStoreing: Sendable {
    func locationAuthorizationStatus() -> CLAuthorizationStatus
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult
}
```

- [ ] **Step 2: Implement LiveMapKitStore with RunLoop-blocking search**

```swift
@MainActor
struct LiveMapKitStore: MapKitStoreing {
    func locationAuthorizationStatus() -> CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult {
        let mkRequest = MKLocalSearch.Request()
        mkRequest.naturalLanguageQuery = request.query
        mkRequest.region = request.region ?? MKCoordinateRegion()
        mkRequest.regionPriority = request.regionPriority
        mkRequest.resultTypes = request.resultTypes

        let search = MKLocalSearch(request: mkRequest)
        var response: MKLocalSearch.Response?
        var searchError: Error?
        let finished = NSCondition()

        search.start { result, error in
            response = result
            searchError = error
            finished.lock()
            finished.signal()
            finished.unlock()
        }

        finished.lock()
        let deadline = Date().addingTimeInterval(30)
        while response == nil && searchError == nil && Date() < deadline {
            finished.wait(until: Date(timeIntervalSinceNow: 0.05))
            EventKitReminderFetch.pumpRunLoop(until: Date(timeIntervalSinceNow: 0.05))
        }
        finished.unlock()

        if let searchError { throw searchError }
        guard let response else {
            throw MapKitProviderError.mapkitError("MapKit search timed out")
        }
        return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
    }
}
```

- [ ] **Step 3: Implement MockMapKitStore**

```swift
@MainActor
final class MockMapKitStore: MapKitStoreing {
    var authorizationStatus: CLAuthorizationStatus = .authorized
    var results: [MapKitSearchResult] = []
    private(set) var lastRequest: MapKitSearchRequest?

    func locationAuthorizationStatus() -> CLAuthorizationStatus { authorizationStatus }

    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult {
        lastRequest = request
        if let first = results.first { return first }
        return MapKitSearchResult(mapItems: [], boundingRegion: nil)
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add AppleBridge/Providers/MapKit/MapKitStore.swift \
  AppleBridge/Providers/MapKit/LiveMapKitStore.swift \
  AppleBridgeTests/MockMapKitStore.swift
git commit -m "feat(mapkit): add MapKitStore search seam"
```

---

### Task 5: MapKitProvider search_places operation

**Files:**
- Modify: `AppleBridge/Providers/MapKit/MapKitProvider.swift`
- Create: `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift`
- Create: `AppleBridge/Providers/MapKit/MapKitProviderSearchPlaces.swift`
- Create: `AppleBridgeTests/MapKitProviderSearchPlacesTests.swift`
- Modify: `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift`

- [ ] **Step 1: Write failing provider tests**

```swift
@Suite("MapKitProviderSearchPlaces")
struct MapKitProviderSearchPlacesTests {
    @Test
    func searchPlacesReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "search_places", payloadJson: #"{"query":"coffee"}"#)
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    func searchPlacesRequiresQuery() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "search_places", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    func searchPlacesReturnsSerializedResponse() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let item = MKMapItem(placemark: placemark)
        item.name = "Mock Cafe"
        let store = MockMapKitStore()
        store.results = [MapKitSearchResult(mapItems: [item], boundingRegion: nil)]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "search_places", payloadJson: #"{"query":"coffee"}"#)
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Mock Cafe")
        #expect(store.lastRequest?.query == "coffee")
    }
}
```

- [ ] **Step 2: Refactor MapKitProvider** (mirror ContactsProvider)

```swift
enum MapKitProviderError: Error, Equatable {
    case permissionDenied
    case serializationFailed
    case mapkitError(String)
    case invalidArguments(String)
}

@MainActor
struct MapKitProvider {
    let store: any MapKitStoreing

    init(store: any MapKitStoreing = LiveMapKitStore()) {
        self.store = store
    }

    var isLocationAuthorized: Bool {
        LocationPermissionStatusMapper.map(store.locationAuthorizationStatus()).grantsReadAccess
    }
}
```

- [ ] **Step 3: Implement search_places handler**

```swift
extension MapKitProvider {
    func searchPlaces(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }
        do {
            let arguments = try parseSearchPlacesArguments(payloadJson)
            let result = try store.searchPlaces(request: arguments)
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

Argument parsing: require non-empty `query`; optional `region` object; map `region_priority` strings to `MKLocalSearchRegionPriority`; map `result_types` array to `MKLocalSearchResultType` bitmask (default `.init([.address, .pointOfInterest, .query])`).

- [ ] **Step 4: Add routing**

```swift
extension MapKitProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "search_places":
            searchPlaces(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown mapkit operation: \(operation)")
        }
    }
}
```

- [ ] **Step 5: Update AppleProviderBridgeMapKitTests** — inject mock provider returning success for `search_places`.

- [ ] **Step 6: Run Swift tests**

Run: `just test-swift`  
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add AppleBridge/Providers/MapKit/ AppleBridgeTests/MapKitProviderSearchPlacesTests.swift \
  AppleBridgeTests/AppleProviderBridgeMapKitTests.swift
git commit -m "feat(mapkit): implement search_places provider operation"
```

---

### Task 6: Ship capability + README

**Files:**
- Modify: `AppleBridge/Models/CapabilityCatalog.swift`
- Modify: `README.md`
- Modify: `AppleBridgeTests/PermissionsStoreMapKitTests.swift` (update unshipped → shipped expectations)
- Modify: `AppleBridgeTests/AppSettingsMapKitTests.swift`

- [ ] **Step 1: Flip capability shipped**

```swift
CapabilityDefinition(id: "mapkit-search", capabilityID: "mapkit.search", label: "Search", shipped: true),
```

- [ ] **Step 2: Update tests** — `requiresAppleLocationAccess` true when `mapkit-search` checked; server gating includes `mapkit.search` when location authorized.

- [ ] **Step 3: README checkoff**

```markdown
- [x] `mapkit.search_places`
```

- [ ] **Step 4: Run full verification**

Run: `TZ=UTC just test-all`  
Expected: PASS

Run: `TZ=UTC just ci`  
Expected: PASS (before merge)

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Models/CapabilityCatalog.swift README.md AppleBridgeTests/PermissionsStoreMapKitTests.swift \
  AppleBridgeTests/AppSettingsMapKitTests.swift
git commit -m "feat(mapkit): ship mapkit.search capability for search_places"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `MAPKIT_SEARCH` + `TOOL_SEARCH_PLACES` Rust registration | Task 1 |
| Input schema (`query`, optional region/priority/result_types) | Task 1 |
| MCP integration tests | Task 2 |
| `MKLocalSearch` via MapKitStore | Task 4 |
| Exhaustive `MKMapItem` JSON | Task 3 |
| Location `permission_denied` gate | Task 5 |
| `mapkit-search` shipped | Task 6 |
| `just test-all` | Task 6 |