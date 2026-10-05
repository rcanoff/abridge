# mapkit.search_places MCP Tool — Design Spec

**Date:** 2026-06-29  
**Status:** Approved  
**Issue:** #104 (Epic #103; depends on #150 MapKit permissions foundation)  
**Branch:** `feat/mapkit-search-places`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-29-mapkit-permissions-foundation-design.md`

---

## Summary

Implement `mapkit.search_places` MCP tool: natural-language place search via **`MKLocalSearch`**. Returns **exhaustive `MKMapItem` JSON projection** (mechanical snake_case serialization, shared serializer for future MapKit read tools). Register in Rust tool catalog gated by **`mapkit.search`**. Flip `mapkit-search` capability to **`shipped: true`**. Enforce **CoreLocation when-in-use** authorization per MapKit foundation (#150).

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `mapkit.search_places` |
| Capability | `mapkit.search` |
| Provider | `mapkit` |
| Operation | `search_places` |

### MapKit API choice

Use **`MKLocalSearch`** with **`MKLocalSearch.Request`**:

| MCP argument | Apple API |
|--------------|-----------|
| `query` | `request.naturalLanguageQuery` |
| `region` (optional) | `request.region` (`MKCoordinateRegion`) |
| `region_priority` (optional) | `request.regionPriority` (`MKLocalSearchRegionPriority`) |
| `result_types` (optional) | `request.resultTypes` (`MKLocalSearchResultType` bitmask) |

`MKLocalSearch.start()` runs asynchronously; the provider blocks on the main actor using the existing **RunLoop pump** pattern (`EventKitReminderFetch.pumpRunLoop`) until completion or timeout — same synchronous FFI contract as other providers.

Do **not** use `CLGeocoder` or server-side APIs; MapKit remains the system of record.

### Input schema (Rust `input_schema`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `query` | string (`minLength: 1`) | **yes** | Natural-language search string |
| `region` | object | no | Geographic bias |
| `region.center.latitude` | number | if `region` | `[-90, 90]` |
| `region.center.longitude` | number | if `region` | `[-180, 180]` |
| `region.span.latitude_delta` | number | if `region` | `> 0` |
| `region.span.longitude_delta` | number | if `region` | `> 0` |
| `region_priority` | string enum | no | `default` (default), `required` |
| `result_types` | string array | no | Subset of `address`, `point_of_interest`, `query`, `physical_feature`, `physical_feature_query`; omit for Apple default |

Empty/missing `query` or whitespace-only → Swift `invalid_arguments` (`"query is required"` / `"query must not be empty"`).

### Output

JSON **object** mirroring `MKLocalSearch.Response` (not a bare array):

```json
{
  "map_items": [ /* exhaustive MKMapItem objects */ ],
  "bounding_region": {
    "center": { "latitude": 0.0, "longitude": 0.0 },
    "span": { "latitude_delta": 0.0, "longitude_delta": 0.0 }
  }
}
```

`bounding_region` is `null` when Apple returns no region (serialize keys with `null` values per fidelity rules).

---

## Framework fidelity (`MKMapItem`)

Define **`MapKitSerialization.mapItemJSONObject(from:)`** once; reuse for `search_nearby`, `lookup_place`, routing tools.

Every `map_items[]` element includes **all serializable `MKMapItem` properties** (macOS 26 SDK), snake_case keys, `null` for absent optionals — never omit keys.

### `MKMapItem` top-level keys

| Key | Source | Encoding |
|-----|--------|----------|
| `name` | `MKMapItem.name` | string or null |
| `phone_number` | `MKMapItem.phoneNumber` | string or null |
| `url` | `MKMapItem.url` | absolute URL string or null |
| `time_zone` | `MKMapItem.timeZone` | identifier string or null |
| `point_of_interest_category` | `MKMapItem.pointOfInterestCategory` | raw value string or null |
| `is_current_location` | `MKMapItem.isCurrentLocation` | boolean |
| `identifier` | `MKMapItem.identifier` (when available) | raw value string or null |
| `location` | `MKMapItem.location` | `CLLocation` object or null |
| `placemark` | `MKMapItem.placemark` | `MKPlacemark` object (legacy; still projected) |
| `address` | `MKMapItem.address` (when available) | `MKAddress` object or null |
| `address_representations` | `MKMapItem.addressRepresentations` | array of objects or null |

### Nested `CLLocation` (`location`)

`coordinate` (`latitude`, `longitude`), `altitude`, `horizontal_accuracy`, `vertical_accuracy`, `course`, `speed`, `timestamp` (ISO 8601), `floor` (when available) — all keys present, null when unavailable.

### Nested `MKPlacemark` (`placemark`)

`coordinate`, `altitude`, `ellipsoidal_altitude`, `region` (`CLCircularRegion`: `center`, `radius`, `identifier`), `time_zone`, `country_code`, `inland_water`, `ocean`, `areas_of_interest`, `postal_address` (exhaustive `CNPostalAddress` via shared helper), `address_dictionary` (when non-nil: mechanical key/value projection).

### Nested `MKAddress` / `MKAddressRepresentation`

Project every readable property Apple exposes on macOS 26 (e.g. `full_address`, `short_address`, `region`, `sub_region`, `city`, `sub_city`, `street`, `sub_street`, `postal_code`, `country`, `country_code`, `formatted_address_lines`, `representations` metadata). When a property is unavailable on the deployment target, include the key with `null` and document in serializer tests.

### `MKCoordinateRegion` (`bounding_region`)

`center.latitude`, `center.longitude`, `span.latitude_delta`, `span.longitude_delta`.

---

## Architecture

```
Rust tools/call → ProviderBridge → MapKitProvider.search_places
                                        ↓
                              MapKitStore (protocol)
                                        ↓
                         LiveMapKitStore / MockMapKitStore
                                        ↓
                              MKLocalSearch.start()
