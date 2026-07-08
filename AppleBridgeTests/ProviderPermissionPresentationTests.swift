@testable import AppleBridge
import Testing

@Suite("ProviderPermissionPresentation")
struct ProviderPermissionPresentationTests {
    @Test
    func statusNotInUseWhenNoCaps() {
        let status = ProviderPermissionStatus.compute(
            checkedShippedCount: 0,
            needsOSAccess: true,
            osGrantsReadAccess: false,
            osIsDeniedOrRestricted: false
        )
        #expect(status == .notInUse)
    }

    @Test
    func statusReadyWhenCapsAndAuthorized() {
        let status = ProviderPermissionStatus.compute(
            checkedShippedCount: 3,
            needsOSAccess: true,
            osGrantsReadAccess: true,
            osIsDeniedOrRestricted: false
        )
        #expect(status == .ready)
    }

    @Test
    func statusNeedsAccessWhenNotDetermined() {
        let status = ProviderPermissionStatus.compute(
            checkedShippedCount: 2,
            needsOSAccess: true,
            osGrantsReadAccess: false,
            osIsDeniedOrRestricted: false
        )
        #expect(status == .needsAccess)
    }

    @Test
    func statusBlockedWhenDenied() {
        let status = ProviderPermissionStatus.compute(
            checkedShippedCount: 1,
            needsOSAccess: true,
            osGrantsReadAccess: false,
            osIsDeniedOrRestricted: true
        )
        #expect(status == .blocked)
    }

    @Test
    func statusReadyForVisionWithoutOS() {
        let status = ProviderPermissionStatus.compute(
            checkedShippedCount: 2,
            needsOSAccess: false,
            osGrantsReadAccess: false,
            osIsDeniedOrRestricted: false
        )
        #expect(status == .ready)
    }

    @Test
    func enableStateOffOnMixed() {
        #expect(ProviderEnableState.compute(checked: 0, totalShipped: 5) == .off)
        #expect(ProviderEnableState.compute(checked: 5, totalShipped: 5) == .on)
        #expect(ProviderEnableState.compute(checked: 2, totalShipped: 5) == .mixed)
    }
}
