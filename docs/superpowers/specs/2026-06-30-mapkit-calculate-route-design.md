# mapkit.calculate_route MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Draft  
**Issue:** #108 (Epic #103; first routing tool — ships `mapkit.routing` capability)  
**Branch:** `feat/mapkit-calculate-route`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-29-mapkit-permissions-foundation-design.md`  
**Sibling:** `mapkit.estimate_travel_time` (#109; shares `mapkit.routing` capability)

---

## Summary

Implement `mapkit.calculate_route` MCP tool: compute turn-by-turn routes between two coordinates via **`MKDirections`**. Returns **exhaustive `MKDirectionsResponse` JSON projection** (source/destination `MKMapItem`, `MKRoute` + `MKRouteStep` geometry and metadata). Register in Rust tool catalog gated by new **`mapkit.routing`** capability. Flip `mapkit-routing` capability to **`shipped: true`**. Enforce **CoreLocation when-in-use** authorization per MapKit foundation (#150).

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `mapkit.calculate_route` |
| Capability | `mapkit.routing` |
| Provider | `mapkit` |
| Operation | `calculate_route` |

### MapKit API choice

Use **`MKDirections`** with **`MKDirectionsRequest`**:

| MCP argument | Apple API |
|--------------|-----------|
| `source.coordinate` | `MKMapItem` built from `MKPlacemark(coordinate:)` → `request.source` |
| `destination.coordinate` | `MKMapItem` built from `MKPlacemark(coordinate:)` → `request.destination` |
| `transport_type` (optional) | `request.transportType` (`MKDirectionsTransportType`) |
| `requests_alternate_routes` (optional) | `request.requestsAlternateRoutes` |
| `departure_date` (optional) | `request.departureDate` |
| `arrival_date` (optional) | `request.arrivalDate` |
| `toll_preference` (optional) | `request.tollPreference` (`MKDirectionsRoutePreference`) |
| `highway_preference` (optional) | `request.highwayPreference` (`MKDirectionsRoutePreference`) |

`MKDirections.calculateDirections(completionHandler:)` runs asynchronously; the provider blocks on the main actor using the existing **RunLoop pump** pattern (`MapKitSearchFetch.waitForCompletion`) — same synchronous FFI contract as other MapKit providers.

Do **not** use third-party routing APIs; MapKit remains the system of record.

### Input schema (Rust `input_schema`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `source` | object | **yes** | Route origin |
| `source.coordinate` | object | **yes** | `CLLocationCoordinate2D` |
| `source.coordinate.latitude` | number | yes | `[-90, 90]` |
| `source.coordinate.longitude` | number | yes | `[-180, 180]` |
| `destination` | object | **yes** | Route terminus |
| `destination.coordinate` | object | **yes** | Same shape as source |
| `transport_type` | string enum | no | `automobile` (default), `walking`, `transit`, `cycling`, `any` |
| `requests_alternate_routes` | boolean | no | Default `false` |
| `departure_date` | string (`date-time`) | no | ISO 8601; mutually exclusive with `arrival_date` |
| `arrival_date` | string (`date-time`) | no | ISO 8601; mutually exclusive with `departure_date` |
| `toll_preference` | string enum | no | `any` (default), `avoid` |
| `highway_preference` | string enum | no | `any` (default), `avoid` |

Validation errors (Swift `invalid_arguments`):

| Condition | Message (representative) |
|-----------|--------------------------|
| Missing / null `source` or `destination` | `"source is required"` / `"destination is required"` |
| Missing coordinate | `"source.coordinate is required"` / `"destination.coordinate is required"` |
| Invalid coordinate shape | Same coordinate messages as `reverse_geocode` |
| Both `departure_date` and `arrival_date` | `"provide departure_date or arrival_date, not both"` |
| Invalid `transport_type` | `"transport_type must be one of: automobile, walking, transit, cycling, any"` |
| Invalid preference | `"toll_preference must be one of: any, avoid"` |

Reuse `requiredCoordinateArgument(in:)` pattern from `MapKitProviderSearchArguments.swift` with nested key prefixes (`source.coordinate`, `destination.coordinate`).

### Output

JSON **object** mirroring `MKDirectionsResponse`:

```json
{
  "source": { /* exhaustive MKMapItem via MapKitSerialization */ },
  "destination": { /* exhaustive MKMapItem */ },
  "routes": [
    {
      "name": "US-101",
      "advisory_notices": ["..."],
      "distance": 12345.0,
      "expected_travel_time": 1800.0,
      "transport_type": ["automobile"],
      "polyline": {
        "title": null,
        "subtitle": null,
        "point_count": 42,
        "coordinates": [{ "latitude": 37.0, "longitude": -122.0 }]
      },
      "steps": [
        {
          "instructions": "Turn left onto...",
          "notice": null,
          "distance": 100.0,
          "transport_type": ["automobile"],
          "polyline": { "title": null, "subtitle": null, "point_count": 2, "coordinates": [] }
        }
      ],
      "has_tolls": false,
      "has_highways": true
    }
  ]
}
```

`routes` may be empty when Apple returns no viable route (valid success). `source` and `destination` may include enriched `MKMapItem` details from Apple's response.

---

## Framework fidelity

### Reuse

- **`MapKitSerialization.mapItemJSONObject(from:)`** for `source` and `destination`.

### New serializers

| Function | Source type |
|----------|-------------|
| `calculateRouteResponseJSONObject(result:)` | `MapKitCalculateRouteResult` (store seam) |
| `routeJSONObject(from:)` | `MapKitRouteData` |
| `routeStepJSONObject(from:)` | `MapKitRouteStepData` |
| `polylineJSONObject(coordinates:title:subtitle:)` | `MKPolyline` geometry |

### `MKRoute` keys (snake_case)

`name`, `advisory_notices`, `distance`, `expected_travel_time`, `transport_type`, `polyline`, `steps`, `has_tolls`, `has_highways`.

### `MKRouteStep` keys

`instructions`, `notice`, `distance`, `transport_type`, `polyline`.

### `MKDirectionsTransportType` encoding

Serialize bitmask as **string array** of active modes: `automobile`, `walking`, `transit`, `cycling`. When `MKDirectionsTransportTypeAny` (all bits), emit `["any"]`.

### `MKPolyline` encoding

`title`, `subtitle` (from `MKShape`), `point_count`, `coordinates` (array of `{latitude, longitude}` via `getCoordinates(_:range:)`).

---

## Architecture

```
Rust tools/call → ProviderBridge → MapKitProvider.calculate_route
                                        ↓
                              MapKitStore (protocol)
                                        ↓
                         LiveMapKitStore / MockMapKitStore
                                        ↓
                    MKDirections.calculateDirections
