# mapkit_forward_geocode MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Draft  
**Issue:** #107 (Epic #103; second geocode tool — reuses shipped `mapkit.geocode` capability)  
**Branch:** `feat/mapkit-forward-geocode`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-29-mapkit-permissions-foundation-design.md`  
**Sibling:** `docs/superpowers/specs/2026-06-30-mapkit-reverse-geocode-design.md` (#106; shared `MapKitSerialization`, `mapkit.geocode` capability)

---

## Summary

Implement `mapkit_forward_geocode` MCP tool: resolve an **address string to nearby place representations** via **`MKGeocodingRequest`**. Returns **exhaustive `MKMapItem` JSON projection** (reuse `MapKitSerialization`). Register in Rust tool catalog gated by existing **`mapkit.geocode`** capability (already shipped in #106). Enforce **CoreLocation when-in-use** authorization per MapKit foundation (#150).

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `mapkit_forward_geocode` |
| Capability | `mapkit.geocode` |
| Provider | `mapkit` |
| Operation | `forward_geocode` |

### MapKit API choice

Use **`MKGeocodingRequest`** (MapKit geocoding API, macOS 26 SDK):

| MCP argument | Apple API |
|--------------|-----------|
| `address` | `MKGeocodingRequest(addressString:)` via `initWithAddressString:` |
| `region` (optional) | `MKGeocodingRequest.region` (`MKCoordinateRegion`) |
| `preferred_locale` (optional) | `MKGeocodingRequest.preferredLocale` (`NSLocale`) |

macOS 26 SDK (`MKGeocodingRequest.h`) exposes `-initWithAddressString:` / `init(addressString:)` as the sole initializer — there is no coordinate-only forward-geocode entry point. The MCP tool is address-string-first; optional `region` supplies geographic bias per Apple's assignable `region` property.

`mapItems` is an async property; the provider blocks on the main actor using the existing **RunLoop pump** pattern (`MapKitSearchFetch.waitForCompletion`) with a `@MainActor` `Task` — same synchronous FFI contract as `reverse_geocode` / `search_places`.

Do **not** use `CLGeocoder` or server-side APIs; MapKit remains the system of record (distinct from planned `location.forward_geocode` under a future CoreLocation provider).

### Input schema (Rust `input_schema`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `address` | string (`minLength: 1`) | **yes** | Address or place string to forward-geocode |
| `region` | object | no | Geographic bias (`MKCoordinateRegion`) |
| `region.center.latitude` | number | if `region` | `[-90, 90]` |
| `region.center.longitude` | number | if `region` | `[-180, 180]` |
| `region.span.latitude_delta` | number | if `region` | `> 0` |
| `region.span.longitude_delta` | number | if `region` | `> 0` |
| `preferred_locale` | string | no | BCP 47 / `NSLocale` identifier (e.g. `en_US`); omit for system default |

Validation errors (Swift `invalid_arguments`):

| Condition | Message (representative) |
|-----------|--------------------------|
| Missing / null `address` | `"address is required"` |
| `address` not a string | `"address must be a string"` |
| Whitespace-only `address` | `"address must not be empty"` |
| Invalid `region` shape | Same region messages as `search_places` |
| Invalid `preferred_locale` | `"preferred_locale must be a string or null"` |
| Empty payload | `"address is required"` |

Reuse `optionalRegionArgument(in:)` from `MapKitProviderSearchArguments.swift`. Add `requiredAddressArgument(in:)` mirroring `requiredQueryArgument(in:)` from `MapKitProviderSearchPlaces.swift`.

### Output

JSON **object** with forward-geocoded map items (no bounding region — `MKGeocodingRequest` does not return `MKLocalSearch.Response`):

```json
{
  "map_items": [ /* exhaustive MKMapItem objects via MapKitSerialization */ ]
}
```

Every `map_items[]` element uses the exhaustive `MKMapItem` shape documented in `2026-06-29-mapkit-search-places-design.md`. An empty array is a valid success when Apple returns no matches.

---

## Framework fidelity

**Reuse** `MapKitSerialization.mapItemJSONObject(from:)` from #104 — no new projection types.

**Reuse** `MapKitSerialization.reverseGeocodeResponseJSONObject(mapItems:)` for the response envelope (`{ "map_items": [...] }` is identical for forward and reverse geocode). No serializer rename required in this issue.

---

## Architecture

```
Rust tools/call → ProviderBridge → MapKitProvider.forward_geocode
                                        ↓
                              MapKitStore (protocol)
                                        ↓
                         LiveMapKitStore / MockMapKitStore
                                        ↓
                    MKGeocodingRequest.mapItems
```

### Swift files (new)

| File | Role |
|------|------|
| `ABridge/Providers/MapKit/MapKitProviderForwardGeocode.swift` | `forward_geocode` operation handler |
| `ABridgeTests/MapKitProviderForwardGeocodeTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `ABridge/Providers/MapKit/MapKitStore.swift` | Add `MapKitForwardGeocodeRequest` + `forwardGeocode(request:)` |
| `ABridge/Providers/MapKit/LiveMapKitStore.swift` | `MKGeocodingRequest` blocking wrapper |
| `ABridge/Providers/MapKit/MapKitProviderRouting.swift` | Dispatch `forward_geocode` |
| `ABridgeTests/MockMapKitStore.swift` | Fake forward-geocode results + `lastForwardGeocodeRequest` |
| `ABridgeTests/AppleProviderBridgeMapKitTests.swift` | Success path for `forward_geocode` |
| `README.md` | Check off `mapkit_forward_geocode` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_FORWARD_GEOCODE`, registration, input schema, unit tests |
| `rust/abridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

### No changes required

| File | Reason |
|------|--------|
| `rust/abridge_core/src/capabilities.rs` | `MAPKIT_GEOCODE` shipped in #106 |
| `ABridge/Models/CapabilityCatalog.swift` | `mapkit-geocode` already `shipped: true` |
| `ABridgeTests/PermissionsStoreMapKitTests.swift` | Geocode toggle expectations covered in #106 |
| `ABridgeTests/AppSettingsMapKitTests.swift` | Server gating for `mapkit.geocode` covered in #106 |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `mapkit.geocode` is in server enabled capabilities |
| Apple location | `MapKitProvider.isLocationAuthorized` before `MKGeocodingRequest` |
| Settings | Existing `mapkit-geocode` shipped toggle; `serverEnabledMCPCapabilityIDs` includes `mapkit.geocode` when `locationAuthorized` (from #106) |

| Condition | Error code |
|-----------|------------|
| Location not authorized | `permission_denied` |
| Invalid JSON / bad arguments | `invalid_arguments` |
| `MKGeocodingRequest` failure | `mapkit_error` |
| Serialization failure | `mapkit_error` |

Rust: tool absent from `tools/list` when `mapkit.geocode` not enabled; `tools/call` with disabled capability returns typed MCP error without provider dispatch (existing pattern).

When `mapkit.geocode` is enabled, `tools/list` includes **both** `mapkit_reverse_geocode` and `mapkit_forward_geocode`.

---

## Acceptance criteria (#107)

1. `mapkit_forward_geocode` in `tools/list` when `mapkit.geocode` enabled.
2. Valid `tools/call` succeeds against mock/live MapKit per tests.
3. Disabled capability or missing location permission → typed error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): grant Location, enable MapKit Geocode in Settings, call tool with `"address": "1 Apple Park Way, Cupertino, CA"`.