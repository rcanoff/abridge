@testable import AppleBridge
import Foundation
import Testing

@Suite("AppStoreRequestAllPendingAccess")
struct AppStoreRequestAllPendingAccessTests {
    @Test
    @MainActor
    func requestAllPendingAccessRequestsInOrderWhenAllNotDetermined() async {
        let reminders = MockRemindersPermissionService()
        let events = MockEventsPermissionService()
        let contacts = MockContactsPermissionService()
        let location = MockLocationPermissionService()
        reminders.status = .notDetermined
        events.status = .notDetermined
        contacts.status = .notDetermined
        location.status = .notDetermined
        reminders.requestResult = .success(.authorized)
        events.requestResult = .success(.authorized)
        contacts.requestResult = .success(.authorized)
        location.requestResult = .success(.authorized)

        let store = AppStore(
            permissionService: reminders,
            eventsPermissionService: events,
            contactsPermissionService: contacts,
            locationPermissionService: location
        )
        store.refreshStatus()

        #expect(store.hasPendingOSAccessRequest)

        await store.requestAllPendingAccess()

        #expect(reminders.requestCallCount == 1)
        #expect(events.requestCallCount == 1)
        #expect(contacts.requestCallCount == 1)
        #expect(location.requestCallCount == 1)
        #expect(store.permissionStatus == .authorized)
        #expect(store.calendarPermissionStatus == .authorized)
        #expect(store.contactsPermissionStatus == .authorized)
        #expect(store.locationPermissionStatus == .authorized)
        #expect(store.lastError == nil)
        #expect(!store.hasPendingOSAccessRequest)
        #expect(!store.isRequestingAnyOSAccess)
    }

    @Test
    @MainActor
    func requestAllPendingAccessSkipsGrantedAndDenied() async {
        let reminders = MockRemindersPermissionService()
        let events = MockEventsPermissionService()
        let contacts = MockContactsPermissionService()
        let location = MockLocationPermissionService()
        reminders.status = .authorized
        events.status = .denied
        contacts.status = .notDetermined
        location.status = .restricted
        contacts.requestResult = .success(.authorized)

        let store = AppStore(
            permissionService: reminders,
            eventsPermissionService: events,
            contactsPermissionService: contacts,
            locationPermissionService: location
        )
        store.refreshStatus()

        await store.requestAllPendingAccess()

        #expect(reminders.requestCallCount == 0)
        #expect(events.requestCallCount == 0)
        #expect(contacts.requestCallCount == 1)
        #expect(location.requestCallCount == 0)
        #expect(store.contactsPermissionStatus == .authorized)
    }

    @Test
    @MainActor
    func requestAllPendingAccessStopsOnFirstError() async {
        let reminders = MockRemindersPermissionService()
        let events = MockEventsPermissionService()
        let contacts = MockContactsPermissionService()
        let location = MockLocationPermissionService()
        reminders.status = .notDetermined
        events.status = .notDetermined
        contacts.status = .notDetermined
        location.status = .notDetermined
        reminders.requestResult = .success(.authorized)
        events.requestResult = .failure(EventsPermissionError.requestFailed("calendar blocked"))
        contacts.requestResult = .success(.authorized)
        location.requestResult = .success(.authorized)

        let store = AppStore(
            permissionService: reminders,
            eventsPermissionService: events,
            contactsPermissionService: contacts,
            locationPermissionService: location
        )
        store.refreshStatus()

        await store.requestAllPendingAccess()

        #expect(reminders.requestCallCount == 1)
        #expect(events.requestCallCount == 1)
        #expect(contacts.requestCallCount == 0)
        #expect(location.requestCallCount == 0)
        #expect(store.lastError == "calendar blocked")
    }

    @Test
    @MainActor
    func requestAllPendingAccessNoOpsWhenNothingPending() async {
        let reminders = MockRemindersPermissionService()
        let events = MockEventsPermissionService()
        let contacts = MockContactsPermissionService()
        let location = MockLocationPermissionService()
        reminders.status = .authorized
        events.status = .denied
        contacts.status = .restricted
        location.status = .authorized

        let store = AppStore(
            permissionService: reminders,
            eventsPermissionService: events,
            contactsPermissionService: contacts,
            locationPermissionService: location
        )
        store.refreshStatus()

        #expect(!store.hasPendingOSAccessRequest)

        await store.requestAllPendingAccess()

        #expect(reminders.requestCallCount == 0)
        #expect(events.requestCallCount == 0)
        #expect(contacts.requestCallCount == 0)
        #expect(location.requestCallCount == 0)
    }

    @Test
    @MainActor
    func requestAllPendingAccessTreatsUnknownAsRequestable() async {
        let reminders = MockRemindersPermissionService()
        let events = MockEventsPermissionService()
        let contacts = MockContactsPermissionService()
        let location = MockLocationPermissionService()
        // Default store statuses are .unknown without refresh; only contacts service will be hit
        // if we leave store at defaults... actually requestable uses store state, all unknown.
        reminders.status = .notDetermined
        events.status = .notDetermined
        contacts.status = .notDetermined
        location.status = .notDetermined
        reminders.requestResult = .success(.authorized)
        events.requestResult = .success(.authorized)
        contacts.requestResult = .success(.authorized)
        location.requestResult = .success(.authorized)

        let store = AppStore(
            permissionService: reminders,
            eventsPermissionService: events,
            contactsPermissionService: contacts,
            locationPermissionService: location
        )
        // Do not refresh — store remains .unknown for all four
        #expect(store.hasPendingOSAccessRequest)

        await store.requestAllPendingAccess()

        #expect(reminders.requestCallCount == 1)
        #expect(events.requestCallCount == 1)
        #expect(contacts.requestCallCount == 1)
        #expect(location.requestCallCount == 1)
    }
}
