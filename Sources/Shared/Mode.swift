import Foundation

enum DurationUnit: String, CaseIterable, Identifiable, Sendable {
    case minutes
    case hours

    var id: Self { self }
    var multiplier: Int { self == .hours ? 60 : 1 }

    func totalMinutes(_ count: Int) -> Int? {
        let (minutes, overflow) = count.multipliedReportingOverflow(by: multiplier)
        guard !overflow, Self.validMinutes.contains(minutes) else { return nil }
        return minutes
    }

    static let validMinutes = 1...Int(Int32.max)
}

enum PowerModeStatus: String, Sendable {
    case off
    case active
    case battery
    case existingOverride
    case settingsChanged
    case failed
    case restorePending
    case unavailable
    case busy
    case inactiveUser
}

enum ScreenSaverStatus: String, Sendable {
    case inactive
    case synchronized
    case authorizationRequired
    case permissionDenied
    case settingsChanged
    case unavailable
    case restorePending
}

enum ServiceIdentity {
    static let app = "com.octoii.nosleep"
    static let helper = app + ".PowerHelper"
    static let daemonPlist = helper + ".plist"
    static let screenSaverAgent = app + ".ScreenSaverAgent"
    static let screenSaverAgentPlist = screenSaverAgent + ".plist"
}
