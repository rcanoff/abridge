# Settings Liquid Glass UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish Settings (MCP + Permissions) and menu bar popover with macOS 26 Liquid Glass and System Settings structure while keeping preview-style permissions transparency.

**Architecture:** Shared `SettingsDesign` tokens + small presentation components; refactor existing Settings/popover views to grouped `Form` + selective `.glassEffect()`; no store/service changes.

**Tech Stack:** Swift 6, SwiftUI (macOS 26), swiftui-pro conventions

**Spec:** `docs/superpowers/specs/2026-06-28-settings-liquid-glass-ui-design.md`  
**Branch:** `feat/settings-liquid-glass-ui`

**Skills before Swift edits:** swiftui-pro, swift-concurrency-pro

---

## File Map

| File | Action |
|------|--------|
| `AppleBridge/Views/Settings/Design/SettingsDesign.swift` | Create — tokens |
| `AppleBridge/Views/Settings/Design/GlassSection.swift` | Create — glass wrapper |
| `AppleBridge/Views/Settings/Design/StatusIndicator.swift` | Create — status label |
| `AppleBridge/Views/Settings/Design/EnforcementTagPair.swift` | Create — Apple/MCP tags |
| `AppleBridge/Views/Settings/SettingsWindowView.swift` | Modify — shell + NavigationStack |
| `AppleBridge/Views/Settings/MCPSettingsView.swift` | Modify — grouped Form |
| `AppleBridge/Views/Settings/PermissionsSettingsView.swift` | Modify — Form + glass + toolbar |
| `AppleBridge/Views/MenuBarPopoverView.swift` | Modify — materials + shared status |
| `project.yml` | Modify if needed — new Design group paths |
| `AppleBridge.xcodeproj` | Regenerate via `xcodegen generate` |

---

### Task 1: Design tokens

**Files:** Create `SettingsDesign.swift`

- [ ] **Step 1:** Add enum/struct with:
  - `popoverSpacing`, `sectionSpacing`, `glassCornerRadius`
  - Sidebar symbol names for MCP / Permissions
  - Glass preset helper (wraps `.glassEffect()` availability for macOS 26)
- [ ] **Step 2:** Run `xcodegen generate` if paths not picked up
- [ ] **Step 3:** Build — `just test-swift` compile phase (or XcodeBuildMCP build)

---

### Task 2: StatusIndicator

**Files:** Create `StatusIndicator.swift`

- [ ] **Step 1:** Implement for `ServerRunState` — symbol + hierarchical text (running=green dot symbol, etc.)
- [ ] **Step 2:** Implement for `RemindersPermissionStatus` — same pattern
- [ ] **Step 3:** VoiceOver accessibility labels
- [ ] **Step 4:** Build succeeds

---

### Task 3: GlassSection + EnforcementTagPair

**Files:** Create `GlassSection.swift`, `EnforcementTagPair.swift`

- [ ] **Step 1:** `GlassSection` — content + padding + moderate `.glassEffect()` on macOS 26
- [ ] **Step 2:** `EnforcementTagPair` — two capsule tags from `CapabilityEnforcement`; glass on cluster
- [ ] **Step 3:** Map tag colors to semantic styles (green/orange/red/secondary) per spec
- [ ] **Step 4:** Build succeeds

---

### Task 4: Settings shell refactor

**Files:** Modify `SettingsWindowView.swift`

- [ ] **Step 1:** Sidebar `List` items → `Label(tab.title, systemImage: SettingsDesign.symbol(for: tab))`
- [ ] **Step 2:** Wrap detail in `NavigationStack`; remove manual `NSColor` background
- [ ] **Step 3:** Pass navigation context into child views (or use per-tab `navigationTitle` inside children)
- [ ] **Step 4:** Manual smoke — open Settings, switch tabs

---

### Task 5: MCP tab — grouped Form

**Files:** Modify `MCPSettingsView.swift`

- [ ] **Step 1:** Replace `ScrollView` + `GroupBox` with `Form` + `Section` groups (Server, Connection, Authentication)
- [ ] **Step 2:** Use `StatusIndicator` for server status
- [ ] **Step 3:** Wrap Authentication block in `GlassSection`
- [ ] **Step 4:** Reset token → `.confirmationDialog` on Reset button
- [ ] **Step 5:** Section footers for helper text; `bold()` / navigation title instead of `fontWeight(.bold)`
- [ ] **Step 6:** Fix port binding — prefer `@State portText` + `onChange` over body `Binding(get:set:)` where possible
- [ ] **Step 7:** Manual smoke — toggle server, edit port, copy/reset token

---

### Task 6: Permissions tab — Form + glass + toolbar

**Files:** Modify `PermissionsSettingsView.swift`

- [ ] **Step 1:** Top `GlassSection` summary card (MCP + Apple lines)
- [ ] **Step 2:** `Form` + `Section("Reminders")` with `ForEach` toggles
- [ ] **Step 3:** Replace custom tags with `EnforcementTagPair`
- [ ] **Step 4:** Conditional `.listRowBackground` for active / blocked-selected rows
- [ ] **Step 5:** Move explanatory copy to `Section` footer; remove custom gray box
- [ ] **Step 6:** Toolbar Save button (`.confirmationAction`); wire existing `savePermissions()`
- [ ] **Step 7:** Calendar stub in tertiary style
- [ ] **Step 8:** Manual smoke — toggle capabilities, save, verify tags

---

### Task 7: Popover polish

**Files:** Modify `MenuBarPopoverView.swift`

- [ ] **Step 1:** `.presentationBackground` with glass/material
- [ ] **Step 2:** Use `SettingsDesign.popoverSpacing` and `StatusIndicator`
- [ ] **Step 3:** `LabeledContent` for Reminders + Server sections
- [ ] **Step 4:** Prominent **Settings…** button
- [ ] **Step 5:** Manual smoke — popover in light/dark

---

### Task 8: swiftui-pro pass + verification

- [ ] **Step 1:** Grep for `fontWeight(.bold)`, `Color(nsColor:`, `.caption2` — fix stragglers
- [ ] **Step 2:** VoiceOver spot-check on tags and toggles
- [ ] **Step 3:** `TZ=UTC just test-swift` — all existing tests green
- [ ] **Step 4:** Optional `just review` on Swift-only diff

---

## Success criteria

- [ ] Spec success criteria met
- [ ] No store/service/Rust file changes in diff (unless accidental import cleanup)
- [ ] `just test-swift` passes

---

## Agent notes

**Commit gate:** Do not commit until user says ready.

**Generated code:** Never edit `apple_bridge_core.swift`.

**Fallback:** If `.glassEffect()` unavailable in SDK, use `.background(.regularMaterial)` with comment to swap when building on macOS 26 SDK — project targets macOS 26.0 so prefer native glass API.