```

### Swift files (new)

| File | Role |
|------|------|
| `ABridge/Providers/MapKit/MapKitSerialization.swift` | Exhaustive MapKit type → JSON |
| `ABridge/Providers/MapKit/MapKitStore.swift` | Protocol + authorization seam |
| `ABridge/Providers/MapKit/LiveMapKitStore.swift` | `MKLocalSearch` wrapper |
| `ABridge/Providers/MapKit/MapKitProviderSearchPlaces.swift` | Operation handler |
| `ABridge/Providers/MapKit/MapKitProviderRouting.swift` | `handle(operation:)` dispatch |
| `ABridgeTests/MockMapKitStore.swift` | Fake search results for CI |
| `ABridgeTests/MapKitSerializationTests.swift` | Projection completeness |
| `ABridgeTests/MapKitProviderSearchPlacesTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `ABridge/Providers/MapKit/MapKitProvider.swift` | Store + location permission injection; remove stub-only body |
| `ABridge/Models/CapabilityCatalog.swift` | `mapkit-search` → `shipped: true` |
| `ABridgeTests/AppleProviderBridgeMapKitTests.swift` | Success path with mock provider |
| `README.md` | Check off `mapkit.search_places` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/abridge_core/src/capabilities.rs` | `MAPKIT_SEARCH` constant + `is_allowed_in_v1` |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_SEARCH_PLACES`, registration, input schema, unit tests |
| `rust/abridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `mapkit.search` is in server enabled capabilities |
| Apple location | `MapKitProvider` checks `LocationPermissionStatus.grantsReadAccess` (injectable `LocationPermissionChecking` or `CLLocationManager.authorizationStatus` via store seam) before calling `MKLocalSearch` |
| Settings | `mapkit-search` shipped → `requiresAppleLocationAccess` true; `AppSettings.serverEnabledMCPCapabilityIDs` includes `mapkit.search` only when `locationAuthorized` |

| Condition | Error code |
|-----------|------------|
| Location not authorized | `permission_denied` |
| Invalid JSON / missing query | `invalid_arguments` |
| `MKLocalSearch` failure | `mapkit_error` |
| Serialization failure | `mapkit_error` |

Rust: tool absent from `tools/list` when `mapkit.search` not enabled; `tools/call` with disabled capability returns typed MCP error without provider dispatch (existing pattern).

---

## Acceptance criteria (#104)

1. `mapkit.search_places` in `tools/list` when `mapkit.search` enabled.
2. Valid `tools/call` succeeds against mock/live MapKit per tests.
3. Disabled capability or missing location permission → typed error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): grant Location, enable MapKit Search in Settings, call tool with `"query": "coffee near Cupertino"`.