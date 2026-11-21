import Foundation

protocol ScreenSaverSettings {
    func idleSeconds() throws -> Int
    func setIdleSeconds(_ seconds: Int) throws
}

struct ScreenSaverRecovery: Codable, Equatable {
    let originalSeconds: Int
    let writtenValues: [Int]
}

protocol ScreenSaverRecoveryJournal {
    func load() throws -> ScreenSaverRecovery?
    func save(_ recovery: ScreenSaverRecovery) throws
    func clear() throws
}

enum ScreenSaverAccessError: Error {
    case authorizationRequired
    case permissionDenied
    case unavailable

    var status: ScreenSaverStatus {
        switch self {
        case .authorizationRequired: .authorizationRequired
        case .permissionDenied: .permissionDenied
        case .unavailable: .unavailable
        }
    }
}

// All operations run on the user agent's serial queue.
final class ScreenSaverPolicy {
    private let settings: any ScreenSaverSettings
    private let journal: any ScreenSaverRecoveryJournal
    private let isEligible: () -> Bool
    private var owner: UUID?
    private var observedSeconds: Int?
    private var settingsChanged = false
    private(set) var restorePending = false
    var needsMonitoring: Bool { owner != nil || restorePending }

    init(
        settings: any ScreenSaverSettings,
        journal: any ScreenSaverRecoveryJournal,
        isEligible: @escaping () -> Bool
    ) {
        self.settings = settings
        self.journal = journal
        self.isEligible = isEligible
    }

    func apply(client: UUID, minimumSeconds: Int) -> ScreenSaverStatus {
        guard owner == nil || owner == client else { return .unavailable }
        guard isEligible() else { return release() }
        guard (1...Int(Int32.max)).contains(minimumSeconds) else {
            return release(returning: .unavailable)
        }

        if owner == nil {
            // Close an interrupted session before taking a new snapshot.
            guard release() != .restorePending else { return .restorePending }
            owner = client
        }

        do {
            let recovery = try journal.load()
            let current = try settings.idleSeconds()
            guard (0...Int(Int32.max)).contains(current) else { throw ScreenSaverAccessError.unavailable }
            if let observedSeconds, current != observedSeconds {
                if recovery != nil { try journal.clear() }
                settingsChanged = true
            }
            observedSeconds = current
            if settingsChanged {
                return externalSettingStatus(current, minimumSeconds: minimumSeconds)
            }

            let original = recovery?.originalSeconds ?? current
            if original == 0 || original >= minimumSeconds {
                if let recovery {
                    try restore(recovery, current: current)
                    observedSeconds = original
                }
            } else if current != minimumSeconds {
                guard isEligible() else { return release() }
                let values = recovery == nil ? [minimumSeconds] : [current, minimumSeconds]
                try journal.save(ScreenSaverRecovery(originalSeconds: original, writtenValues: values))
                guard isEligible() else { return release() }
                try settings.setIdleSeconds(minimumSeconds)
                let confirmed = try settings.idleSeconds()
                if confirmed != minimumSeconds {
                    guard confirmed != current else { throw ScreenSaverAccessError.unavailable }
                    // A different value arrived during the write. Relinquish ownership.
                    try journal.clear()
                    observedSeconds = confirmed
                    settingsChanged = true
                    return externalSettingStatus(confirmed, minimumSeconds: minimumSeconds)
                }
                observedSeconds = minimumSeconds
                if recovery != nil {
                    try journal.save(ScreenSaverRecovery(originalSeconds: original, writtenValues: [minimumSeconds]))
                }
            }

            return isEligible() ? .synchronized : release()
        } catch {
            return release(returning: (error as? ScreenSaverAccessError)?.status ?? .unavailable)
        }
    }

    func disconnect(client: UUID) {
        if owner == client { _ = release() }
    }

    func refresh() {
        if restorePending || (owner != nil && !isEligible()) { _ = release() }
    }

    @discardableResult
    func release(client: UUID? = nil, returning result: ScreenSaverStatus = .inactive) -> ScreenSaverStatus {
        if let client, let owner, owner != client { return .unavailable }
        owner = nil
        observedSeconds = nil
        settingsChanged = false
        do {
            if let recovery = try journal.load() {
                try restore(recovery, current: settings.idleSeconds())
            }
            restorePending = false
            return result
        } catch {
            restorePending = true
            return .restorePending
        }
    }

    private func restore(_ recovery: ScreenSaverRecovery, current: Int) throws {
        if current != recovery.originalSeconds, recovery.writtenValues.contains(current) {
            try settings.setIdleSeconds(recovery.originalSeconds)
            guard try settings.idleSeconds() == recovery.originalSeconds else { throw ScreenSaverAccessError.unavailable }
        }
        try journal.clear()
    }

    private func externalSettingStatus(_ seconds: Int, minimumSeconds: Int) -> ScreenSaverStatus {
        guard isEligible() else { return release() }
        return seconds == 0 || seconds >= minimumSeconds ? .synchronized : .settingsChanged
    }
}
