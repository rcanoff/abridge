@testable import ABridge
import Testing

@Suite("LocationPermissionStatusReconciliation")
struct LocationPermissionReconciliationTests {
    @Test
    func preservesAuthorizedWhenSystemStatusIsStaleAfterGrant() {
        let state = LocationPermissionStatusReconciliation.State(sessionGrantConfirmed: true)

        let resolved = LocationPermissionStatusReconciliation.resolve(
            systemStatus: .notDetermined,
            state: state
        )

        #expect(resolved.status == .authorized)
        #expect(resolved.state.sessionGrantConfirmed)
    }

    @Test
    func preservesAuthorizedWhenSystemStatusIsUnknownAfterGrant() {
        let state = LocationPermissionStatusReconciliation.State(sessionGrantConfirmed: true)

        let resolved = LocationPermissionStatusReconciliation.resolve(
            systemStatus: .unknown,
            state: state
        )

        #expect(resolved.status == .authorized)
        #expect(resolved.state.sessionGrantConfirmed)
    }

    @Test
    func clearsSessionGrantWhenSystemReportsDenied() {
        let state = LocationPermissionStatusReconciliation.State(sessionGrantConfirmed: true)

        let resolved = LocationPermissionStatusReconciliation.resolve(
            systemStatus: .denied,
            state: state
        )

        #expect(resolved.status == .denied)
        #expect(resolved.state.sessionGrantConfirmed == false)
    }

    @Test
    func confirmsGrantWhenSystemReportsAuthorized() {
        let state = LocationPermissionStatusReconciliation.State(sessionGrantConfirmed: false)

        let resolved = LocationPermissionStatusReconciliation.resolve(
            systemStatus: .authorized,
            state: state
        )

        #expect(resolved.status == .authorized)
        #expect(resolved.state.sessionGrantConfirmed)
    }

    @Test
    func afterRequestRecordsGrantedReadAccess() {
        let state = LocationPermissionStatusReconciliation.afterRequest(
            result: .authorized,
            state: LocationPermissionStatusReconciliation.State(sessionGrantConfirmed: false)
        )

        #expect(state.sessionGrantConfirmed)
    }
}
