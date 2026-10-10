# mapkit_open_navigation MCP Tool — Design Spec

**Date:** 2026-06-30  
**Status:** Draft  
**Issue:** #110 (Epic #103; first navigation tool — ships `mapkit.navigation` capability)  
**Branch:** `feat/mapkit-open-navigation`  
**PRD:** `docs/prd.md` § Future Providers  
**Conventions:** `docs/conventions.md` § JSON and payloads (framework fidelity)  
**Foundation:** `docs/superpowers/specs/2026-06-29-mapkit-permissions-foundation-design.md`  
**Sibling:** `mapkit_calculate_route` (#108; routing sibling under separate capability)

---

## Summary

Implement `mapkit_open_navigation` MCP tool: open **Apple Maps** turn-by-turn navigation between source and destination coordinates via **`MKMapItem.openMaps(with:launchOptions:)`** (user-visible system action). Returns confirmation JSON with exhaustive `MKMapItem` projection for source/destination and the launch options applied. Register in Rust tool catalog gated by new **`mapkit.navigation`** capability. Flip `mapkit-navigation` capability to **`shipped: true`**. Enforce **CoreLocation when-in-use** authorization per MapKit foundation (#150).

---

## Tool contract

| Field | Value |
|-------|-------|
| MCP name | `mapkit_open_navigation` |
| Capability | `mapkit.navigation` |
| Provider | `mapkit` |
| Operation | `open_navigation` |

### MapKit API choice

Use **`MKMapItem.openMaps(with:launchOptions:)`**:

| MCP argument | Apple API |
|--------------|-----------|
| `source.coordinate` | `MKMapItem` from `MKPlacemark(coordinate:)` — first map item (route origin) |
| `destination.coordinate` | `MKMapItem` from `MKPlacemark(coordinate:)` — second map item (route terminus) |
| `transport_type` (optional) | `MKLaunchOptionsDirectionsModeKey` in `launchOptions` (`MKLaunchOptionsDirectionsMode*`) |

Synchronous call on the main actor; no async MapKit callback. Same FFI contract as other MapKit providers.

Do **not** use third-party navigation APIs; MapKit/Maps remains the system of record.

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

Validation errors (Swift `invalid_arguments`):

| Condition | Message (representative) |
|-----------|--------------------------|
| Missing / null `source` or `destination` | `"source is required"` / `"destination is required"` |
| Missing coordinate | `"source.coordinate is required"` / `"destination.coordinate is required"` |
| Invalid coordinate shape | Same coordinate messages as `reverse_geocode` |
| Invalid `transport_type` | `"transport_type must be one of: automobile, walking, transit, cycling, any"` |

Reuse nested coordinate parsing pattern from `MapKitProviderCalculateRoute.swift`.

### Output

JSON **object** confirming the navigation launch:

```json
{
  "opened": true,
  "source": { /* exhaustive MKMapItem via MapKitSerialization */ },
  "destination": { /* exhaustive MKMapItem */ },
  "transport_type": ["automobile"],
  "launch_options": {
    "directions_mode": "Driving"
  }
}
```

When `transport_type` is `any`, `launch_options` is `null` (Maps chooses default mode).

`directions_mode` uses Apple's `MKLaunchOptionsDirectionsMode*` string constants (`Driving`, `Walking`, `Transit`, `Cycling`).

---

## Framework fidelity

### Reuse

- **`MapKitSerialization.mapItemJSONObject(from:)`** for `source` and `destination`.
- **`transportTypeJSONArray(from:)`** for `transport_type`.

### New serializers

| Function | Source type |
|----------|-------------|
| `openNavigationResponseJSONObject(result:)` | `MapKitOpenNavigationResult` (store seam) |

### Response keys (snake_case)

`opened`, `source`, `destination`, `transport_type`, `launch_options` (object with `directions_mode` or `null`).

---

## Architecture

```
Rust tools/call → ProviderBridge → MapKitProvider.open_navigation
                                        ↓
                              MapKitStore (protocol)
                                        ↓
                         LiveMapKitStore / MockMapKitStore
                                        ↓
                    MKMapItem.openMaps(with:launchOptions:)
```

`MapKitOpenNavigationResult` is a **store seam type**. `LiveMapKitStore` performs the Maps launch and records launch options; `MapKitSerialization` projects seam type to fidelity JSON.

### Swift files (new)

| File | Role |
|------|------|
| `ABridge/Providers/MapKit/MapKitProviderOpenNavigation.swift` | `open_navigation` operation handler |
| `ABridgeTests/MapKitProviderOpenNavigationTests.swift` | Provider end-to-end tests |

### Swift files (modify)

| File | Change |
|------|--------|
| `ABridge/Providers/MapKit/MapKitStore.swift` | Request/result seam types + `openNavigation(request:)` |
| `ABridge/Providers/MapKit/LiveMapKitStore.swift` | `MKMapItem.openMaps` wrapper |
| `ABridge/Providers/MapKit/MapKitSerialization.swift` | Open-navigation response serializer |
| `ABridge/Providers/MapKit/MapKitProviderRouting.swift` | Dispatch `open_navigation` |
| `ABridge/Models/CapabilityCatalog.swift` | `mapkit-navigation` → `shipped: true` |
| `ABridgeTests/MockMapKitStore.swift` | Fake open-navigation results + `lastOpenNavigationRequest` |
| `ABridgeTests/AppleProviderBridgeMapKitTests.swift` | Success path for `open_navigation` |
| `ABridgeTests/AppSettingsMapKitTests.swift` | Server gating for `mapkit.navigation` |
| `ABridgeTests/PermissionsStoreMapKitTests.swift` | Location requirement for navigation toggle |
| `README.md` | Check off `mapkit_open_navigation` |

### Rust files (modify)

| File | Change |
|------|--------|
| `rust/abridge_core/src/capabilities.rs` | `MAPKIT_NAVIGATION` constant + v1 allowlist |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_OPEN_NAVIGATION`, registration, input schema, unit tests |
| `rust/abridge_core/tests/mcp_protocol.rs` | `tools/list` + `tools/call` integration tests |

---

## Permission and capability gating

| Layer | Behavior |
|-------|----------|
| MCP capability | Tool appears in `tools/list` only when `mapkit.navigation` is in server enabled capabilities |
| Apple location | `MapKitProvider.isLocationAuthorized` before opening Maps |
| Settings | `mapkit-navigation` shipped toggle; `serverEnabledMCPCapabilityIDs` includes `mapkit.navigation` when `locationAuthorized` |

| Condition | Error code |
|-----------|------------|
| Location not authorized | `permission_denied` |
| Invalid JSON / bad arguments | `invalid_arguments` |
| Maps launch failure | `mapkit_error` |
| Serialization failure | `mapkit_error` |

---

## Acceptance criteria (#110)

1. `mapkit_open_navigation` in `tools/list` when `mapkit.navigation` enabled.
2. Valid `tools/call` succeeds against mock/live MapKit per tests.
3. Disabled capability or missing location permission → typed error (not silent success).
4. Responses use exhaustive Apple field projection (snake_case keys).
5. `mapkit-navigation` capability shipped in Settings.
6. `just test-all` passes.

## Verification

```sh
TZ=UTC just test-all
TZ=UTC just ci
```

Manual (not CI-gating): grant Location, enable MapKit Navigation in Settings, call tool with Cupertino→San Francisco coordinates; Apple Maps opens with directions.