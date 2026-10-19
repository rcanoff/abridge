@testable import ABridge
import CoreServices
import Testing

@Suite("NotesAutomationStatus")
struct NotesAutomationStatusTests {
    @Test
    func mapNoErrorIsGranted() {
        let status = NotesAutomationStatusMapper.map(noErr)
        #expect(status == .granted)
        #expect(status.isDenied == false)
    }

    @Test
    func mapEventNotPermittedIsDenied() {
        let status = NotesAutomationStatusMapper.map(OSStatus(errAEEventNotPermitted))
        #expect(status == .denied)
        #expect(status.isDenied)
        #expect(status.displayName == "Denied")
    }

    @Test
    func mapWouldRequireUserConsentIsNotDetermined() {
        let status = NotesAutomationStatusMapper.map(OSStatus(errAEEventWouldRequireUserConsent))
        #expect(status == .notDetermined)
        #expect(status.displayName == "Not determined")
    }

    @Test
    func mapProcessNotFoundIsUnknown() {
        let status = NotesAutomationStatusMapper.map(OSStatus(procNotFound))
        #expect(status == .unknown)
        #expect(status.displayName == "Notes not running")
    }

    @Test
    func mapUnexpectedStatusIsUnknown() {
        #expect(NotesAutomationStatusMapper.map(-1) == .unknown)
    }
}
