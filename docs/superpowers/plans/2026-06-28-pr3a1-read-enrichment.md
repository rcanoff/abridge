# PR 3a1: Reminders Read Enrichment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the shipped Read capability with `list_id` on reminder payloads, a `get_reminder` MCP tool, and the missing PR 3a test coverage — before PR 3b Create.

**Architecture:** Same PR 3a stack — Rust tool registry gates `eventkit.reminders.read`, dispatches `get_reminder` to Swift `EventKitProvider`, which fetches via `EKEventStore.calendarItem(withIdentifier:)`. Mapping uses a `ReminderRepresentable` protocol so `FakeReminder` enables CI tests without live EventKit.

**Tech Stack:** Rust (axum MCP router), UniFFI ProviderBridge, Swift 6, EventKit, Swift Testing

**Spec:** `docs/superpowers/specs/2026-06-28-pr3a1-read-enrichment-design.md`  
**Branch:** `feat/pr3a1-read-enrichment`

---

## File Map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/tools/mod.rs` | Add `TOOL_GET_REMINDER`, schema, registry entry |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | Dispatch tests for `list_reminders` + `get_reminder` |
| `AppleBridge/Providers/EventKit/EventKitReminderMapping.swift` | `ReminderRepresentable`, `list_id` in dictionary |
| `AppleBridge/Providers/EventKit/EventKitProvider.swift` | `get_reminder` op, `fetchReminder` on store protocol |
| `AppleBridgeTests/FakeReminder.swift` | Test double conforming to `ReminderRepresentable` |
| `AppleBridgeTests/MockEventKitStore.swift` | `fetchReminder`, `fakeReminders` storage |
| `AppleBridgeTests/StalledEventKitStore.swift` | Protocol signature update |
| `AppleBridgeTests/EventKitReminderMappingTests.swift` | `list_id` mapping tests |
| `AppleBridgeTests/EventKitProviderTests.swift` | Happy-path + error tests |
| `AppleBridgeTests/AppleProviderBridgeTests.swift` | Optional `get_reminder` routing smoke |

---

## Constants

```text
CAPABILITY_READ = "eventkit.reminders.read"
TOOL_GET_REMINDER = "eventkit.reminders.get_reminder"
OPERATION_GET_REMINDER = "get_reminder"
```

---

## Prerequisites

- [ ] On `main` at latest (`4dd3572` or newer)
- [ ] `just ci` green on base
- [ ] Read skills before Swift edits: **swiftui-pro**, **swift-testing-pro**, **swift-concurrency-pro**
- [ ] Read **rust-best-practices** + `rust/AGENTS.md` before Rust edits

---

### Task 1: Branch

- [ ] **Step 1:** Create branch

```bash
git checkout main && git pull && git checkout -b feat/pr3a1-read-enrichment
```

---

### Task 2: Rust tool registry — `get_reminder` (TDD)

**Files:**
- Modify: `rust/apple_bridge_core/src/tools/mod.rs`
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1:** Add failing registry test in `tools/mod.rs` `mod tests`:

```rust
use super::{TOOL_GET_REMINDER, TOOL_LIST_LISTS, TOOL_LIST_REMINDERS, tools_for_capabilities};

#[test]
fn lists_get_reminder_when_read_enabled() {
  let tools = tools_for_capabilities(&["eventkit.reminders.read".into()]);
  let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
  assert_eq!(
    names,
    vec![TOOL_LIST_LISTS, TOOL_LIST_REMINDERS, TOOL_GET_REMINDER]
  );
}
```

- [ ] **Step 2:** Run `TZ=UTC cargo test lists_get_reminder --manifest-path rust/apple_bridge_core/Cargo.toml`  
  Expected: FAIL — `TOOL_GET_REMINDER` not defined

- [ ] **Step 3:** Implement in `tools/mod.rs`:

```rust
pub const TOOL_GET_REMINDER: &str = "eventkit.reminders.get_reminder";

// Add to ALL_TOOLS array:
ToolDefinition {
  name: TOOL_GET_REMINDER,
  capability: capabilities::EVENTKIT_REMINDERS_READ,
  provider: "eventkit",
  operation: "get_reminder",
  description: "Get a single reminder by reminder_id",
},

// In input_schema match arm:
TOOL_GET_REMINDER => serde_json::json!({
  "type": "object",
  "properties": {
    "reminder_id": { "type": "string" }
  },
  "required": ["reminder_id"]
}),
```

- [ ] **Step 4:** Run `TZ=UTC cargo test --manifest-path rust/apple_bridge_core/Cargo.toml`  
  Expected: PASS (update `lists_read_tools_when_capability_enabled` expected vec if still present)

