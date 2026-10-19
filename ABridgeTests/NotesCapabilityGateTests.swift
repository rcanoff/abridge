@testable import ABridge
import Foundation
import Testing

@Suite("NotesCapabilityGate")
struct NotesCapabilityGateTests {
    private let enabled = [
        "notes.read",
        "notes.search",
        "notes.create",
        "notes.edit",
        "notes.delete",
    ]

    @Test
    func sendsNothingWithoutFullDiskAccess() {
        #expect(
            NotesCapabilityGate.serverCapabilityIDs(
                enabled: enabled,
                fullDiskAccessGranted: false,
                automationDenied: false
            ).isEmpty
        )
        #expect(
            NotesCapabilityGate.serverCapabilityIDs(
                enabled: enabled,
                fullDiskAccessGranted: false,
                automationDenied: true
            ).isEmpty
        )
    }

    @Test
    func sendsReadsAndWritesWhenFullDiskAccessIsGrantedAndAutomationIsNotDenied() {
        let notDetermined = NotesCapabilityGate.serverCapabilityIDs(
            enabled: enabled,
            fullDiskAccessGranted: true,
            automationDenied: false
        )
        #expect(notDetermined == enabled)
    }

    @Test
    func sendsOnlyReadsWhenAutomationIsDenied() {
        #expect(
            NotesCapabilityGate.serverCapabilityIDs(
                enabled: enabled,
                fullDiskAccessGranted: true,
                automationDenied: true
            ) == ["notes.read", "notes.search"]
        )
    }

    @Test
    func preservesEnabledOrderAndDropsUnknownIDs() {
        let sent = NotesCapabilityGate.serverCapabilityIDs(
            enabled: ["notes.delete", "notes.read", "other.capability"],
            fullDiskAccessGranted: true,
            automationDenied: false
        )
        #expect(sent == ["notes.delete", "notes.read"])
    }

    @Test
    func checkedAccessBlocksWritesOnlyAfterFullDiskAccessWhenAutomationIsDenied() {
        let reads = ["notes.read", "notes.search"]
        let writes = ["notes.create", "notes.edit", "notes.delete"]

        #expect(
            NotesCapabilityGate.access(
                for: reads + writes,
                fullDiskAccessGranted: false,
                automationDenied: true
            ) == NotesCapabilityAccess(sendsAll: false, blocksWrites: false)
        )
        #expect(
            NotesCapabilityGate.access(
                for: reads,
                fullDiskAccessGranted: true,
                automationDenied: true
            ) == NotesCapabilityAccess(sendsAll: true, blocksWrites: false)
        )
        #expect(
            NotesCapabilityGate.access(
                for: writes,
                fullDiskAccessGranted: true,
                automationDenied: true
            ) == NotesCapabilityAccess(sendsAll: false, blocksWrites: true)
        )
        #expect(
            NotesCapabilityGate.access(
                for: writes,
                fullDiskAccessGranted: true,
                automationDenied: false
            ) == NotesCapabilityAccess(sendsAll: true, blocksWrites: false)
        )
    }

    @Test
    @MainActor
    func losingAutomationAndFullDiskAccessRemovesNotesCapabilitiesFromServer() async throws {
        try await assertLosingNotesGrantsRemovesCapabilities(priorAutomation: .granted, label: "granted")
        try await assertLosingNotesGrantsRemovesCapabilities(
            priorAutomation: .notDetermined,
            label: "notDetermined"
        )
    }
}

