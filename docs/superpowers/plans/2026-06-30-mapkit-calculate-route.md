# mapkit.calculate_route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `mapkit.calculate_route` MCP tool (#108) with exhaustive `MKDirectionsResponse` JSON projection under new `mapkit.routing` capability.

**Architecture:** Extend `MapKitStore` with `calculateRoute`; use `MKDirections` in `LiveMapKitStore`; map `MKDirectionsResponse` to seam types for mockability; add route serializers to `MapKitSerialization`; Rust tool registration on `mapkit.routing`; ship `mapkit-routing` toggle; CoreLocation when-in-use gate per #150.

**Tech Stack:** Rust (`apple_bridge_core`), Swift 6 + MapKit + CoreLocation, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-mapkit-calculate-route-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/capabilities.rs` | `MAPKIT_ROUTING` constant + v1 allowlist |
| `rust/apple_bridge_core/src/tools/mod.rs` | `TOOL_CALCULATE_ROUTE` registration + input schema |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `AppleBridge/Providers/MapKit/MapKitStore.swift` | Request/result seam types + protocol method |
| `AppleBridge/Providers/MapKit/LiveMapKitStore.swift` | `MKDirections` blocking wrapper |
| `AppleBridge/Providers/MapKit/MapKitSerialization.swift` | Route/step/polyline serializers |
| `AppleBridge/Providers/MapKit/MapKitProviderCalculateRoute.swift` | `calculate_route` handler |
| `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift` | Operation dispatch |
| `AppleBridge/Models/CapabilityCatalog.swift` | Ship `mapkit-routing` |
| `AppleBridgeTests/MockMapKitStore.swift` | Calculate-route mock seam |
| `AppleBridgeTests/MapKitProviderCalculateRouteTests.swift` | Provider tests |
| `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift` | Bridge routing test |
| `AppleBridgeTests/AppSettingsMapKitTests.swift` | Routing capability gating |
| `AppleBridgeTests/PermissionsStoreMapKitTests.swift` | Routing location requirement |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/apple_bridge_core/src/capabilities.rs`
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`

- [ ] **Step 1:** Add `MAPKIT_ROUTING` to capabilities.rs + v1 allowlist + tests
- [ ] **Step 2:** Register `TOOL_CALCULATE_ROUTE` in tools/mod.rs (bump array 47 → 48)
- [ ] **Step 3:** Add input schema for source/destination coordinates + optional routing options
- [ ] **Step 4:** Add unit tests (`lists_calculate_route_tool_when_mapkit_routing_capability_enabled`, schema tests)
- [ ] **Step 5:** Run `TZ=UTC just test-rust`
- [ ] **Step 6:** Commit `feat(mapkit): register mapkit.calculate_route MCP tool in Rust`

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1:** `mcp_tools_list_includes_calculate_route_when_mapkit_routing_enabled`
- [ ] **Step 2:** `tools_call_dispatches_calculate_route`
- [ ] **Step 3:** Run `TZ=UTC just test-rust`
- [ ] **Step 4:** Commit `test(mapkit): add MCP integration tests for calculate_route`

---

### Task 3: MapKitStore seam + serialization

**Files:**
- Modify: `AppleBridge/Providers/MapKit/MapKitStore.swift`
- Modify: `AppleBridge/Providers/MapKit/LiveMapKitStore.swift`
- Modify: `AppleBridge/Providers/MapKit/MapKitSerialization.swift`
- Modify: `AppleBridgeTests/MockMapKitStore.swift`

- [ ] **Step 1:** Add `MapKitCalculateRouteRequest`, `MapKitCalculateRouteResult`, `MapKitRouteData`, `MapKitRouteStepData`
- [ ] **Step 2:** Implement `LiveMapKitStore.calculateRoute` with `MKDirections`
- [ ] **Step 3:** Add route/step/polyline serializers to `MapKitSerialization`
- [ ] **Step 4:** Extend `MockMapKitStore`
- [ ] **Step 5:** Run `just test-swift`
- [ ] **Step 6:** Commit `feat(mapkit): add MapKitStore calculate_route seam`

---

### Task 4: MapKitProvider calculate_route operation

**Files:**
- Create: `AppleBridge/Providers/MapKit/MapKitProviderCalculateRoute.swift`
- Modify: `AppleBridge/Providers/MapKit/MapKitProviderRouting.swift`
- Create: `AppleBridgeTests/MapKitProviderCalculateRouteTests.swift`
- Modify: `AppleBridgeTests/AppleProviderBridgeMapKitTests.swift`

- [ ] **Step 1:** Write failing provider tests (permission, validation, success)
- [ ] **Step 2:** Implement `calculateRoute` handler + argument parsing
- [ ] **Step 3:** Add routing case
- [ ] **Step 4:** Bridge test
- [ ] **Step 5:** Run `xcodegen generate` if needed; `just test-swift`
- [ ] **Step 6:** Commit `feat(mapkit): implement calculate_route provider operation`

---

### Task 5: Ship capability + README + full verification

**Files:**
- Modify: `AppleBridge/Models/CapabilityCatalog.swift`
- Modify: `AppleBridgeTests/AppSettingsMapKitTests.swift`
- Modify: `AppleBridgeTests/PermissionsStoreMapKitTests.swift`
- Modify: `README.md`

- [ ] **Step 1:** Set `mapkit-routing` → `shipped: true`
- [ ] **Step 2:** Add AppSettings + PermissionsStore tests for routing toggle
- [ ] **Step 3:** README checkoff
- [ ] **Step 4:** Run `TZ=UTC just test-all`
- [ ] **Step 5:** Commit `feat(mapkit): ship mapkit.calculate_route tool`

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