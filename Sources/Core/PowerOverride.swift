import Foundation

protocol SystemPowerSettings {
    func sleepDisabled() throws -> Bool
    func acDisplayMinutes() throws -> Int
    func setSleepDisabled(_ disabled: Bool) throws
    func setACDisplayMinutes(_ minutes: Int) throws
}

struct PowerRecovery: Codable, Equatable {
    let originalDisplayMinutes: Int
    var displayValues: [Int]
    var mayOwnSleepOverride: Bool
}

protocol PowerRecoveryJournal {
    func load() throws -> PowerRecovery?
    func save(_ recovery: PowerRecovery) throws
    func clear() throws
}

enum PowerOverrideError: Error, Equatable {
    case externalPowerLost
    case existingOverride
    case settingsChanged
    case invalidDuration
    case writeNotApplied
    case restorePending
}

// Call on one serial queue. There is one system-wide override and one recovery journal.
final class PowerOverride {
    private let settings: any SystemPowerSettings
    private let journal: any PowerRecoveryJournal
    private var active = false

    init(settings: any SystemPowerSettings, journal: any PowerRecoveryJournal) {
        self.settings = settings
        self.journal = journal
    }

    func apply(displayMinutes: Int, onExternalPower: () -> Bool) throws {
        guard DurationUnit.validMinutes.contains(displayMinutes) else {
            throw PowerOverrideError.invalidDuration
        }

        do {
            try requireExternalPower(onExternalPower)
            if active {
                try updateDisplay(displayMinutes)
            } else {
                try restore()
                try begin(displayMinutes, onExternalPower: onExternalPower)
            }
            try requireExternalPower(onExternalPower)
        } catch {
            do {
                try restore()
            } catch {
                throw PowerOverrideError.restorePending
            }
            throw error
        }
    }

    func restore() throws {
        active = false
        guard var recovery = try journal.load() else { return }
        let initialRecovery = recovery
        var restorationError: (any Error)?

        // Finish display restoration before removing the override. A closed Mac can sleep
        // as soon as the sleep override is removed.
        if !recovery.displayValues.isEmpty {
            do {
                let current = try settings.acDisplayMinutes()
                if current != recovery.originalDisplayMinutes,
                   recovery.displayValues.contains(current) {
                    try settings.setACDisplayMinutes(recovery.originalDisplayMinutes)
                    guard try settings.acDisplayMinutes() == recovery.originalDisplayMinutes else {
                        throw PowerOverrideError.writeNotApplied
                    }
                }
                recovery.displayValues.removeAll()
            } catch {
                restorationError = error
            }
        }

        // Try to release the sleep override even if repairing the display profile failed.
        if recovery.mayOwnSleepOverride {
            do {
                if try settings.sleepDisabled() {
                    try settings.setSleepDisabled(false)
                    guard try !settings.sleepDisabled() else {
                        throw PowerOverrideError.writeNotApplied
                    }
                }
                recovery.mayOwnSleepOverride = false
            } catch {
                restorationError = error
            }
        }

        if recovery != initialRecovery {
            try journal.save(recovery)
        }
        if let restorationError { throw restorationError }
        try journal.clear()
    }

    private func begin(_ minutes: Int, onExternalPower: () -> Bool) throws {
        guard try !settings.sleepDisabled() else {
            throw PowerOverrideError.existingOverride
        }
        let originalMinutes = try settings.acDisplayMinutes()
        var recovery = PowerRecovery(
            originalDisplayMinutes: originalMinutes,
            displayValues: originalMinutes == minutes ? [] : [minutes],
            mayOwnSleepOverride: false
        )
        try journal.save(recovery)

        if originalMinutes != minutes {
            try settings.setACDisplayMinutes(minutes)
        }
        guard try settings.acDisplayMinutes() == minutes else {
            throw PowerOverrideError.writeNotApplied
        }
        try requireExternalPower(onExternalPower)
        guard try !settings.sleepDisabled() else {
            throw PowerOverrideError.existingOverride
        }

        recovery.mayOwnSleepOverride = true
        try journal.save(recovery)
        try settings.setSleepDisabled(true)
        guard try settings.sleepDisabled() else {
            throw PowerOverrideError.writeNotApplied
        }
        active = true
    }

    private func updateDisplay(_ minutes: Int) throws {
        guard var recovery = try journal.load(), try settings.sleepDisabled() else {
            throw PowerOverrideError.settingsChanged
        }
        let current = try settings.acDisplayMinutes()
        let expected = recovery.displayValues.last ?? recovery.originalDisplayMinutes
        guard current == expected else {
            throw PowerOverrideError.settingsChanged
        }
        guard current != minutes else { return }

        // Both values are ours until we know whether the new setting reached powerd.
        recovery.displayValues = [current, minutes]
        try journal.save(recovery)
        try settings.setACDisplayMinutes(minutes)
        guard try settings.acDisplayMinutes() == minutes else {
            throw PowerOverrideError.writeNotApplied
        }
        recovery.displayValues = minutes == recovery.originalDisplayMinutes ? [] : [minutes]
        try journal.save(recovery)
    }

    private func requireExternalPower(_ onExternalPower: () -> Bool) throws {
        guard onExternalPower() else { throw PowerOverrideError.externalPowerLost }
    }
}
