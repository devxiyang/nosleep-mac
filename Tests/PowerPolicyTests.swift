import Foundation
import Testing

private enum TestFailure: Error {
    case io
}

private final class MemorySettings: SystemPowerSettings {
    var disabled = false
    var minutes = 10
    var onAC = true
    var unplugWhileWritingDisplay = false
    var failSettingDisplay: Int?
    var writes: [String] = []

    func sleepDisabled() throws -> Bool { disabled }
    func acDisplayMinutes() throws -> Int { minutes }

    func setSleepDisabled(_ disabled: Bool) throws {
        writes.append("sleep=\(disabled)")
        self.disabled = disabled
    }

    func setACDisplayMinutes(_ minutes: Int) throws {
        if failSettingDisplay == minutes { throw TestFailure.io }
        writes.append("display=\(minutes)")
        self.minutes = minutes
        if unplugWhileWritingDisplay { onAC = false }
    }
}

private final class MemoryJournal: PowerRecoveryJournal {
    var recovery: PowerRecovery?
    var shouldFailSave = false

    func load() throws -> PowerRecovery? { recovery }
    func save(_ recovery: PowerRecovery) throws {
        if shouldFailSave { throw TestFailure.io }
        self.recovery = recovery
    }
    func clear() throws { recovery = nil }
}

private struct Rig {
    let settings = MemorySettings()
    let journal = MemoryJournal()
    let override: PowerOverride
    let policy: PowerPolicy
    let client = UUID()

    init() {
        override = PowerOverride(settings: settings, journal: journal)
        policy = PowerPolicy(override: override, onExternalPower: { [settings] in settings.onAC })
    }

    @discardableResult
    func enable(_ minutes: Int = 30) -> PowerModeStatus {
        policy.setMode(client: client, enabled: true, displayMinutes: minutes)
    }
}

@Test func enablesOnACAndRestoresBothSettingsOnUnplug() {
    let rig = Rig()
    #expect(rig.enable() == .active)
    #expect(rig.settings.disabled)
    #expect(rig.settings.minutes == 30)

    rig.settings.onAC = false
    rig.policy.refresh()
    #expect(rig.policy.status == .battery)
    #expect(!rig.settings.disabled)
    #expect(rig.settings.minutes == 10)
    #expect(rig.settings.writes.suffix(2) == ["display=10", "sleep=false"])
    #expect(rig.journal.recovery == nil)

    rig.settings.onAC = true
    rig.policy.refresh()
    #expect(rig.policy.status == .active)
    #expect(rig.settings.minutes == 30)
    #expect(rig.settings.disabled)
}

@Test func optingInOnBatteryDoesNotWritePowerSettings() {
    let rig = Rig()
    rig.settings.onAC = false
    #expect(rig.enable() == .battery)
    #expect(rig.settings.writes.isEmpty)
    #expect(rig.journal.recovery == nil)
}

@Test func turningOffRestoresPreviousDisplaySettingIncludingNever() {
    let rig = Rig()
    rig.settings.minutes = 0
    rig.enable()
    #expect(rig.policy.setMode(client: rig.client, enabled: false, displayMinutes: 0) == .off)
    #expect(!rig.settings.disabled)
    #expect(rig.settings.minutes == 0)
}

@Test func lostClientRestoresPowerSettings() {
    let rig = Rig()
    rig.enable()
    rig.policy.disconnect(client: UUID())
    #expect(rig.settings.disabled)

    rig.policy.disconnect(client: rig.client)
    #expect(rig.policy.status == .off)
    #expect(!rig.settings.disabled)
    #expect(rig.settings.minutes == 10)
}

@Test func preexistingOverrideIsLeftAlone() {
    let rig = Rig()
    rig.settings.disabled = true
    #expect(rig.enable() == .existingOverride)
    #expect(rig.settings.writes.isEmpty)
    #expect(rig.journal.recovery == nil)
    rig.policy.disconnect(client: rig.client)
    #expect(rig.settings.disabled)
}

@Test func currentOwnerCannotBeStoppedByAnotherClient() {
    let rig = Rig()
    rig.enable()
    let other = UUID()
    #expect(rig.policy.setMode(client: other, enabled: true, displayMinutes: 20) == .busy)
    #expect(rig.policy.setMode(client: other, enabled: false, displayMinutes: 0) == .busy)
    #expect(rig.settings.disabled)
}

