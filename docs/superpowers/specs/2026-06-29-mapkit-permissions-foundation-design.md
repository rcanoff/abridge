# MapKit Location Permission & MCP Capability Foundation — Design Spec

**Date:** 2026-06-29  
**Status:** Superseded. Location Access now gates only the Core Location provider (`corelocation_get_current_location`); MapKit tools need no macOS permission.  
**Issue:** #150 (Epic #103, first in MapKit merge order)  
**Branch:** `feat/mapkit-permissions-foundation`  
**PRD:** `docs/prd.md` § Future Providers, § User Interface — Permissions  
**Architecture:** `docs/architecture-bootstrap-guide.md`  
**Reference:** `docs/superpowers/specs/2026-06-29-contacts-permissions-foundation-design.md`, `docs/superpowers/specs/2026-06-29-issue-149-calendars-events-apple-permission-design.md`

---

## Summary

Establish **MapKit / CoreLocation Apple permission** and **MCP capability scaffolding** before any `mapkit.*` MCP tool ships. Mirrors the two-layer permission model used for Contacts and EventKit: macOS location TCC access plus per-capability MCP toggles in Settings.

No MCP tools or Rust tool registration in this subtask — only permission plumbing, capability catalog entries (unshipped), Settings UI, and a `MapKitProvider` routing stub.

CoreLocation streaming (`location.start_updates` / continuous updates) is **out of scope**.

---

## Goals

1. Permissions tab shows **Location Access** under **Apple Permissions** with correct granted/denied/not-determined states.
2. User can request when-in-use location access from Settings; denied state links to System Settings.
3. MCP Permissions shows **MapKit** capability group; toggles persist.
4. Enabling a shipped mapkit MCP capability without Apple location permission does **not** apply capabilities to the server.
5. `MapKitProvider` skeleton routes through `AppleProviderBridge` with `unknown_operation` until tools land.
6. `just test-swift` passes including permission service unit tests (mocked `CLAuthorizationStatus`; no live dialog in CI).

## Non-goals