- [ ] **Step 5:** Commit

```bash
git add rust/apple_bridge_core/src/tools/mod.rs
git commit -m "feat(rust): register eventkit.reminders.get_reminder read tool"
```

---

### Task 3: Rust MCP dispatch tests (TDD)

**Files:**
- Modify: `rust/apple_bridge_core/tests/mcp_protocol.rs`

- [ ] **Step 1:** Add failing tests:

```rust
#[test]
fn tools_call_dispatches_list_reminders() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"eventkit.reminders.list_reminders","arguments":{"list_id":"list-1"}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.read".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains(r#""isError":false"#));
  let recorded = mock.last_request.lock().expect("lock").clone().expect("request");
  assert_eq!(recorded.provider, "eventkit");
  assert_eq!(recorded.operation, "list_reminders");
  assert!(recorded.payload_json.contains("list-1"));
}

#[test]
fn tools_call_dispatches_get_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"eventkit.reminders.get_reminder","arguments":{"reminder_id":"rem-42"}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.read".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains(r#""isError":false"#));
  let recorded = mock.last_request.lock().expect("lock").clone().expect("request");
  assert_eq!(recorded.provider, "eventkit");
  assert_eq!(recorded.operation, "get_reminder");
  assert!(recorded.payload_json.contains("rem-42"));
}

#[test]
fn mcp_tools_list_includes_get_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":12,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.read".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.get_reminder"));
}
```

- [ ] **Step 2:** Run `TZ=UTC cargo test tools_call_dispatches_get_reminder --manifest-path rust/apple_bridge_core/Cargo.toml`  
  Expected: PASS once Task 2 merged (dispatch already generic — tests document behavior)

- [ ] **Step 3:** Commit

```bash
git add rust/apple_bridge_core/tests/mcp_protocol.rs
git commit -m "test(rust): MCP dispatch coverage for list_reminders and get_reminder"
```

---

### Task 4: Swift mapping — `ReminderRepresentable` + `list_id` (TDD)

**Skills:** swift-testing-pro

**Files:**
- Modify: `AppleBridge/Providers/EventKit/EventKitReminderMapping.swift`
- Create: `AppleBridgeTests/FakeReminder.swift`
- Modify: `AppleBridgeTests/EventKitReminderMappingTests.swift`
- Modify: `project.yml` if new test file needs explicit listing (check pattern — tests may auto-include `AppleBridgeTests/**`)

- [ ] **Step 1:** Add failing mapping test:

```swift
@Test
func reminderDictionaryIncludesListID() throws {
    let reminder = FakeReminder(
        id: "rem-1",
        listID: "list-abc",
        title: "Buy milk",
        completed: false,
        dueDateISO: "2026-06-28T12:00:00Z",
        notes: "2%"
    )

    let dict = EventKitReminderMapping.reminderDictionary(from: reminder)
    let json = try EventKitReminderMapping.jsonString(from: dict)

    #expect(json.contains("\"list_id\""))
    #expect(json.contains("list-abc"))
    #expect(json.contains("Buy milk"))
}
```

- [ ] **Step 2:** Run `just test-swift`  
  Expected: FAIL — `FakeReminder` / protocol missing

- [ ] **Step 3:** Add `FakeReminder.swift`:

```swift
@testable import AppleBridge
import Foundation

struct FakeReminder: ReminderRepresentable {
    let id: String
    let listID: String?
    let title: String?
    let completed: Bool
    let dueDateISO: String?
    let notes: String?

    var calendarItemIdentifier: String { id }
    var reminderListID: String? { listID }
    var reminderTitle: String? { title }
    var isCompleted: Bool { completed }
    var dueDateComponents: DateComponents? {
        guard let dueDateISO else { return nil }
        return ISO8601DateFormatter().date(from: dueDateISO).map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0)
        }
    }
    var reminderNotes: String? { notes }
}
```

- [ ] **Step 4:** Refactor `EventKitReminderMapping.swift`:

```swift
protocol ReminderRepresentable {
    var calendarItemIdentifier: String { get }
    var reminderListID: String? { get }
    var reminderTitle: String? { get }
    var isCompleted: Bool { get }
    var dueDateComponents: DateComponents? { get }
    var reminderNotes: String? { get }
}

extension EKReminder: ReminderRepresentable {
    var reminderListID: String? { calendar?.calendarIdentifier }
    var reminderTitle: String? { title }
    var reminderNotes: String? { notes }
}

static func reminderDictionary(from reminder: some ReminderRepresentable) -> [String: Any] {
    var payload: [String: Any] = [
        "id": reminder.calendarItemIdentifier,
        "list_id": reminder.reminderListID ?? NSNull(),
        "title": reminder.reminderTitle ?? "",
        "completed": reminder.isCompleted,
    ]
    // due_date + notes — same logic as today, using protocol properties
    ...
}

// Keep convenience for call sites:
static func reminderDictionary(from reminder: EKReminder) -> [String: Any] {
    reminderDictionary(from: reminder as ReminderRepresentable)
}
```

