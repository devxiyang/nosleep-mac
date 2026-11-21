import Foundation

enum MenuAction: Equatable {
    case authorizeHelper
    case authorizeScreenSaver
    case retryScreenSaverAuthorization
    case openBackgroundItems
    case openLockScreenSettings
    case openScreenSaverSettings
    case openAutomationSettings
    case retry

    var title: LocalizedStringResource {
        switch self {
        case .authorizeHelper, .authorizeScreenSaver: "Continue Setup"
        case .retryScreenSaverAuthorization: "Retry Authorization"
        case .openBackgroundItems: "Open Background Items"
        case .openLockScreenSettings: "Open Lock Screen Settings"
        case .openScreenSaverSettings: "Open Screen Saver Settings"
        case .openAutomationSettings: "Open Automation Settings"
        case .retry: "Retry"
        }
    }
}

enum ScreenSaverAuthorizationState: Equatable {
    case notRequested
    case requesting
    case finished(ScreenSaverAuthorizationResult)
}

enum IdleLockNotice: Equatable {
    case passwordRequired
    case passwordPolicyUnavailable
    case setupScreenSaver
    case approveScreenSaver
    case authorizeScreenSaver
    case awaitingAutomation
    case automationDenied
    case automationNotApplied
    case automationRequestFailed
    case screenSaverConflict
    case restorePending

    static func forScreenSaver(
        _ status: ScreenSaverStatus,
        authorization: ScreenSaverAuthorizationState
    ) -> Self? {
        switch status {
        case .synchronized, .inactive:
            return nil
        case .restorePending:
            return .restorePending
        case .settingsChanged:
            return .screenSaverConflict
        case .permissionDenied:
            return authorization == .requesting ? .awaitingAutomation : .automationDenied
        case .unavailable:
            switch authorization {
            case .requesting: return .awaitingAutomation
            case .finished(.denied): return .automationDenied
            case .finished(.failed): return .automationRequestFailed
            case .notRequested, .finished(.granted): return .screenSaverConflict
            }
        case .authorizationRequired:
            switch authorization {
            case .notRequested: return .authorizeScreenSaver
            case .requesting: return .awaitingAutomation
            case .finished(.granted): return .automationNotApplied
            case .finished(.denied): return .automationDenied
            case .finished(.failed): return .automationRequestFailed
            }
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .passwordRequired: "Require a password immediately after the display turns off."
        case .passwordPolicyUnavailable: "Could not read the macOS lock screen policy."
        case .setupScreenSaver, .authorizeScreenSaver: "Allow NoSleep to adjust the system screen saver."
        case .approveScreenSaver: "Waiting for screen saver background approval."
        case .awaitingAutomation: "Waiting for macOS automation approval…"
        case .automationDenied: "macOS denied access to System Events."
        case .automationNotApplied: "Check System Events access in Automation settings."
        case .automationRequestFailed: "Could not request System Events access."
        case .screenSaverConflict: "The system screen saver may lock your Mac earlier."
        case .restorePending: "Restoring the previous screen saver delay…"
        }
    }

    var action: MenuAction? {
        switch self {
        case .passwordRequired, .passwordPolicyUnavailable: .openLockScreenSettings
        case .setupScreenSaver: .authorizeHelper
        case .approveScreenSaver: .openBackgroundItems
        case .authorizeScreenSaver: .authorizeScreenSaver
        case .awaitingAutomation: nil
        case .automationDenied, .automationNotApplied: .openAutomationSettings
        case .automationRequestFailed: .retryScreenSaverAuthorization
        case .screenSaverConflict, .restorePending: .openScreenSaverSettings
        }
    }
}
