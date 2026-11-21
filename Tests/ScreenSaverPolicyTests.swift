import Foundation
import Testing

private final class SaverSettings: ScreenSaverSettings {
    var seconds = 1_200
    var eligible = true
    var accessError: ScreenSaverAccessError?
    var rejectedValue: Int?
    var errorAfterWriting: Int?
    var unplugAfterWriting: Int?
    var externalChangeAfterWriting: Int?
    var ignoreWrites = false
    var writes: [Int] = []

    func idleSeconds() throws -> Int {
        if let accessError { throw accessError }
        return seconds
    }

    func setIdleSeconds(_ seconds: Int) throws {
        if rejectedValue == seconds { throw ScreenSaverAccessError.unavailable }
        writes.append(seconds)
        if !ignoreWrites { self.seconds = seconds }
        if let externalChangeAfterWriting {
            self.seconds = externalChangeAfterWriting
            self.externalChangeAfterWriting = nil
        }
        if unplugAfterWriting == seconds { eligible = false }
        if errorAfterWriting == seconds { throw ScreenSaverAccessError.unavailable }
    }
}

private final class SaverJournal: ScreenSaverRecoveryJournal {
    var value: ScreenSaverRecovery?
    var failToSave = false

    func load() throws -> ScreenSaverRecovery? { value }
    func save(_ recovery: ScreenSaverRecovery) throws {
        if failToSave { throw CocoaError(.fileWriteUnknown) }
        value = recovery
    }
    func clear() throws { value = nil }
}

private struct SaverSession {
    let settings = SaverSettings()
    let journal = SaverJournal()
    let client = UUID()
    let policy: ScreenSaverPolicy
    let fourHours = 14_400

    init() {
        policy = ScreenSaverPolicy(settings: settings, journal: journal, isEligible: { [settings] in settings.eligible })
    }

    @discardableResult
    func apply(_ minimum: Int? = nil) -> ScreenSaverStatus {
        policy.apply(client: client, minimumSeconds: minimum ?? fourHours)
    }
}

@Test func screenSaverDelayIsRestoredOnBatteryAndReappliedWithANewBaseline() {
    let session = SaverSession()
    #expect(session.apply() == .synchronized)
    #expect(session.apply() == .synchronized)
    #expect(session.settings.writes == [14_400])

    session.settings.eligible = false
    session.policy.refresh()
    #expect(session.settings.seconds == 1_200)
    #expect(session.journal.value == nil)
    #expect(session.apply() == .inactive)

    session.settings.seconds = 1_800
    session.settings.eligible = true
    #expect(session.apply() == .synchronized)
    #expect(session.journal.value?.originalSeconds == 1_800)
    #expect(session.policy.release(client: session.client) == .inactive)
    #expect(session.settings.writes == [14_400, 1_200, 14_400, 1_800])
}

@Test func quickReconnectWaitsForAnUnfinishedScreenSaverRestore() {
    let session = SaverSession()
    session.apply()
    session.settings.rejectedValue = 1_200
    session.settings.eligible = false
    session.policy.refresh()
    #expect(session.policy.restorePending)

    session.settings.eligible = true
    #expect(session.apply(28_800) == .restorePending)
    #expect(session.settings.writes == [14_400])

    session.settings.rejectedValue = nil
    #expect(session.apply(28_800) == .synchronized)
    #expect(session.settings.writes == [14_400, 1_200, 28_800])
    #expect(session.journal.value?.originalSeconds == 1_200)
}

@Test func screenSaverDisconnectAndAgentRestartCanRestoreTheOwnerSetting() {
    let session = SaverSession()
    session.apply()
    session.policy.disconnect(client: UUID())
    #expect(session.settings.seconds == 14_400)
    session.policy.disconnect(client: session.client)
    #expect(session.settings.seconds == 1_200)
    #expect(session.journal.value == nil)

    session.apply()
    let restarted = ScreenSaverPolicy(settings: session.settings, journal: session.journal, isEligible: { true })
    #expect(restarted.release() == .inactive)
    #expect(session.settings.seconds == 1_200)
    #expect(session.journal.value == nil)
}

@Test(arguments: [0, 14_400, 28_800])
func screenSaverSettingsThatAlreadyFitAreLeftInPlace(seconds: Int) {
    let session = SaverSession()
    session.settings.seconds = seconds
    #expect(session.apply() == .synchronized)
    #expect(session.settings.writes.isEmpty)
    #expect(session.journal.value == nil)
}

@Test(arguments: [1_200, 28_800])
func screenSaverChangesMadeOutsideNoSleepAreRespected(originalSeconds: Int) {
    let session = SaverSession()
    session.settings.seconds = originalSeconds
    #expect(session.apply() == .synchronized)
    let expectedWrites = session.settings.writes

    session.settings.seconds = 600
    #expect(session.apply() == .settingsChanged)
    #expect(session.apply() == .settingsChanged)
    #expect(session.policy.release(client: session.client) == .inactive)
    #expect(session.settings.seconds == 600)
    #expect(session.settings.writes == expectedWrites)
    #expect(session.journal.value == nil)
}

@Test func shorteningIdleTimeReleasesAnUnneededScreenSaverOverride() {
    let session = SaverSession()
    session.apply()
    #expect(session.apply(10 * 60) == .synchronized)
    #expect(session.settings.seconds == 1_200)
    #expect(session.journal.value == nil)
}

@Test func screenSaverPrefersAnExternalChangeDuringWriteConfirmation() {
    let session = SaverSession()
    session.settings.externalChangeAfterWriting = 600
    #expect(session.apply() == .settingsChanged)
    #expect(session.apply() == .settingsChanged)
    #expect(session.policy.release(client: session.client) == .inactive)
    #expect(session.settings.seconds == 600)
    #expect(session.settings.writes == [14_400])
    #expect(session.journal.value == nil)
}

@Test func screenSaverPermissionRequiredOrDeniedLeavesSettingsIntact() {
    let session = SaverSession()
    session.settings.accessError = .authorizationRequired
    #expect(session.apply() == .authorizationRequired)
    session.settings.accessError = .permissionDenied
    #expect(session.apply() == .permissionDenied)
    #expect(session.settings.writes.isEmpty)
    #expect(session.journal.value == nil)
}

@Test func screenSaverRequiresDurableRecoveryAndSuccessfulReadBack() {
    let session = SaverSession()
    session.journal.failToSave = true
    #expect(session.apply() == .unavailable)
    #expect(session.settings.writes.isEmpty)

    session.journal.failToSave = false
    session.settings.ignoreWrites = true
    #expect(session.apply() == .unavailable)
    #expect(session.settings.seconds == 1_200)
    #expect(session.journal.value == nil)
}

@Test func screenSaverWriteThatReportsFailureStillRestoresTheOldValue() {
    let session = SaverSession()
    session.apply()
    session.settings.errorAfterWriting = 28_800
    #expect(session.apply(28_800) == .unavailable)
    #expect(session.settings.writes == [14_400, 28_800, 1_200])
    #expect(session.journal.value == nil)
}

@Test func losingExternalPowerDuringScreenSaverWriteRestoresTheOldValue() {
    let session = SaverSession()
    session.settings.unplugAfterWriting = 14_400
    #expect(session.apply() == .inactive)
    #expect(session.settings.writes == [14_400, 1_200])
    #expect(session.journal.value == nil)
}
