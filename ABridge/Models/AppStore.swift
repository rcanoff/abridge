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
    private(set) var locationPermissionStatus: LocationPermissionStatus = .unknown
    private(set) var isRequestingLocationPermission = false
    private(set) var isRequestingAllPendingAccess = false
    private(set) var lastError: String?

    private let permissionService: any RemindersPermissionChecking
    private let eventsPermissionService: any EventsPermissionChecking
    private let contactsPermissionService: any ContactsPermissionChecking
    private let locationPermissionService: any LocationPermissionChecking
    private let urlOpener: any URLOpening

    /// True when any OS-backed permission can still show a system prompt (`notDetermined` / `unknown`).
    var hasPendingOSAccessRequest: Bool {
        Self.isStillRequestable(permissionStatus)
            || Self.isStillRequestable(calendarPermissionStatus)
            || Self.isStillRequestable(contactsPermissionStatus)
            || Self.isStillRequestable(locationPermissionStatus)
    }

    /// True while any single or batch OS access request is in flight.
    var isRequestingAnyOSAccess: Bool {
        isRequestingAllPendingAccess
            || isRequestingPermission
            || isRequestingCalendarPermission
            || isRequestingContactsPermission
            || isRequestingLocationPermission
    }

    init(
        permissionService: any RemindersPermissionChecking = RemindersPermissionService(),
        eventsPermissionService: any EventsPermissionChecking = EventsPermissionService(),
        contactsPermissionService: any ContactsPermissionChecking = ContactsPermissionService(),
        locationPermissionService: any LocationPermissionChecking = LocationPermissionService(),
        urlOpener: any URLOpening = NSWorkspace.shared
    ) {
        self.permissionService = permissionService
        self.eventsPermissionService = eventsPermissionService
        self.contactsPermissionService = contactsPermissionService
        self.locationPermissionService = locationPermissionService
        self.urlOpener = urlOpener
    }

    func refreshStatus() {
        lastError = nil
        permissionStatus = permissionService.currentStatus()
        calendarPermissionStatus = eventsPermissionService.currentStatus()
        contactsPermissionStatus = contactsPermissionService.currentStatus()
        locationPermissionStatus = locationPermissionService.currentStatus()
    }

    func refreshCalendarStatus() {
        lastError = nil
        calendarPermissionStatus = eventsPermissionService.currentStatus()
    }

    func refreshContactsStatus() {
        lastError = nil
        contactsPermissionStatus = contactsPermissionService.currentStatus()
    }

    func refreshLocationStatus() {
        lastError = nil
        locationPermissionStatus = locationPermissionService.currentStatus()
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

    func requestLocationAccess() async {
        guard !isRequestingLocationPermission else { return }

        isRequestingLocationPermission = true
        lastError = nil

        defer { isRequestingLocationPermission = false }

        do {
            locationPermissionStatus = try await locationPermissionService.requestAccess()
        } catch {
            refreshLocationStatus()
            lastError = error.localizedDescription
        }
    }

    /// Sequentially requests remaining OS privacy prompts: Reminders → Calendars → Contacts → Location.
    /// Skips already decided statuses; stops on first error (`lastError`). Does not change MCP capability toggles.
    func requestAllPendingAccess() async {
        guard !isRequestingAllPendingAccess else { return }
        guard hasPendingOSAccessRequest else { return }

        isRequestingAllPendingAccess = true
        defer { isRequestingAllPendingAccess = false }

        if Self.isStillRequestable(permissionStatus) {
            await requestAccess()
            if lastError != nil {
                return
            }
        }
        if Self.isStillRequestable(calendarPermissionStatus) {
            await requestCalendarAccess()
            if lastError != nil {
                return
            }
        }
        if Self.isStillRequestable(contactsPermissionStatus) {
            await requestContactsAccess()
            if lastError != nil {
                return
            }
        }
        if Self.isStillRequestable(locationPermissionStatus) {
            await requestLocationAccess()
            if lastError != nil {
                return
            }
        }
    }

    static func isStillRequestable(_ status: RemindersPermissionStatus) -> Bool {
        switch status {
        case .unknown, .notDetermined: true
        case .authorized, .writeOnly, .denied, .restricted: false
        }
    }

    static func isStillRequestable(_ status: EventsPermissionStatus) -> Bool {
        switch status {
        case .unknown, .notDetermined: true
        case .authorized, .writeOnly, .denied, .restricted: false
        }
    }

    static func isStillRequestable(_ status: ContactsPermissionStatus) -> Bool {
        switch status {
        case .unknown, .notDetermined: true
        case .authorized, .limited, .denied, .restricted: false
        }
    }

    static func isStillRequestable(_ status: LocationPermissionStatus) -> Bool {
        switch status {
        case .unknown, .notDetermined: true
        case .authorized, .authorizedAlways, .denied, .restricted: false
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

    func openLocationPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices"
        ) else {
            lastError = "Unable to open Location privacy settings."
            return
        }

        guard urlOpener.open(url) else {
            lastError = "Unable to open Location privacy settings."
            return
        }

        lastError = nil
    }
}
