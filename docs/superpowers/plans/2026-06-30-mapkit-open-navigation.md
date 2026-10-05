# mapkit.open_navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `mapkit.open_navigation` MCP tool (#110) opening Apple Maps navigation under new `mapkit.navigation` capability.

**Architecture:** Extend `MapKitStore` with `openNavigation`; use `MKMapItem.openMaps` in `LiveMapKitStore`; map launch options to seam types for mockability; add response serializers to `MapKitSerialization`; Rust tool registration on `mapkit.navigation`; ship `mapkit-navigation` toggle; CoreLocation when-in-use gate per #150.

**Tech Stack:** Rust (`abridge_core`), Swift 6 + MapKit + CoreLocation, Swift Testing, UniFFI `ProviderBridge`

**Spec:** `docs/superpowers/specs/2026-06-30-mapkit-open-navigation-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `rust/abridge_core/src/capabilities.rs` | `MAPKIT_NAVIGATION` constant + v1 allowlist |
| `rust/abridge_core/src/tools/mod.rs` | `TOOL_OPEN_NAVIGATION` registration + input schema |
| `rust/abridge_core/tests/mcp_protocol.rs` | MCP integration tests |
| `ABridge/Providers/MapKit/MapKitStore.swift` | Request/result seam types + protocol method |
| `ABridge/Providers/MapKit/LiveMapKitStore.swift` | `MKMapItem.openMaps` wrapper |
| `ABridge/Providers/MapKit/MapKitSerialization.swift` | Open-navigation response serializer |
| `ABridge/Providers/MapKit/MapKitProviderOpenNavigation.swift` | `open_navigation` handler |
| `ABridge/Providers/MapKit/MapKitProviderRouting.swift` | Operation dispatch |
| `ABridge/Models/CapabilityCatalog.swift` | Ship `mapkit-navigation` |
| `ABridgeTests/MockMapKitStore.swift` | Open-navigation mock seam |
| `ABridgeTests/MapKitProviderOpenNavigationTests.swift` | Provider tests |
| `ABridgeTests/AppleProviderBridgeMapKitTests.swift` | Bridge routing test |
| `ABridgeTests/AppSettingsMapKitTests.swift` | Navigation capability gating |
| `ABridgeTests/PermissionsStoreMapKitTests.swift` | Navigation location requirement |
| `README.md` | Check off tool |

---

### Task 1: Rust capability + tool registration

**Files:**
- Modify: `rust/abridge_core/src/capabilities.rs`
- Modify: `rust/abridge_core/src/tools/mod.rs`

- [ ] **Step 1:** Add `MAPKIT_NAVIGATION` to capabilities.rs + v1 allowlist + tests
- [ ] **Step 2:** Register `TOOL_OPEN_NAVIGATION` in tools/mod.rs (bump array 48 → 49)
- [ ] **Step 3:** Add input schema for source/destination coordinates + optional `transport_type`
- [ ] **Step 4:** Add unit tests (`lists_open_navigation_tool_when_mapkit_navigation_capability_enabled`, schema tests)
- [ ] **Step 5:** Run `TZ=UTC just test-rust`
- [ ] **Step 6:** Commit `feat(mapkit): register mapkit.open_navigation MCP tool in Rust`

---

### Task 2: Rust MCP integration tests

**Files:**
- Modify: `rust/abridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1:** `mcp_tools_list_includes_open_navigation_when_mapkit_navigation_enabled`
- [ ] **Step 2:** `tools_call_dispatches_open_navigation`
- [ ] **Step 3:** Run `TZ=UTC just test-rust`
- [ ] **Step 4:** Commit `test(mapkit): add MCP integration tests for open_navigation`

---

### Task 3: MapKitStore seam + serialization

**Files:**
- Modify: `ABridge/Providers/MapKit/MapKitStore.swift`
- Modify: `ABridge/Providers/MapKit/LiveMapKitStore.swift`
- Modify: `ABridge/Providers/MapKit/MapKitSerialization.swift`
- Modify: `ABridgeTests/MockMapKitStore.swift`

- [ ] **Step 1:** Add `MapKitOpenNavigationRequest`, `MapKitOpenNavigationResult`
- [ ] **Step 2:** Implement `LiveMapKitStore.openNavigation` with `MKMapItem.openMaps`
- [ ] **Step 3:** Add `openNavigationResponseJSONObject` to `MapKitSerialization`
- [ ] **Step 4:** Extend `MockMapKitStore`
- [ ] **Step 5:** Run `just test-swift`
- [ ] **Step 6:** Commit `feat(mapkit): add MapKitStore open_navigation seam`

---

### Task 4: MapKitProvider open_navigation operation

**Files:**
- Create: `ABridge/Providers/MapKit/MapKitProviderOpenNavigation.swift`
- Modify: `ABridge/Providers/MapKit/MapKitProviderRouting.swift`
- Create: `ABridgeTests/MapKitProviderOpenNavigationTests.swift`
- Modify: `ABridgeTests/AppleProviderBridgeMapKitTests.swift`

- [ ] **Step 1:** Write failing provider tests (permission, validation, success)
- [ ] **Step 2:** Implement `openNavigation` handler + argument parsing
- [ ] **Step 3:** Add routing case
- [ ] **Step 4:** Bridge test
- [ ] **Step 5:** Run `xcodegen generate` if needed; `just test-swift`
- [ ] **Step 6:** Commit `feat(mapkit): implement open_navigation provider operation`

---

### Task 5: Ship capability + README + full verification

**Files:**
- Modify: `ABridge/Models/CapabilityCatalog.swift`
- Modify: `ABridgeTests/AppSettingsMapKitTests.swift`
- Modify: `ABridgeTests/PermissionsStoreMapKitTests.swift`
- Modify: `README.md`

- [ ] **Step 1:** Set `mapkit-navigation` → `shipped: true`
- [ ] **Step 2:** Add AppSettings + PermissionsStore tests for navigation toggle
- [ ] **Step 3:** README checkoff
- [ ] **Step 4:** Run `TZ=UTC just test-all`
- [ ] **Step 5:** Commit `feat(mapkit): ship mapkit.open_navigation tool`

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `MAPKIT_NAVIGATION` Rust constant + v1 allowlist | Task 1 |
| `TOOL_OPEN_NAVIGATION` registration + input schema | Task 1 |
| MCP integration tests | Task 2 |
| `MKMapItem.openMaps` via MapKitStore | Task 3 |
| Exhaustive open-navigation JSON serializers | Task 3 |
| Location `permission_denied` gate | Task 4 |
| Ship `mapkit-navigation` capability | Task 5 |
| README checkoff | Task 5 |
| `just test-all` | Task 5 |