- [ ] **Step 5:** Run `just test-swift`  
  Expected: PASS mapping tests

- [ ] **Step 6:** Commit

```bash
git add AppleBridge/Providers/EventKit/EventKitReminderMapping.swift AppleBridgeTests/FakeReminder.swift AppleBridgeTests/EventKitReminderMappingTests.swift
git commit -m "feat(swift): add list_id to reminder read payload via ReminderRepresentable"
```

---

### Task 5: Swift provider — `get_reminder` + mock seam (TDD)

**Skills:** swift-testing-pro, swift-concurrency-pro

**Files:**
- Modify: `AppleBridge/Providers/EventKit/EventKitProvider.swift`
- Modify: `AppleBridgeTests/MockEventKitStore.swift`
- Modify: `AppleBridgeTests/EventKitProviderTests.swift`

- [ ] **Step 1:** Extend `EventKitStoreing` — change fetch return type to `ReminderRepresentable`:

```swift
func fetchReminders(matching predicate: NSPredicate) throws -> [any ReminderRepresentable]
func fetchReminder(withIdentifier id: String) throws -> (any ReminderRepresentable)?
```

`LiveEventKitStore` — `fetchReminders` unchanged except return type (`[EKReminder]` conforms). `fetchReminder`:

```swift
func fetchReminder(withIdentifier id: String) throws -> (any ReminderRepresentable)? {
    guard let item = eventStore.calendarItem(withIdentifier: id) else { return nil }
    guard let reminder = item as? EKReminder else {
        throw EventKitProviderError.invalidArguments("Not a reminder: \(id)")
    }
    return reminder
}
```

`MockEventKitStore` — replace `reminders: [EKReminder]` with `fakeReminders: [FakeReminder]`:

```swift
var fakeReminders: [FakeReminder] = []

func fetchReminders(matching predicate: NSPredicate) throws -> [any ReminderRepresentable] {
    _ = predicate
    return fakeReminders
}

func fetchReminder(withIdentifier id: String) throws -> (any ReminderRepresentable)? {
    fakeReminders.first { $0.calendarItemIdentifier == id }
}
```

Update `StalledEventKitStore` to satisfy the new protocol signature (return `[]`, never complete).

- [ ] **Step 2:** Add failing provider tests:

```swift
@Test
@MainActor
func getReminderReturnsPayload() {
    let mockStore = MockEventKitStore()
    mockStore.authorizationStatus = .fullAccess
    mockStore.fakeReminders = [
        FakeReminder(
            id: "rem-1", listID: "list-1", title: "Task", completed: false,
            dueDateISO: nil, notes: nil
        ),
    ]
    let provider = EventKitProvider(store: mockStore)

    let response = provider.handle(
        operation: "get_reminder",
        payloadJson: #"{"reminder_id":"rem-1"}"#
    )

    #expect(response.ok == true)
    #expect(response.payloadJson.contains("rem-1"))
    #expect(response.payloadJson.contains("list-1"))
}

@Test
@MainActor
func getReminderUnknownIDReturnsInvalidArguments() {
    let mockStore = MockEventKitStore()
    mockStore.authorizationStatus = .fullAccess
    let provider = EventKitProvider(store: mockStore)

    let response = provider.handle(
        operation: "get_reminder",
        payloadJson: #"{"reminder_id":"missing"}"#
    )

    #expect(response.ok == false)
    #expect(response.errorJson?.contains("invalid_arguments") == true)
}

@Test
@MainActor
func getReminderMissingReminderIDReturnsInvalidArguments() {
    let mockStore = MockEventKitStore()
    mockStore.authorizationStatus = .fullAccess
    let provider = EventKitProvider(store: mockStore)

    let response = provider.handle(operation: "get_reminder", payloadJson: "{}")

    #expect(response.ok == false)
    #expect(response.errorJson?.contains("invalid_arguments") == true)
}

@Test
@MainActor
func listRemindersIncludesListID() {
    let mockStore = MockEventKitStore()
    mockStore.authorizationStatus = .fullAccess
    mockStore.fakeReminders = [
        FakeReminder(
            id: "rem-2", listID: "list-9", title: "Eggs", completed: true,
            dueDateISO: nil, notes: nil
        ),
    ]
    let provider = EventKitProvider(store: mockStore)

    let response = provider.handle(operation: "list_reminders", payloadJson: "{}")

    #expect(response.ok == true)
    #expect(response.payloadJson.contains("list-9"))
    #expect(response.payloadJson.contains("rem-2"))
}
```

