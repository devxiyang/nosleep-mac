import Foundation

// A client keeps its preference on battery, but its system override is released.
final class PowerPolicy {
    private let override: PowerOverride
    private let onExternalPower: () -> Bool
    private(set) var owner: UUID?
    private var desiredMinutes: Int?
    private(set) var status: PowerModeStatus = .off

    init(override: PowerOverride, onExternalPower: @escaping () -> Bool) {
        self.override = override
        self.onExternalPower = onExternalPower
    }

    func recover() {
        owner = nil
        desiredMinutes = nil
        resolveByRestoring(to: .off)
    }

    func setMode(client: UUID, enabled: Bool, displayMinutes: Int) -> PowerModeStatus {
        guard owner == nil || owner == client else { return .busy }

        if enabled {
            guard DurationUnit.validMinutes.contains(displayMinutes) else { return .failed }
            owner = client
            desiredMinutes = displayMinutes
            refresh()
        } else {
            owner = nil
            desiredMinutes = nil
            resolveByRestoring(to: .off)
        }
        return status
    }

    func disconnect(client: UUID) {
        guard owner == client else { return }
        _ = setMode(client: client, enabled: false, displayMinutes: 0)
    }

    func status(for client: UUID) -> PowerModeStatus {
        guard owner == nil || owner == client else { return .busy }
        // Re-read on status refresh so an external change is visible promptly.
        if status == .active || status == .battery || status == .restorePending { refresh() }
        return status
    }

    func refresh() {
        guard let desiredMinutes else {
            if status == .restorePending { resolveByRestoring(to: .off) }
            return
        }
        guard onExternalPower() else {
            resolveByRestoring(to: .battery)
            return
        }

        do {
            try override.apply(displayMinutes: desiredMinutes, onExternalPower: onExternalPower)
            status = .active
        } catch PowerOverrideError.externalPowerLost {
            status = .battery
        } catch PowerOverrideError.existingOverride {
            fail(with: .existingOverride)
        } catch PowerOverrideError.settingsChanged {
            fail(with: .settingsChanged)
        } catch PowerOverrideError.restorePending {
            fail(with: .restorePending)
        } catch {
            fail(with: .failed)
        }
    }

    private func fail(with status: PowerModeStatus) {
        desiredMinutes = nil
        self.status = status
    }

    private func resolveByRestoring(to status: PowerModeStatus) {
        do {
            try override.restore()
            self.status = status
        } catch {
            self.status = .restorePending
        }
    }
}