```

`MapKitCalculateRouteResult` / `MapKitRouteData` are **store seam types** (MKRoute is not constructible for mocks). `LiveMapKitStore` maps `MKDirectionsResponse` → seam types; `MapKitSerialization` projects seam types to fidelity JSON.

### Swift files (new)

| File | Role |
|------|------|
| `ABridge/Providers/MapKit/MapKitProviderCalculateRoute.swift` | `calculate_route` operation handler |
| `ABridgeTests/MapKitProviderCalculateRouteTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `ABridge/Providers/MapKit/MapKitStore.swift` | Request/result/route seam types + `calculateRoute(request:)` |
| `ABridge/Providers/MapKit/LiveMapKitStore.swift` | `MKDirections` blocking wrapper + response mapping |
| `ABridge/Providers/MapKit/MapKitSerialization.swift` | Route/step/polyline serializers |
| `ABridge/Providers/MapKit/MapKitProviderRouting.swift` | Dispatch `calculate_route` |
| `ABridge/Models/CapabilityCatalog.swift` | `mapkit-routing` → `shipped: true` |
| `ABridgeTests/MockMapKitStore.swift` | Fake route results + `lastCalculateRouteRequest` |
| `ABridgeTests/AppleProviderBridgeMapKitTests.swift` | Success path for `calculate_route` |
| `ABridgeTests/AppSettingsMapKitTests.swift` | Server gating for `mapkit.routing` |
| `ABridgeTests/PermissionsStoreMapKitTests.swift` | Location requirement for routing toggle |
| `README.md` | Check off `mapkit.calculate_route` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/abridge_core/src/capabilities.rs` | `MAPKIT_ROUTING` constant + v1 allowlist |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_CALCULATE_ROUTE`, registration, input schema, unit tests |
| `rust/abridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `mapkit.routing` is in server enabled capabilities |
| Apple location | `MapKitProvider.isLocationAuthorized` before `MKDirections` |
| Settings | `mapkit-routing` shipped toggle; `serverEnabledMCPCapabilityIDs` includes `mapkit.routing` when `locationAuthorized` |

| Condition | Error code |
|-----------|------------|
| Location not authorized | `permission_denied` |
| Invalid JSON / bad arguments | `invalid_arguments` |
| `MKDirections` failure | `mapkit_error` |
| Serialization failure | `mapkit_error` |

---

## Acceptance criteria (#108)

1. `mapkit.calculate_route` in `tools/list` when `mapkit.routing` enabled.
2. Valid `tools/call` succeeds against mock/live MapKit per tests.
3. Disabled capability or missing location permission → typed error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `mapkit-routing` capability shipped in Settings.
6. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): grant Location, enable MapKit Routing in Settings, call tool with Cupertino→San Francisco coordinates.