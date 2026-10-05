@testable import ABridge
import Foundation
import Testing

@Suite("PermissionsStoreProviderEnable")
struct PermissionsStoreProviderEnableTests {
    @MainActor
    private func makeStore(suite: String) throws -> (PermissionsStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (PermissionsStore(appSettings: AppSettings(defaults: defaults)), defaults)
    }

    @Test
    @MainActor
    func enableAllRemindersChecksEveryShippedID() throws {
        let (store, _) = try makeStore(suite: "PermissionsStoreProviderEnable.enableAll")
        store.enableAllShipped(for: .reminders)
        let shipped = CapabilityCatalog.remindersCapabilities.filter(\.shipped).map(\.id)
        for id in shipped {
            #expect(store.checkedCapabilityIDs.contains(id))
        }
        #expect(store.enableState(for: .reminders) == .on)
        #expect(store.requiresAppleRemindersAccess)
    }

    @Test
    @MainActor
    func disableAllRemindersClearsShippedOnly() throws {
        let (store, _) = try makeStore(suite: "PermissionsStoreProviderEnable.disableAll")
        store.enableAllShipped(for: .reminders)
        store.enableAllShipped(for: .contacts)
        store.disableAllShipped(for: .reminders)
        #expect(store.enableState(for: .reminders) == .off)
        #expect(store.enableState(for: .contacts) == .on)
    }

    @Test
    @MainActor
    func calendarsAndEventsSpansBothCatalogs() throws {
        let (store, _) = try makeStore(suite: "PermissionsStoreProviderEnable.calEvents")
        store.enableAllShipped(for: .calendarsAndEvents)
        #expect(store.requiresCalendarAccess)
        let cal = CapabilityCatalog.calendarsCapabilities.filter(\.shipped).count
        let ev = CapabilityCatalog.eventsCapabilities.filter(\.shipped).count
        #expect(store.checkedShippedCount(for: .calendarsAndEvents) == cal + ev)
    }

    @Test
    @MainActor
    func mixedWhenPartial() throws {
        let (store, _) = try makeStore(suite: "PermissionsStoreProviderEnable.mixed")
        store.setChecked(true, for: "read")
        #expect(store.enableState(for: .reminders) == .mixed)
    }
}
