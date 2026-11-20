import Foundation
import ServiceManagement

enum LoginItemRegistration {
    enum State: Equatable {
        case off
        case enabled
        case approvalRequired
        case unavailable

        init(_ status: SMAppService.Status) {
            switch status {
            case .notRegistered, .notFound: self = .off
            case .enabled: self = .enabled
            case .requiresApproval: self = .approvalRequired
            @unknown default: self = .unavailable
            }
        }

        var isRegistered: Bool { self == .enabled || self == .approvalRequired }
    }

    private static let initializedKey = "didInitializeLaunchAtLogin"

    static func applyDefault(
        defaults: UserDefaults,
        isReadOnlyVolume: Bool,
        state: State,
        enable: () -> Void
    ) {
        guard !isReadOnlyVolume, !defaults.bool(forKey: initializedKey) else { return }
        recordChoice(in: defaults)
        if state == .off { enable() }
    }

    static func recordChoice(in defaults: UserDefaults) {
        defaults.set(true, forKey: initializedKey)
    }

    static func setEnabled(
        _ enabled: Bool,
        status: () -> SMAppService.Status,
        register: () throws -> Void,
        unregister: () throws -> Void
    ) throws -> State {
        let current = State(status())
        guard current != .unavailable, current.isRegistered != enabled else { return current }

        do {
            if enabled {
                try register()
            } else {
                try unregister()
            }
        } catch {
            let updated = State(status())
            guard updated != .unavailable, updated.isRegistered == enabled else { throw error }
            return updated
        }
        return State(status())
    }
}
