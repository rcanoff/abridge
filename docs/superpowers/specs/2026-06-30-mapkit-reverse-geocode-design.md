# mapkit.reverse_geocode MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Approved  
**Issue:** #106 (Epic #103; first geocode tool — ships `mapkit.geocode` capability)  
**Branch:** `feat/mapkit-reverse-geocode`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-29-mapkit-permissions-foundation-design.md`  
**Sibling:** `docs/superpowers/specs/2026-06-29-mapkit-search-places-design.md` (shared `MapKitSerialization`)

---

## Summary

Implement `mapkit.reverse_geocode` MCP tool: resolve a **coordinate to nearby address representations** via **`MKReverseGeocodingRequest`**. Returns **exhaustive `MKMapItem` JSON projection** (reuse `MapKitSerialization`). Register in Rust tool catalog gated by new **`mapkit.geocode`** capability. Flip `mapkit-geocode` capability to **`shipped: true`**. Enforce **CoreLocation when-in-use** authorization per MapKit foundation (#150).

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `mapkit.reverse_geocode` |
| Capability | `mapkit.geocode` |
| Provider | `mapkit` |
| Operation | `reverse_geocode` |

### MapKit API choice

Use **`MKReverseGeocodingRequest`** (MapKit geocoding API, macOS 26 SDK):

| MCP argument | Apple API |
|--------------|-----------|
| `coordinate.latitude` / `coordinate.longitude` | `MKReverseGeocodingRequest(coordinate:)` |

`mapItems` is an async property; the provider blocks on the main actor using the existing **RunLoop pump** pattern (`MapKitSearchFetch.waitForCompletion`) with a `@MainActor` `Task` — same synchronous FFI contract as `search_places` / `search_nearby`.

Do **not** use `CLGeocoder` or server-side APIs; MapKit remains the system of record (distinct from planned `location.reverse_geocode` under a future CoreLocation provider).

### Input schema (Rust `input_schema`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `coordinate` | object | **yes** | Geographic point to reverse-geocode |
| `coordinate.latitude` | number | yes | `[-90, 90]` |
| `coordinate.longitude` | number | yes | `[-180, 180]` |

Validation errors (Swift `invalid_arguments`):

| Condition | Message (representative) |
|-----------|--------------------------|
| Missing / null `coordinate` | `"coordinate is required"` |
| `coordinate` not an object | `"coordinate must be an object"` |
| Missing / invalid latitude or longitude | Same bounds messages as `search_nearby` coordinate parsing |
| Empty payload | `"coordinate is required"` |

Reuse `requiredCoordinateArgument(in:)` from `MapKitProviderSearchArguments.swift`.

### Output

JSON **object** with reverse-geocoded map items (no bounding region — `MKReverseGeocodingRequest` does not return `MKLocalSearch.Response`):

```json
{
  "map_items": [ /* exhaustive MKMapItem objects via MapKitSerialization */ ]
}
```

Every `map_items[]` element uses the exhaustive `MKMapItem` shape documented in `2026-06-29-mapkit-search-places-design.md`. An empty array is a valid success when Apple returns no matches.

---

## Framework fidelity

**Reuse** `MapKitSerialization.mapItemJSONObject(from:)` from #104 — no new projection types.

Add **`MapKitSerialization.reverseGeocodeResponseJSONObject(mapItems:)`** returning `{ "map_items": [...] }`.

---

## Architecture

```
Rust tools/call → ProviderBridge → MapKitProvider.reverse_geocode
                                        ↓
                              MapKitStore (protocol)
                                        ↓
                         LiveMapKitStore / MockMapKitStore
                                        ↓
                    MKReverseGeocodingRequest.mapItems
```

### Swift files (new)

| File | Role |
|------|------|
| `AppleBridge/Providers/MapKit/MapKitProviderReverseGeocode.swift` | `reverse_geocode` operation handler |
| `AppleBridgeTests/MapKitProviderReverseGeocodeTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `AppleBridge/Providers/MapKit/MapKitStore.swift` | Add `MapKitReverseGeocodeRequest` + `reverseGeocode(request:)` |
| `AppleBridge/Providers/MapKit/LiveMapKitStore.swift` | `MKReverseGeocodingRequest` blocking wrapper |
| `AppleBridge/Providers/MapKit/MapKitSerialization.swift` | `reverseGeocodeResponseJSONObject(mapItems:)` |
| `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift` | Dispatch `reverse_geocode` |
| `AppleBridge/Models/CapabilityCatalog.swift` | `mapkit-geocode` → `shipped: true` |
| `AppleBridgeTests/MockMapKitStore.swift` | Fake reverse-geocode results + `lastReverseGeocodeRequest` |
| `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift` | Success path for `reverse_geocode` |
| `AppleBridgeTests/PermissionsStoreMapKitTests.swift` | Expect `mapkit-geocode` shipped |
| `AppleBridgeTests/AppSettingsMapKitTests.swift` | Server gating includes `mapkit.geocode` when location authorized |
| `README.md` | Check off `mapkit.reverse_geocode` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/apple_bridge_core/src/capabilities.rs` | `MAPKIT_GEOCODE` constant + `is_allowed_in_v1` |
| `rust/apple_bridge_core/src/tools/mod.rs` | `TOOL_REVERSE_GEOCODE`, registration, input schema, unit tests |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `mapkit.geocode` is in server enabled capabilities |
| Apple location | `MapKitProvider.isLocationAuthorized` before `MKReverseGeocodingRequest` |
| Settings | `mapkit-geocode` shipped → `requiresAppleLocationAccess` true when toggle checked; `AppSettings.serverEnabledMCPCapabilityIDs` includes `mapkit.geocode` only when `locationAuthorized` |

| Condition | Error code |
|-----------|------------|
| Location not authorized | `permission_denied` |
| Invalid JSON / bad arguments | `invalid_arguments` |
| `MKReverseGeocodingRequest` failure | `mapkit_error` |
| Serialization failure | `mapkit_error` |

Rust: tool absent from `tools/list` when `mapkit.geocode` not enabled; `tools/call` with disabled capability returns typed MCP error without provider dispatch (existing pattern).

---

## Acceptance criteria (#106)

1. `mapkit.reverse_geocode` in `tools/list` when `mapkit.geocode` enabled.
2. Valid `tools/call` succeeds against mock/live MapKit per tests.
3. Disabled capability or missing location permission → typed error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `mapkit-geocode` capability shipped in Settings catalog.
6. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): grant Location, enable MapKit Geocode in Settings, call tool with `"coordinate": {"latitude": 37.3346, "longitude": -122.0090}`.