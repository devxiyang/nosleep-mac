import Foundation
import ServiceManagement

enum PowerHelperRegistration {
    enum Readiness: Equatable {
        case setupRequired
        case approvalRequired
        case ready
        case unavailable
    }

    static func readiness(for status: SMAppService.Status, bundleURL: URL) -> Readiness {
        switch status {
        case .enabled:
            return .ready
        case .requiresApproval:
            return .approvalRequired
        case .notRegistered:
            return .setupRequired
        case .notFound:
            // macOS can return notFound before its first registration of a bundled daemon.
            let manifest = bundleURL
                .appending(path: "Contents/Library/LaunchDaemons")
                .appending(path: ServiceIdentity.daemonPlist)
            let isBundled = (try? manifest.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            return isBundled ? .setupRequired : .unavailable
        @unknown default:
            return .unavailable
        }
    }

    static func prepare(
        bundleURL: URL,
        mayRequestAuthorization: Bool,
        status: () -> SMAppService.Status,
        register: () throws -> Void,
        openApprovalSettings: () -> Void
    ) throws -> Readiness {
        var state = readiness(for: status(), bundleURL: bundleURL)
        guard mayRequestAuthorization else { return state }

        if state == .setupRequired {
            do {
                try register()
                state = readiness(for: status(), bundleURL: bundleURL)
                if state == .setupRequired {
                    // Registration can finish before Background Item Management updates its record.
                    state = .approvalRequired
                }
            } catch {
                state = readiness(for: status(), bundleURL: bundleURL)
                guard state == .ready || state == .approvalRequired else { throw error }
            }
        }

        if state == .approvalRequired { openApprovalSettings() }
        return state
    }
}
