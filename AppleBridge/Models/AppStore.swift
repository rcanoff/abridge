import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    private(set) var permissionStatus: RemindersPermissionStatus = .unknown
    private(set) var isRequestingPermission = false
    private(set) var calendarPermissionStatus: EventsPermissionStatus = .unknown
    private(set) var isRequestingCalendarPermission = false
    private(set) var contactsPermissionStatus: ContactsPermissionStatus = .unknown
    private(set) var isRequestingContactsPermission = false
    private(set) var lastError: String?

    private let permissionService: any RemindersPermissionChecking
    private let eventsPermissionService: any EventsPermissionChecking
    private let contactsPermissionService: any ContactsPermissionChecking
    private let urlOpener: any URLOpening

    init(
        permissionService: any RemindersPermissionChecking = RemindersPermissionService(),
        eventsPermissionService: any EventsPermissionChecking = EventsPermissionService(),
        contactsPermissionService: any ContactsPermissionChecking = ContactsPermissionService(),
        urlOpener: any URLOpening = NSWorkspace.shared
    ) {
        self.permissionService = permissionService
        self.eventsPermissionService = eventsPermissionService
        self.contactsPermissionService = contactsPermissionService
        self.urlOpener = urlOpener
    }

    func refreshStatus() {
        lastError = nil
        permissionStatus = permissionService.currentStatus()
        calendarPermissionStatus = eventsPermissionService.currentStatus()
        contactsPermissionStatus = contactsPermissionService.currentStatus()
    }

    func refreshCalendarStatus() {
        lastError = nil
        calendarPermissionStatus = eventsPermissionService.currentStatus()
    }

    func refreshContactsStatus() {
        lastError = nil
        contactsPermissionStatus = contactsPermissionService.currentStatus()
    }

    func requestAccess() async {
        guard !isRequestingPermission else { return }

        isRequestingPermission = true
        lastError = nil

        defer { isRequestingPermission = false }

        do {
            permissionStatus = try await permissionService.requestAccess()
        } catch {
            refreshStatus()
            lastError = error.localizedDescription
        }
    }

    func requestCalendarAccess() async {
        guard !isRequestingCalendarPermission else { return }

        isRequestingCalendarPermission = true
        lastError = nil

        defer { isRequestingCalendarPermission = false }

        do {
            calendarPermissionStatus = try await eventsPermissionService.requestAccess()
        } catch {
            refreshCalendarStatus()
            lastError = error.localizedDescription
        }
    }

    func requestContactsAccess() async {
        guard !isRequestingContactsPermission else { return }

        isRequestingContactsPermission = true
        lastError = nil

        defer { isRequestingContactsPermission = false }

        do {
            contactsPermissionStatus = try await contactsPermissionService.requestAccess()
        } catch {
            refreshContactsStatus()
            lastError = error.localizedDescription
        }
    }

    func openRemindersPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Reminders"
        ) else {
            lastError = "Unable to open Reminders privacy settings."
            return
        }

        guard urlOpener.open(url) else {
            lastError = "Unable to open Reminders privacy settings."
            return
        }

        lastError = nil
    }

    func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
        ) else {
            lastError = "Unable to open Calendars privacy settings."
            return
        }

        guard urlOpener.open(url) else {
            lastError = "Unable to open Calendars privacy settings."
            return
        }

        lastError = nil
    }

    func openContactsPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Contacts"
        ) else {
            lastError = "Unable to open Contacts privacy settings."
            return
        }

        guard urlOpener.open(url) else {
            lastError = "Unable to open Contacts privacy settings."
            return
        }

        lastError = nil
    }
}