@Test func externalDisplayChangeIsKept() {
    let rig = Rig()
    rig.enable()
    rig.settings.minutes = 45
    #expect(rig.policy.status(for: rig.client) == .settingsChanged)
    #expect(rig.settings.minutes == 45)
    #expect(!rig.settings.disabled)
    #expect(rig.journal.recovery == nil)
}

@Test func updatingTimerKeepsTheExistingSleepOverride() {
    let rig = Rig()
    rig.enable()
    #expect(rig.enable(90) == .active)
    #expect(rig.settings.writes == ["display=30", "sleep=true", "display=90"])

    rig.policy.disconnect(client: rig.client)
    #expect(rig.settings.minutes == 10)
    #expect(!rig.settings.disabled)
}

@Test func unpluggingMidActivationRollsBackWithoutDisablingSleep() {
    let rig = Rig()
    rig.settings.unplugWhileWritingDisplay = true
    #expect(rig.enable() == .battery)
    #expect(rig.settings.writes == ["display=30", "display=10"])
    #expect(!rig.settings.disabled)
    #expect(rig.journal.recovery == nil)
}

@Test func noWriteWhenRecoveryCannotBeRecorded() {
    let rig = Rig()
    rig.journal.shouldFailSave = true
    #expect(rig.enable() == .failed)
    #expect(rig.settings.writes.isEmpty)
}

@Test func restartCanRestoreAnInterruptedDurationEdit() {
    let rig = Rig()
    rig.journal.recovery = PowerRecovery(
        originalDisplayMinutes: 10, displayValues: [30, 60], mayOwnSleepOverride: true
    )
    rig.settings.disabled = true
    rig.settings.minutes = 30

    rig.policy.recover()

    #expect(rig.policy.status == .off)
    #expect(!rig.settings.disabled)
    #expect(rig.settings.minutes == 10)
    #expect(rig.journal.recovery == nil)
}

@Test func sleepIsRestoredEvenIfDisplayRestoreNeedsRetry() {
    let rig = Rig()
    rig.enable()
    rig.settings.failSettingDisplay = 10
    rig.policy.disconnect(client: rig.client)

    #expect(rig.policy.status == .restorePending)
    #expect(!rig.settings.disabled)
    #expect(rig.journal.recovery != nil)

    rig.settings.failSettingDisplay = nil
    rig.policy.refresh()
    #expect(rig.policy.status == .off)
    #expect(rig.settings.minutes == 10)
    #expect(rig.journal.recovery == nil)
}

@Test func retryDoesNotReclaimSuccessfullyRestoredSleepSetting() {
    let rig = Rig()
    rig.enable()
    rig.settings.failSettingDisplay = 10
    rig.policy.disconnect(client: rig.client)
    #expect(rig.policy.status == .restorePending)
    #expect(rig.journal.recovery?.mayOwnSleepOverride == false)

    rig.settings.disabled = true
    rig.settings.failSettingDisplay = nil
    rig.policy.refresh()
    #expect(rig.policy.status == .off)
    #expect(rig.settings.disabled)
    #expect(rig.settings.minutes == 10)
}

@Test func durationUnitsValidatePositiveWholeMinutes() {
    #expect(DurationUnit.minutes.totalMinutes(20) == 20)
    #expect(DurationUnit.hours.totalMinutes(10) == 600)
    #expect(DurationUnit.hours.totalMinutes(Int.max) == nil)
    #expect(DurationUnit.minutes.totalMinutes(0) == nil)
    #expect(DurationUnit.minutes.totalMinutes(-1) == nil)
}

@Test func pmsetParserUsesOnlyTheACDisplayTimer() throws {
    let profiles = """
    Battery Power:
     displaysleep         2
    AC Power:
     displaysleep         15
    UPS Power:
     displaysleep         4
    """
    #expect(try PmsetOutput.acDisplayMinutes(profiles) == 15)
    #expect(throws: PmsetOutput.ParseError.self) {
        try PmsetOutput.acDisplayMinutes("Battery Power:\n displaysleep 2")
    }
}

@Test func pmsetParserDistinguishesAnOmittedOverrideFromInvalidOutput() throws {
    #expect(try PmsetOutput.sleepDisabled("System-wide power settings:\n SleepDisabled 1"))
    #expect(try !PmsetOutput.sleepDisabled("Currently in use:\n displaysleep 10"))
    #expect(throws: PmsetOutput.ParseError.self) { try PmsetOutput.sleepDisabled("") }
}
