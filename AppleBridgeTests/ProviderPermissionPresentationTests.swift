@testable import AppleBridge
import Testing

@Suite("ProviderPermissionPresentation")
struct ProviderPermissionPresentationTests {
    @Test
    func statusNotInUseWhenNoCaps() {
        let s = ProviderPermissionStatus.compute(
            checkedShippedCount: 0,
            needsOSAccess: true,
            osGrantsReadAccess: false,
            osIsDeniedOrRestricted: false
        )
        #expect(s == .notInUse)
    }

    @Test
    func statusReadyWhenCapsAndAuthorized() {
        let s = ProviderPermissionStatus.compute(
            checkedShippedCount: 3,
            needsOSAccess: true,
            osGrantsReadAccess: true,
            osIsDeniedOrRestricted: false
        )
        #expect(s == .ready)
    }

    @Test
    func statusNeedsAccessWhenNotDetermined() {
        let s = ProviderPermissionStatus.compute(
            checkedShippedCount: 2,
            needsOSAccess: true,
            osGrantsReadAccess: false,
            osIsDeniedOrRestricted: false
        )
        #expect(s == .needsAccess)
    }

    @Test
    func statusBlockedWhenDenied() {
        let s = ProviderPermissionStatus.compute(
            checkedShippedCount: 1,
            needsOSAccess: true,
            osGrantsReadAccess: false,
            osIsDeniedOrRestricted: true
        )
        #expect(s == .blocked)
    }

    @Test
    func statusReadyForVisionWithoutOS() {
        let s = ProviderPermissionStatus.compute(
            checkedShippedCount: 2,
            needsOSAccess: false,
            osGrantsReadAccess: false,
            osIsDeniedOrRestricted: false
        )
        #expect(s == .ready)
    }

    @Test
    func masterOffOnMixed() {
        #expect(ProviderMasterState.compute(checked: 0, totalShipped: 5) == .off)
        #expect(ProviderMasterState.compute(checked: 5, totalShipped: 5) == .on)
        #expect(ProviderMasterState.compute(checked: 2, totalShipped: 5) == .mixed)
    }
}
