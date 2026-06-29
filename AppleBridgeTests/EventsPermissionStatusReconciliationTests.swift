@testable import AppleBridge
import Testing

@Suite("EventsPermissionStatusReconciliation")
struct EventsPermissionReconciliationTests {
    @Test
    func preservesAuthorizedWhenEventKitStatusIsStaleAfterGrant() {
        let state = EventsPermissionStatusReconciliation.State(sessionGrantConfirmed: true)

        let resolved = EventsPermissionStatusReconciliation.resolve(
            eventKitStatus: .notDetermined,
            state: state
        )

        #expect(resolved.status == .authorized)
        #expect(resolved.state.sessionGrantConfirmed)
    }

    @Test
    func clearsSessionGrantWhenEventKitReportsDenied() {
        let state = EventsPermissionStatusReconciliation.State(sessionGrantConfirmed: true)

        let resolved = EventsPermissionStatusReconciliation.resolve(
            eventKitStatus: .denied,
            state: state
        )

        #expect(resolved.status == .denied)
        #expect(resolved.state.sessionGrantConfirmed == false)
    }

    @Test
    func confirmsGrantWhenEventKitReportsFullAccess() {
        let state = EventsPermissionStatusReconciliation.State(sessionGrantConfirmed: false)

        let resolved = EventsPermissionStatusReconciliation.resolve(
            eventKitStatus: .authorized,
            state: state
        )

        #expect(resolved.status == .authorized)
        #expect(resolved.state.sessionGrantConfirmed)
    }

    @Test
    func clearsSessionGrantWhenEventKitReportsWriteOnly() {
        let state = EventsPermissionStatusReconciliation.State(sessionGrantConfirmed: true)

        let resolved = EventsPermissionStatusReconciliation.resolve(
            eventKitStatus: .writeOnly,
            state: state
        )

        #expect(resolved.status == .writeOnly)
        #expect(resolved.state.sessionGrantConfirmed == false)
    }

    @Test
    func afterRequestRecordsGrantedReadAccess() {
        let state = EventsPermissionStatusReconciliation.afterRequest(
            result: .authorized,
            state: EventsPermissionStatusReconciliation.State(sessionGrantConfirmed: false)
        )

        #expect(state.sessionGrantConfirmed)
    }
}
