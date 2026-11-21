import Foundation
import ServiceManagement

enum BundledServiceRegistration {
    enum Service {
        case powerHelper
        case screenSaverAgent

        var manifestPath: String {
            switch self {
            case .powerHelper: "Contents/Library/LaunchDaemons/" + ServiceIdentity.daemonPlist
            case .screenSaverAgent: "Contents/Library/LaunchAgents/" + ServiceIdentity.screenSaverAgentPlist
            }
        }
    }

    enum Readiness: Equatable {
        case setupRequired
        case approvalRequired
        case ready
        case unavailable
    }

    static func readiness(for status: SMAppService.Status, bundleURL: URL, service: Service) -> Readiness {
        switch status {
        case .enabled:
            return .ready
        case .requiresApproval:
            return .approvalRequired
        case .notRegistered:
            return .setupRequired
        case .notFound:
            // macOS can return notFound before the first registration of a bundled service.
            let manifest = bundleURL.appending(path: service.manifestPath)
            let isBundled = (try? manifest.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            return isBundled ? .setupRequired : .unavailable
        @unknown default:
            return .unavailable
        }
    }

    static func prepare(
        bundleURL: URL,
        service: Service,
        mayRequestAuthorization: Bool,
        status: () -> SMAppService.Status,
        register: () throws -> Void,
        openApprovalSettings: () -> Void
    ) throws -> Readiness {
        var state = readiness(for: status(), bundleURL: bundleURL, service: service)
        guard mayRequestAuthorization else { return state }

        if state == .setupRequired {
            do {
                try register()
                state = readiness(for: status(), bundleURL: bundleURL, service: service)
                if state == .setupRequired {
                    // Registration can finish before Background Item Management updates its record.
                    state = .approvalRequired
                }
            } catch {
                state = readiness(for: status(), bundleURL: bundleURL, service: service)
                guard state == .ready || state == .approvalRequired else { throw error }
            }
        }

        if state == .approvalRequired { openApprovalSettings() }
        return state
    }
}
