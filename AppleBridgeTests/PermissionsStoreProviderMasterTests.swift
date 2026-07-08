import Foundation
import Testing
@testable import AppleBridge

@Suite("PermissionsStoreProviderMaster")
struct PermissionsStoreProviderMasterTests {
    @MainActor
    private func makeStore(suite: String) throws -> (PermissionsStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (PermissionsStore(appSettings: AppSettings(defaults: defaults)), defaults)
    }

    @Test
    @MainActor
    func enableAllRemindersChecksEveryShippedID() throws {
        let (store, _) = try makeStore(suite: "PermissionsStoreProviderMaster.enableAll")
        store.enableAllShipped(for: .reminders)
        let shipped = CapabilityCatalog.remindersCapabilities.filter(\.shipped).map(\.id)
        for id in shipped {
            #expect(store.checkedCapabilityIDs.contains(id))
        }
        #expect(store.masterState(for: .reminders) == .on)
        #expect(store.requiresAppleRemindersAccess)
    }

    @Test
    @MainActor
    func disableAllRemindersClearsShippedOnly() throws {
        let (store, _) = try makeStore(suite: "PermissionsStoreProviderMaster.disableAll")
        store.enableAllShipped(for: .reminders)
        store.enableAllShipped(for: .contacts)
        store.disableAllShipped(for: .reminders)
        #expect(store.masterState(for: .reminders) == .off)
        #expect(store.masterState(for: .contacts) == .on)
    }

    @Test
    @MainActor
    func calendarsAndEventsSpansBothCatalogs() throws {
        let (store, _) = try makeStore(suite: "PermissionsStoreProviderMaster.calEvents")
        store.enableAllShipped(for: .calendarsAndEvents)
        #expect(store.requiresCalendarAccess)
        let cal = CapabilityCatalog.calendarsCapabilities.filter(\.shipped).count
        let ev = CapabilityCatalog.eventsCapabilities.filter(\.shipped).count
        #expect(store.checkedShippedCount(for: .calendarsAndEvents) == cal + ev)
    }

    @Test
    @MainActor
    func mixedWhenPartial() throws {
        let (store, _) = try makeStore(suite: "PermissionsStoreProviderMaster.mixed")
        store.setChecked(true, for: "read")
        #expect(store.masterState(for: .reminders) == .mixed)
    }
}
