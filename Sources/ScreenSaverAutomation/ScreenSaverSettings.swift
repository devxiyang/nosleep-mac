protocol ScreenSaverSettings {
    func idleSeconds() throws -> Int
    func setIdleSeconds(_ seconds: Int) throws
}

enum ScreenSaverAuthorizationResult: Equatable, Sendable {
    case granted
    case denied
    case failed
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
