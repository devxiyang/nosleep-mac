enum AgentControlRequest: Codable, Sendable {
    case getStatus
    case setKeepAwakeOnAC(enabled: Bool)
    case setIdleLockAfter(minutes: Int)

    @MainActor func perform(
        allowed: Bool,
        setKeepAwake: (Bool) -> Void,
        setIdleLock: (Int) -> Void,
        status: () -> AgentControlStatus
    ) -> AgentControlReply {
        guard allowed else { return .failure(.controlDisabled) }
        switch self {
        case .getStatus:
            break
        case let .setKeepAwakeOnAC(enabled):
            setKeepAwake(enabled)
        case let .setIdleLockAfter(minutes):
            guard DurationUnit.validMinutes.contains(minutes) else { return .failure(.invalidArguments) }
            setIdleLock(minutes)
        }
        return .status(status())
    }
}

enum AgentControlReply: Codable, Equatable, Sendable {
    case status(AgentControlStatus)
    case failure(AgentControlError)
}

enum AgentControlError: String, Codable, Error, Sendable {
    case appNotRunning = "app_not_running"
    case controlDisabled = "control_disabled"
    case invalidArguments = "invalid_arguments"
    case connectionFailed = "connection_failed"

    var message: String {
        switch self {
        case .appNotRunning: "Open the NoSleep menu bar app and try again."
        case .controlDisabled: "Turn on Allow Local Agent Control in NoSleep settings."
        case .invalidArguments: "The tool arguments do not match the expected input."
        case .connectionFailed: "Could not complete a request to the NoSleep menu bar app."
        }
    }
}

struct AgentControlStatus: Codable, Equatable, Sendable {
    let powerSource: PowerSource
    let keepAwakeOnAC: Bool
    let keepAwakeStatus: AgentPowerStatus
    let idleLockAfterMinutes: Int
    let displaySleepAfterMinutes: Int?
    let idleLockStatus: AgentIdleLockStatus
}

enum AgentPowerStatus: String, Codable, Sendable {
    case off
    case active
    case pausedOnBattery = "paused_on_battery"
    case applying
    case needsUserAction = "needs_user_action"
    case conflict
    case restoring
    case unavailable
}

enum AgentIdleLockStatus: String, Codable, Sendable {
    case inactive
    case applying
    case synchronized
    case needsUserAction = "needs_user_action"
    case screenSaverConflict = "screen_saver_conflict"
    case restoring
}
