# mapkit.search_nearby MCP Tool — Design Spec

**Date:** 2026-06-29  
**Status:** Approved  
**Issue:** #105 (Epic #103; depends on sibling #104 `mapkit.search_places`)  
**Branch:** `feat/mapkit-search-nearby`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-29-mapkit-permissions-foundation-design.md`  
**Sibling:** `docs/superpowers/specs/2026-06-29-mapkit-search-places-design.md`

---

## Summary

Implement `mapkit.search_nearby` MCP tool: search for **points of interest near a coordinate or region** via **`MKLocalSearch`** with `pointOfInterestFilter` and `resultTypes = .pointOfInterest` (no natural-language query). Returns the **same exhaustive `MKLocalSearch.Response` JSON projection** as `search_places` (reuse `MapKitSerialization`). Register in Rust tool catalog gated by existing **`mapkit.search`** capability (already shipped with #104). Enforce **CoreLocation when-in-use** authorization per MapKit foundation (#150).

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `mapkit.search_nearby` |
| Capability | `mapkit.search` |
| Provider | `mapkit` |
| Operation | `search_nearby` |

### MapKit API choice

Use **`MKLocalSearch`** with **`MKLocalSearch.Request`** — same transport as `search_places`, different request shape:

| MCP argument | Apple API |
|--------------|-----------|
| `region` **or** `coordinate` | `request.region` (`MKCoordinateRegion`) |
| `radius_meters` (with `coordinate`) | Converts coordinate → region via `MKCoordinateRegion(center:latitudinalMeters:longitudinalMeters:)` |
| `including_categories` (optional) | `request.pointOfInterestFilter` (`MKPointOfInterestFilter`) |
| `excluding_categories` (optional) | `request.pointOfInterestFilter` (`MKPointOfInterestFilter`) |

Fixed request fields (not MCP arguments):

| Apple field | Value |
|-------------|-------|
| `naturalLanguageQuery` | **unset** (POI-only nearby search) |
| `resultTypes` | `.pointOfInterest` |
| `regionPriority` | `.required` (search area is explicit) |

`MKLocalSearch.start()` runs asynchronously; the provider blocks on the main actor using the existing **RunLoop pump** pattern (`MapKitSearchFetch.waitForCompletion`) — same synchronous FFI contract as `search_places`.

Do **not** use `CLGeocoder`, `MKLocalPointsOfInterestRequest`, or server-side APIs; MapKit remains the system of record and `MKLocalSearch` keeps one code path with `search_places`.

### Input schema (Rust `input_schema`)

Caller must supply **exactly one** geographic anchor: `region` **or** `coordinate` (mutually exclusive).

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `region` | object | one of `region` / `coordinate` | Search bounding box |
| `region.center.latitude` | number | if `region` | `[-90, 90]` |
| `region.center.longitude` | number | if `region` | `[-180, 180]` |
| `region.span.latitude_delta` | number | if `region` | `> 0` |
| `region.span.longitude_delta` | number | if `region` | `> 0` |
| `coordinate` | object | one of `region` / `coordinate` | Center point for nearby search |
| `coordinate.latitude` | number | if `coordinate` | `[-90, 90]` |
| `coordinate.longitude` | number | if `coordinate` | `[-180, 180]` |
| `radius_meters` | number | no | Used with `coordinate`; `> 0`; default **1000** when omitted |
| `including_categories` | string array | no | `MKPointOfInterestCategory.rawValue` strings |
| `excluding_categories` | string array | no | `MKPointOfInterestCategory.rawValue` strings |

Validation errors (Swift `invalid_arguments`):

| Condition | Message (representative) |
|-----------|--------------------------|
| Neither `region` nor `coordinate` | `"region or coordinate is required"` |
| Both `region` and `coordinate` | `"provide region or coordinate, not both"` |
| Invalid region / coordinate components | Same bounds messages as `search_places` region parsing |
| Unknown category raw value | `"including_categories value … is not recognized"` (or `excluding_categories`) |
| Empty category arrays when key present | `"including_categories must not be empty"` |

Rust JSON Schema documents all properties; **mutual-exclusion** is enforced in Swift (same pattern as other tools with conditional required fields).

### Output

Identical to `search_places` — JSON **object** mirroring `MKLocalSearch.Response`:

```json
{
  "map_items": [ /* exhaustive MKMapItem objects via MapKitSerialization */ ],
  "bounding_region": {
    "center": { "latitude": 0.0, "longitude": 0.0 },
    "span": { "latitude_delta": 0.0, "longitude_delta": 0.0 }
  }
}
```

`bounding_region` is `null` when Apple returns no region.

---

## Framework fidelity

**Reuse** `MapKitSerialization.mapItemJSONObject(from:)` and `MapKitSerialization.searchResponseJSONObject(mapItems:boundingRegion:)` from #104 — no new projection types. Every `map_items[]` element uses the exhaustive `MKMapItem` shape documented in `2026-06-29-mapkit-search-places-design.md`.

---

## Architecture

```
Rust tools/call → ProviderBridge → MapKitProvider.search_nearby
                                        ↓
                              MapKitStore (protocol)
                                        ↓
                         LiveMapKitStore / MockMapKitStore
                                        ↓
                    MKLocalSearch.start()  (POI filter + region)
```

### Swift files (new)

| File | Role |
|------|------|
| `AppleBridge/Providers/MapKit/MapKitProviderSearchArguments.swift` | Shared region/coordinate/POI-category argument parsing (extracted from `search_places`) |
| `AppleBridge/Providers/MapKit/MapKitProviderSearchNearby.swift` | `search_nearby` operation handler |
| `AppleBridgeTests/MapKitProviderSearchNearbyTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `AppleBridge/Providers/MapKit/MapKitStore.swift` | Add `MapKitSearchNearbyRequest` + `searchNearby(request:)` |
| `AppleBridge/Providers/MapKit/LiveMapKitStore.swift` | `MKLocalSearch` POI-nearby wrapper |
| `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift` | Dispatch `search_nearby` |
| `AppleBridge/Providers/MapKit/MapKitProviderSearchPlaces.swift` | Use shared argument helpers |
| `AppleBridgeTests/MockMapKitStore.swift` | Fake nearby results + `lastNearbyRequest` |
| `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift` | Success path for `search_nearby` |
| `README.md` | Check off `mapkit.search_nearby` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/apple_bridge_core/src/tools/mod.rs` | `TOOL_SEARCH_NEARBY`, registration, input schema, unit tests; update `mapkit.search` tool-list test to expect **both** search tools |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

**No changes** to `capabilities.rs` or `CapabilityCatalog.swift` — `mapkit.search` already shipped with #104.

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` when `mapkit.search` is enabled (same as `search_places`) |
| Apple location | `MapKitProvider.isLocationAuthorized` before `MKLocalSearch` |
| Settings | Existing `mapkit-search` toggle; no new capability tree entry |

| Condition | Error code |
|-----------|------------|
| Location not authorized | `permission_denied` |
| Invalid JSON / bad arguments | `invalid_arguments` |
| `MKLocalSearch` failure | `mapkit_error` |
| Serialization failure | `mapkit_error` |

---

## Acceptance criteria (#105)

1. `mapkit.search_nearby` in `tools/list` when `mapkit.search` enabled (alongside `mapkit.search_places`).
2. Valid `tools/call` succeeds against mock/live MapKit per tests.
3. Disabled capability or missing location permission → typed error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): grant Location, enable MapKit Search in Settings, call tool with `"coordinate": {"latitude": 37.3346, "longitude": -122.0090}, "including_categories": ["MKPOICategoryRestaurant"]`.