@MainActor
private func assertLosingNotesGrantsRemovesCapabilities(
    priorAutomation: NotesAutomationStatus,
    label: String
) async throws {
    let harness = try await makeNotesGrantLossHarness(label: label)
    let reads = NotesCapabilityGate.readCapabilityIDs
    let writes = NotesCapabilityGate.writeCapabilityIDs
    let allowed = notesAccessGrant(fullDiskAccess: .granted, automation: priorAutomation)

    await applyNotesGrant(allowed, to: harness.settingsStore)
    let advertised = try await notesCapabilityIDs(sentBy: harness.mock)
    #expect(advertised.isSuperset(of: reads.union(writes)), "\(label) advertises writes")

    let automationDenied = notesAccessGrant(fullDiskAccess: .granted, automation: .denied)
    try #require(
        notesGrantShouldReapply(from: allowed, to: automationDenied, permissions: harness.permissions),
        "\(label) -> denied"
    )
    await applyNotesGrant(automationDenied, to: harness.settingsStore)
    let afterAutomationLoss = try await notesCapabilityIDs(sentBy: harness.mock)
    #expect(afterAutomationLoss.isSuperset(of: reads), "\(label) keeps reads")
    #expect(afterAutomationLoss.isDisjoint(with: writes), "\(label) drops writes")

    await applyNotesGrant(allowed, to: harness.settingsStore)
    let fullDiskLost = notesAccessGrant(fullDiskAccess: .notGranted, automation: priorAutomation)
    try #require(
        notesGrantShouldReapply(from: allowed, to: fullDiskLost, permissions: harness.permissions),
        "\(label) loses Full Disk Access"
    )
    await applyNotesGrant(fullDiskLost, to: harness.settingsStore)
    let afterFullDiskLoss = try await notesCapabilityIDs(sentBy: harness.mock)
    #expect(afterFullDiskLoss.isDisjoint(with: reads.union(writes)), "\(label) drops Notes caps")
}

@MainActor
private func makeNotesGrantLossHarness(label: String) async throws -> NotesGrantLossHarness {
    let suiteName = "NotesCapabilityGateTests.notesGrantLoss.\(label)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)
    appSettings.mcpEnabled = true
    appSettings.saveCapabilityIDs(Set(CapabilityCatalog.notesCapabilities.map(\.id)))

    let mock = MockServerService()
    await mock.setRefreshResult(.running)
    let serverStore = ServerStore(serverService: mock)
    await serverStore.startServer(port: 3020, enabledCapabilities: [])
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: serverStore,
        notesFullDiskAccessService: MockNotesFullDiskAccessService(),
        notesAutomationService: MockNotesAutomationService()
    )
    return NotesGrantLossHarness(
        settingsStore: settingsStore,
        mock: mock,
        permissions: PermissionsStore(appSettings: appSettings)
    )
}

@MainActor
private struct NotesGrantLossHarness {
    let settingsStore: SettingsStore
    let mock: MockServerService
    let permissions: PermissionsStore
}

@MainActor
private func notesAccessGrant(
    fullDiskAccess: NotesFullDiskAccessStatus,
    automation: NotesAutomationStatus
) -> NotesAccessGrant {
    NotesAccessGrant(
        fullDiskAccessGranted: fullDiskAccess.grantsAccess,
        automationAllowsWrite: !automation.isDenied
    )
}

@MainActor
private func notesGrantShouldReapply(
    from previous: NotesAccessGrant,
    to current: NotesAccessGrant,
    permissions: PermissionsStore
) -> Bool {
    NotesAccessGrantReconciliation.shouldReapply(
        previous: previous,
        current: current,
        requiresNotesAccess: permissions.requiresAppleNotesAccess,
        requiresNotesWriteAccess: permissions.requiresAppleNotesWriteAccess
    )
}

@MainActor
private func applyNotesGrant(_ grant: NotesAccessGrant, to settingsStore: SettingsStore) async {
    await settingsStore.applySavedCapabilities(
        remindersAuthorized: false,
        eventsAuthorized: false,
        contactsAuthorized: false,
        locationAuthorized: false,
        notesFullDiskAccessGranted: grant.fullDiskAccessGranted,
        notesAutomationDenied: !grant.automationAllowsWrite
    )
}

private func notesCapabilityIDs(sentBy mock: MockServerService) async throws -> Set<String> {
    let sent = try #require(await mock.lastEnabledCapabilities)
    return Set(sent.filter { $0.hasPrefix("notes.") })
}
