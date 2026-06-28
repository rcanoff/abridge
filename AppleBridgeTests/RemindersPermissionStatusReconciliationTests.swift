@testable import AppleBridge
import Testing

@Suite("RemindersPermissionStatusReconciliation")
struct PermissionStatusReconciliationTests {
    @Test
    func preservesAuthorizedWhenEventKitStatusIsStaleAfterGrant() {
        let state = RemindersPermissionStatusReconciliation.State(sessionGrantConfirmed: true)

        let resolved = RemindersPermissionStatusReconciliation.resolve(
            eventKitStatus: .notDetermined,
            state: state
        )

        #expect(resolved.status == .authorized)
        #expect(resolved.state.sessionGrantConfirmed)
    }

    @Test
    func clearsSessionGrantWhenEventKitReportsDenied() {
        let state = RemindersPermissionStatusReconciliation.State(sessionGrantConfirmed: true)

        let resolved = RemindersPermissionStatusReconciliation.resolve(
            eventKitStatus: .denied,
            state: state
        )

        #expect(resolved.status == .denied)
        #expect(resolved.state.sessionGrantConfirmed == false)
    }

    @Test
    func confirmsGrantWhenEventKitReportsFullAccess() {
        let state = RemindersPermissionStatusReconciliation.State(sessionGrantConfirmed: false)

        let resolved = RemindersPermissionStatusReconciliation.resolve(
            eventKitStatus: .authorized,
            state: state
        )

        #expect(resolved.status == .authorized)
        #expect(resolved.state.sessionGrantConfirmed)
    }

    @Test
    func afterRequestRecordsGrantedReadAccess() {
        let state = RemindersPermissionStatusReconciliation.afterRequest(
            result: .authorized,
            state: RemindersPermissionStatusReconciliation.State(sessionGrantConfirmed: false)
        )

        #expect(state.sessionGrantConfirmed)
    }
}
