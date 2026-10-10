# mapkit_calculate_route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `mapkit_calculate_route` MCP tool (#108) with exhaustive `MKDirectionsResponse` JSON projection under new `mapkit.routing` capability.

**Architecture:** Extend `MapKitStore` with `calculateRoute`; use `MKDirections` in `LiveMapKitStore`; map `MKDirectionsResponse` to seam types for mockability; add route serializers to `MapKitSerialization`; Rust tool registration on `mapkit.routing`; ship `mapkit-routing` toggle; CoreLocation when-in-use gate per #150.

**Tech Stack:** Rust (`abridge_core`), Swift 6 + MapKit + CoreLocation, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-mapkit-calculate-route-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/abridge_core/src/capabilities.rs` | `MAPKIT_ROUTING` constant + v1 allowlist |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_CALCULATE_ROUTE` registration + input schema |
| `rust/abridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `ABridge/Providers/MapKit/MapKitStore.swift` | Request/result seam types + protocol method |
| `ABridge/Providers/MapKit/LiveMapKitStore.swift` | `MKDirections` blocking wrapper |
| `ABridge/Providers/MapKit/MapKitSerialization.swift` | Route/step/polyline serializers |
| `ABridge/Providers/MapKit/MapKitProviderCalculateRoute.swift` | `calculate_route` handler |
| `ABridge/Providers/MapKit/MapKitProviderRouting.swift` | Operation dispatch |
| `ABridge/Models/CapabilityCatalog.swift` | Ship `mapkit-routing` |
| `ABridgeTests/MockMapKitStore.swift` | Calculate-route mock seam |
| `ABridgeTests/MapKitProviderCalculateRouteTests.swift` | Provider tests |
| `ABridgeTests/AppleProviderBridgeMapKitTests.swift` | Bridge routing test |
| `ABridgeTests/AppSettingsMapKitTests.swift` | Routing capability gating |
| `ABridgeTests/PermissionsStoreMapKitTests.swift` | Routing location requirement |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/abridge_core/src/capabilities.rs`
- Modify: `rust/abridge_core/src/tools/mod.rs`

- [ ] **Step 1:** Add `MAPKIT_ROUTING` to capabilities.rs + v1 allowlist + tests
- [ ] **Step 2:** Register `TOOL_CALCULATE_ROUTE` in tools/mod.rs (bump array 47 → 48)
- [ ] **Step 3:** Add input schema for source/destination coordinates + optional routing options
- [ ] **Step 4:** Add unit tests (`lists_calculate_route_tool_when_mapkit_routing_capability_enabled`, schema tests)
- [ ] **Step 5:** Run `TZ=UTC just test-rust`
- [ ] **Step 6:** Commit `feat(mapkit): register mapkit_calculate_route MCP tool in Rust`

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/abridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1:** `mcp_tools_list_includes_calculate_route_when_mapkit_routing_enabled`
- [ ] **Step 2:** `tools_call_dispatches_calculate_route`
- [ ] **Step 3:** Run `TZ=UTC just test-rust`
- [ ] **Step 4:** Commit `test(mapkit): add MCP integration tests for calculate_route`

---

### Task 3: MapKitStore seam + serialization

**Files:**
- Modify: `ABridge/Providers/MapKit/MapKitStore.swift`
- Modify: `ABridge/Providers/MapKit/LiveMapKitStore.swift`
- Modify: `ABridge/Providers/MapKit/MapKitSerialization.swift`
- Modify: `ABridgeTests/MockMapKitStore.swift`

- [ ] **Step 1:** Add `MapKitCalculateRouteRequest`, `MapKitCalculateRouteResult`, `MapKitRouteData`, `MapKitRouteStepData`
- [ ] **Step 2:** Implement `LiveMapKitStore.calculateRoute` with `MKDirections`
- [ ] **Step 3:** Add route/step/polyline serializers to `MapKitSerialization`
- [ ] **Step 4:** Extend `MockMapKitStore`
- [ ] **Step 5:** Run `just test-swift`
- [ ] **Step 6:** Commit `feat(mapkit): add MapKitStore calculate_route seam`

---

### Task 4: MapKitProvider calculate_route operation

**Files:**
- Create: `ABridge/Providers/MapKit/MapKitProviderCalculateRoute.swift`
- Modify: `ABridge/Providers/MapKit/MapKitProviderRouting.swift`
- Create: `ABridgeTests/MapKitProviderCalculateRouteTests.swift`
- Modify: `ABridgeTests/AppleProviderBridgeMapKitTests.swift`

- [ ] **Step 1:** Write failing provider tests (permission, validation, success)
- [ ] **Step 2:** Implement `calculateRoute` handler + argument parsing
- [ ] **Step 3:** Add routing case
- [ ] **Step 4:** Bridge test
- [ ] **Step 5:** Run `xcodegen generate` if needed; `just test-swift`
- [ ] **Step 6:** Commit `feat(mapkit): implement calculate_route provider operation`

---

### Task 5: Ship capability + README + full verification

**Files:**
- Modify: `ABridge/Models/CapabilityCatalog.swift`
- Modify: `ABridgeTests/AppSettingsMapKitTests.swift`
- Modify: `ABridgeTests/PermissionsStoreMapKitTests.swift`
- Modify: `README.md`

- [ ] **Step 1:** Set `mapkit-routing` → `shipped: true`
- [ ] **Step 2:** Add AppSettings + PermissionsStore tests for routing toggle
- [ ] **Step 3:** README checkoff
- [ ] **Step 4:** Run `TZ=UTC just test-all`
- [ ] **Step 5:** Commit `feat(mapkit): ship mapkit_calculate_route tool`

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `MAPKIT_ROUTING` Rust constant + v1 allowlist | Task 1 |
| `TOOL_CALCULATE_ROUTE` registration + input schema | Task 1 |
| MCP integration tests | Task 2 |
| `MKDirections` via MapKitStore | Task 3 |
| Exhaustive route JSON serializers | Task 3 |
| Location `permission_denied` gate | Task 4 |
| Ship `mapkit-routing` capability | Task 5 |
| README checkoff | Task 5 |
| `just test-all` | Task 5 |