- Individual `mapkit.*` MCP tools (sibling sub-issues #104+)
- Rust tool registration or capability constants in `rust/abridge_core`
- CoreLocation streaming provider or `location.*` tools
- Menu bar popover location status
- MapKit search/geocode/route JSON projection (deferred to tool subtasks)
- In-app map UI

---

## Two-layer permission model (MapKit / Location)

### Layer 1 — Apple (macOS TCC)

| Element | Behavior |
|---------|----------|
| Framework | `CoreLocation` (`CLLocationManager`) |
| Usage string | `NSLocationUsageDescription` in `project.yml` (`INFOPLIST_KEY_NSLocationUsageDescription`) |
| Status source | `CLLocationManager().authorizationStatus` |
| Request | `CLLocationManager().requestWhenInUseAuthorization()` (delegate callback) |
| Granted | `.authorized` or `.authorizedAlways` → `LocationPermissionStatus` → `grantsReadAccess == true` |
| System Settings | `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices` |

**API choice:** `LocationPermissionChecking` / `LocationPermissionService` (not `MapKitPermissionService`). MapKit geocoding/search may not always need GPS, but this foundation uses **CoreLocation when-in-use** as the single Apple permission gate for the MapKit provider group — matching how Contacts gates the entire `contacts.*` family on one TCC grant.

`LocationPermissionStatus` enum mirrors `ContactsPermissionStatus` shape but maps `CLAuthorizationStatus`.

Session reconciliation mirrors Contacts: after `requestAccess()`, retain a session grant when EventKit/CoreLocation returns `.notDetermined` briefly post-dialog.

### Layer 2 — MCP capabilities (app)

| Toggle ID | Capability ID | Label | Shipped | Future MCP tools (README) |
|-----------|---------------|-------|---------|---------------------------|
| `mapkit-search` | `mapkit.search` | Search | `false` | `mapkit_search_places`, `mapkit_search_nearby` |
| `mapkit-geocode` | `mapkit.geocode` | Geocode | `false` | `mapkit_reverse_geocode`, `mapkit_forward_geocode` |
| `mapkit-routing` | `mapkit.routing` | Routing | `false` | `mapkit_calculate_route`, `mapkit_estimate_travel_time` |
| `mapkit-navigation` | `mapkit.navigation` | Navigation | `false` | `mapkit_open_navigation` |
| `corelocation-read` | `corelocation.read` | Location | `false` | `corelocation_get_current_location` |
| `mapkit-read` | `mapkit.read` | Read | `false` | `mapkit_get_place` |

`shipped: false` until sibling MCP tool subtasks land. Toggles persist in `AppSettings.savedCapabilityIDs` but do not reach the server until shipped **and** Apple location permission granted.

Capability IDs follow `docs/conventions.md` provider naming (`mapkit.search`, `mapkit.read`, etc.).

---

## Components

### New Swift files

| File | Responsibility |
|------|----------------|
| `ABridge/Models/LocationPermissionStatus.swift` | Status enum + `CLAuthorizationStatus` mapper |
| `ABridge/Services/LocationPermissionChecking.swift` | Protocol |
| `ABridge/Services/LocationPermissionService.swift` | Live service with injectable status/request handlers |
| `ABridge/Providers/MapKit/MapKitProvider.swift` | Thin stub: returns `unknown_operation` for all ops |
| `ABridgeTests/LocationPermissionServiceTests.swift` | Unit tests with mocked handlers |
| `ABridgeTests/LocationPermissionStatusTests.swift` | Mapper tests |
| `ABridgeTests/MockLocationPermissionService.swift` | Test double |
| `ABridgeTests/AppleProviderBridgeMapKitTests.swift` | Bridge routes `mapkit` provider |
| `ABridgeTests/AppSettingsMapKitTests.swift` | MapKit capability gating tests |
| `ABridgeTests/PermissionsStoreMapKitTests.swift` | MapKit gating tests |

### Modified Swift files

| File | Change |
|------|--------|
| `project.yml` | Add `INFOPLIST_KEY_NSLocationUsageDescription` |
| `ABridge/Models/CapabilityCatalog.swift` | Add `mapkitCapabilities` |
| `ABridge/Models/AppSettings.swift` | `enabledMapKitCapabilityIDs`, extend `serverEnabledMCPCapabilityIDs(locationAuthorized:)` |
| `ABridge/Models/PermissionsStore.swift` | `requiresAppleLocationAccess`, extend `shouldApplySavedCapabilitiesAfterToggle` |
| `ABridge/Models/SettingsStore.swift` | Inject `locationPermissionService`; thread `locationAuthorized` through `applySavedCapabilities` / `serverEnabledCapabilities` |
| `ABridge/Models/AppStore.swift` | Location permission status, request, open System Settings |
| `ABridge/Views/Settings/PermissionsSettingsView.swift` | Location Apple row + MapKit MCP group; reapply on authorization change |
| `ABridge/Providers/AppleProviderBridge.swift` | Route `provider == "mapkit"` to `MapKitProvider` |
| `ABridge/Services/ABridgeAppStoreMaking.swift` | Wire `LocationPermissionService` into stores |
| `ABridgeTests/SettingsStoreTests.swift` | `applySavedCapabilities` with `locationAuthorized` |
| `ABridgeTests/MockABridgeAppStoreMaker.swift` | Wire location service |
| `ABridgeTests/PermissionsStoreTests.swift` | Add `locationAuthorized` to existing toggle tests |
| `ABridgeTests/AppSettingsTests.swift` | Add `locationAuthorized` to existing gating tests |
| `ABridgeTests/AppStoreTests.swift` | Location permission flow tests (if present, extend) |

---

## Server capability gating

`AppSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized:eventsAuthorized:contactsAuthorized:locationAuthorized:)`:

- Always includes `diagnostics.read`
- Reminder capabilities when `remindersAuthorized`
- Calendar + event capabilities when `eventsAuthorized`
- Contacts capabilities when `contactsAuthorized`
- MapKit capabilities when `locationAuthorized` (only shipped + checked)

`PermissionsStore.shouldApplySavedCapabilitiesAfterToggle` returns `false` when enabling a shipped mapkit capability without `locationAuthorized`.

While all mapkit capabilities remain `shipped: false`, `requiresAppleLocationAccess` is `false` for any toggle (matches contacts-unshipped pattern).

---

## MapKitProvider stub

```swift
// provider: "mapkit"
// All operations return ProviderResponse(ok: false, errorJson: unknown_operation)
```

No business logic. Future subtasks add operations one at a time. Framework fidelity — no custom DTOs; tool subtasks serialize MapKit/CoreLocation types directly.

---

## Acceptance criteria (from #150)

1. Permissions tab shows Location Access under Apple Permissions with request + System Settings.
2. MCP Permissions shows MapKit group; toggles persist; respects authorization before server apply.
3. Enabling mapkit capability without Apple location permission does not silently enable server tools.
4. `just test-swift` passes with permission unit tests.

## Verification

```sh
xcodegen generate   # if project.yml changed
TZ=UTC just test-swift
TZ=UTC just ci      # full gate before review
```

Manual (not CI-gating): grant/deny Location in System Settings and confirm UI states.