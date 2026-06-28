# Settings + Popover — Liquid Glass UI Design

**Date:** 2026-06-28  
**Status:** Approved (brainstorming)  
**Branch:** `feat/settings-liquid-glass-ui` (from `feat/pr3a-mcp-read-milestone`)  
**Predecessor:** `docs/superpowers/specs/2026-06-27-settings-permissions-design.md`  
**Preview reference:** `docs/superpowers/previews/settings-preview.html` (behavior + tags, not chrome)

---

## Summary

Visual polish pass for the Settings window (MCP + Permissions) and menu bar popover. Adopt **macOS 26 Liquid Glass** and **System Settings** structure while preserving the preview’s permissions transparency (summary card, Apple/MCP dual tags, row emphasis).

**Presentation only** — no changes to stores, services, Rust, or MCP behavior.

---

## Decisions (locked in brainstorming)

| Question | Choice |
|----------|--------|
| Scope | Settings window **and** menu bar popover |
| Visual target | **Balanced** — System Settings structure + preview personality |
| Glass intensity | **Moderate** — glass on elevated surfaces, not every row |

---

## Goals

- Settings feels like a native macOS 26 utility (grouped `Form`, sidebar symbols, toolbar save)
- Liquid Glass on elevated panels only (summary, token block, popover, tags)
- Popover shares typography, status indicators, and materials with Settings
- swiftui-pro compliance: `bold()`, hierarchical `foregroundStyle`, no `NSColor`, minimal `.caption2`
- Accessibility: VoiceOver labels on tags; Dynamic Type safe layouts

## Non-goals

- Custom window title bar / fake traffic lights
- Glass on every section or toggle row
- New Settings tabs or features
- Pixel-perfect HTML preview
- UIKit `NSGlassEffectView` bridges
- Store / service / UniFFI changes

---

## Design principles

| Principle | Rule |
|-----------|------|
| Structure from Apple | `NavigationSplitView`, grouped `Form`, sidebar `Label` + SF Symbol, toolbar actions |
| Personality from preview | Summary card, Apple/MCP tags, active/blocked row emphasis |
| Glass elevates | Standard controls stay system chrome; glass accents depth |
| One design system | Shared tokens + components in Settings and popover |

### Glass surfaces (moderate)

1. Permissions summary card (top)
2. MCP bearer token section
3. Popover presentation background
4. Enforcement tag clusters (capsule glass)
5. Active / blocked capability row tint (subtle)

All other surfaces use system `Form` / `List` materials.

---

## Architecture

```
SettingsDesign (tokens)
    ├── GlassSection
    ├── StatusIndicator
    └── EnforcementTagPair

SettingsWindowView (shell)
    ├── MCPSettingsView (Form sections)
    └── PermissionsSettingsView (Form + glass summary + tags)

MenuBarPopoverView (compact status + open Settings)
```

Data flow unchanged: existing `@Bindable` stores passed into views.

---

## Settings shell

```
NavigationSplitView
├── Sidebar: List(selection:) — Label + SF Symbol per tab
│     MCP          → point.3.connected.trianglepath.dotted
│     Permissions  → lock.shield
└── Detail: NavigationStack
      ├── .navigationTitle(tab)
      ├── Form(.grouped)
      └── .toolbar — Save on Permissions when actionable
```

- Remove manual `Color(nsColor: .windowBackgroundColor)`; trust window chrome
- Sidebar width: system default (~148pt min), not hard-coded unless needed

---

## MCP tab

| Section | Contents |
|---------|----------|
| **Server** | Enable toggle · `StatusIndicator` for run state |
| **Connection** | Host (read-only) · Port · Endpoint (monospaced, selectable) |
| **Authentication** | Token · Copy · Reset (`confirmationDialog` on button) · section footer |

**Glass:** `GlassSection` wraps Authentication (token block).

**swiftui-pro:** Section footers for helper copy; `confirmationDialog` attached to Reset button.

---

## Permissions tab

Top → bottom:

1. **Summary card** (`GlassSection`) — MCP summary line + Apple summary line
2. **Section “Reminders”** — capability `Toggle` rows; legend in section footer
3. **Each row** — label + `EnforcementTagPair` (glass capsule tags)
4. **Row emphasis** — conditional `.listRowBackground` when MCP active or blocked+selected
5. **Explanatory copy** — `Section` footer (not custom gray box)
6. **Toolbar** — “Save” / “Save changes” (`.confirmationAction`)

**Calendar stub:** tertiary “Coming later” under disabled subsection.

Tags read from existing `CapabilityEnforcement` — no `PermissionsStore` changes.

---

## Menu bar popover

- `.presentationBackground` with glass / system material
- `LabeledContent` + `StatusIndicator` for Reminders and Server
- Permission actions unchanged (Grant / Open System Settings)
- **Settings…** as primary navigation affordance
- No bearer token or start/stop (Settings owns MCP controls)
- Shared `SettingsDesign.popoverSpacing`

---

## Shared components

| File | Responsibility |
|------|----------------|
| `SettingsDesign.swift` | Spacing, radii, symbol names, glass preset helpers |
| `GlassSection.swift` | Content wrapper + optional `.glassEffect()` |
| `StatusIndicator.swift` | Server run state + permission status via `Label` + symbol |
| `EnforcementTagPair.swift` | Renders Apple + MCP tags from `CapabilityEnforcement` |

Components are presentation-only; no store imports beyond types needed for display.

---

## Accessibility

- Tags: accessibility label e.g. “Apple granted, MCP active”
- Dynamic Type: tags wrap or compress; avoid fixed narrow frames
- Reduce Motion: system transitions only; no custom motion
- Status colors on symbols/text, not full-row fills (except subtle listRowBackground)

---

## Testing

| Layer | Minimum |
|-------|---------|
| Build | `just test-swift` — existing tests must pass (no logic changes) |
| Manual | Open Settings both tabs; toggle capabilities; open popover; light/dark; Large Text |

No new unit tests required unless pure layout helpers are extracted.

---

## Success criteria

- [ ] Settings sidebar uses SF Symbols; detail uses grouped `Form` + navigation titles
- [ ] Glass visible on summary card, token section, popover, tag capsules
- [ ] Permissions tags and row emphasis match preview semantics
- [ ] Popover visually consistent with Settings
- [ ] swiftui-pro pass: no `fontWeight(.bold)`, no `Color(nsColor:)`, reduced `.caption2`
- [ ] `just test-swift` green

---

## Open items

None.