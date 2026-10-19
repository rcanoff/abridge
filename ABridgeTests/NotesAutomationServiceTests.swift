@testable import ABridge
import CoreServices
import Foundation
import Testing

@Suite("NotesAutomationService")
struct NotesAutomationServiceTests {
    @Test
    @MainActor
    func currentStatusDoesNotSendConsentEvent() {
        let events = CallCounter()
        let service = NotesAutomationService(
            determinePermission: { OSStatus(errAEEventWouldRequireUserConsent) },
            sendConsentEvent: { events.increment() },
            launchNotesIfNeeded: {}
        )

        #expect(service.currentStatus() == .notDetermined)
        #expect(events.value == 0)
    }

    @Test
    @MainActor
    func requestAccessLaunchesNotesSendsEventThenReadsStatus() async throws {
        let events = CallCounter()
        let launches = CallCounter()
        let service = NotesAutomationService(
            determinePermission: { events.value == 1 ? noErr : OSStatus(errAEEventWouldRequireUserConsent) },
            sendConsentEvent: { events.increment() },
            launchNotesIfNeeded: { launches.increment() }
        )

        let status = try await service.requestAccess()

        #expect(status == .granted)
        #expect(launches.value == 1)
        #expect(events.value == 1)
    }

    @Test
    @MainActor
    func requestAccessReportsDenialAfterEvent() async throws {
        let service = NotesAutomationService(
            determinePermission: { OSStatus(errAEEventNotPermitted) },
            sendConsentEvent: {},
            launchNotesIfNeeded: {}
        )

        #expect(try await service.requestAccess() == .denied)
    }

    @Test
    @MainActor
    func requestAccessPropagatesLaunchFailure() async {
        let events = CallCounter()
        let service = NotesAutomationService(
            determinePermission: { noErr },
            sendConsentEvent: { events.increment() },
            launchNotesIfNeeded: { throw StubFailure() }
        )

        await #expect(throws: StubFailure.self) {
            try await service.requestAccess()
        }
        #expect(events.value == 0)
    }

    @Test
    @MainActor
    func requestAccessPropagatesEventFailure() async {
        let service = NotesAutomationService(
            determinePermission: { noErr },
            sendConsentEvent: { throw StubFailure() },
            launchNotesIfNeeded: {}
        )

        await #expect(throws: StubFailure.self) {
            try await service.requestAccess()
        }
    }
}

private struct StubFailure: Error, Equatable {}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