- [ ] **Step 3:** Implement `get_reminder` in `EventKitProvider.handle`:

```swift
case "get_reminder":
    getReminder(payloadJson: payloadJson)
```

```swift
private func getReminder(payloadJson: String) -> ProviderResponse {
    guard isAuthorized else {
        return errorResponse(code: "permission_denied", message: "Reminders access not granted")
    }
    do {
        let reminderID = try parseReminderID(payloadJson)
        guard let reminder = try store.fetchReminder(withIdentifier: reminderID) else {
            return errorResponse(code: "invalid_arguments", message: "Unknown reminder_id: \(reminderID)")
        }
        let payload = try EventKitReminderMapping.jsonString(
            from: EventKitReminderMapping.reminderDictionary(from: reminder)
        )
        return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
    } catch let error as EventKitProviderError {
        // same switch as list_reminders
    } catch {
        return providerError(from: error)
    }
}

private func parseReminderID(_ payloadJson: String) throws -> String {
    // Require non-empty string reminder_id — mirror list_id parse style
}
```

- [ ] **Step 4:** Update `listReminders` to map `store.fetchReminders` results through `reminderDictionary(from:)` (already `ReminderRepresentable`).

- [ ] **Step 5:** Run `just test-swift`  
  Expected: PASS

- [ ] **Step 6:** Commit

```bash
git add AppleBridge/Providers/EventKit/EventKitProvider.swift AppleBridgeTests/MockEventKitStore.swift AppleBridgeTests/EventKitProviderTests.swift
git commit -m "feat(swift): implement get_reminder and list_id in list_reminders"
```

---

### Task 6: Bridge routing smoke (optional but quick)

**Files:**
- Modify: `AppleBridgeTests/AppleProviderBridgeTests.swift`

- [ ] **Step 1:** Add test:

```swift
@Test
@MainActor
func routesEventKitGetReminder() {
    let mockStore = MockEventKitStore()
    mockStore.authorizationStatus = .fullAccess
    mockStore.fakeReminders = [
        FakeReminder(
            id: "r1", listID: "l1", title: "T", completed: false, dueDateISO: nil, notes: nil
        ),
    ]
    let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
    let request = ProviderRequest(
        provider: "eventkit",
        operation: "get_reminder",
        payloadJson: #"{"reminder_id":"r1"}"#
    )
    let response = bridge.callProvider(request: request)
    #expect(response.ok == true)
}
```

- [ ] **Step 2:** `just test-swift` — PASS

- [ ] **Step 3:** Commit

```bash
git add AppleBridgeTests/AppleProviderBridgeTests.swift
git commit -m "test(swift): bridge routes get_reminder to EventKitProvider"
```

---

### Task 7: Verification + manual smoke

- [ ] **Step 1:** Full CI

```bash
TZ=UTC just ci
```

Expected: all green

- [ ] **Step 2:** Manual smoke (requires Reminders permission granted)

1. Open Settings → enable MCP server with Read capability
2. Copy bearer token and port
3. `tools/list` — confirm `eventkit.reminders.get_reminder` present
4. `tools/call` `list_reminders` — note an `id` and `list_id` from response
5. `tools/call` `get_reminder` with that `id` — single object, same `list_id`
6. `get_reminder` with bogus id — `invalid_arguments`

Example curl skeleton (replace token, port, id):

```bash
curl -s -X POST "http://127.0.0.1:3020/mcp" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"eventkit.reminders.get_reminder","arguments":{"reminder_id":"<id>"}}}'
```

- [ ] **Step 3:** Final commit if any fixups; do **not** push until user requests

---

## Self-review checklist

| Spec requirement | Task |
|------------------|------|
| `list_id` on reminder objects | Task 4, 5 |
| `get_reminder` tool + operation | Task 2, 5 |
| Same JSON shape for list + get | Task 4 |
| Read capability only (no UI) | Task 2 (no Swift settings files) |
| Rust MCP dispatch tests | Task 3 |
| Swift provider + mapping tests | Tasks 4, 5, 6 |
| Manual smoke | Task 7 |

---

## After merge — next PR

**PR 3b Create** — `eventkit.reminders.create` capability + `create_reminder` tool; clients can use `list_id` from read + `get_reminder` for verification.