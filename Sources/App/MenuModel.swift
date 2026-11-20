import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement

enum MenuStatus: Equatable {
    case checking
    case signingRequired
    case installHelper
    case approveHelper
    case lockPolicyRequired
    case lockPolicyUnavailable
    case power(PowerModeStatus)

    var message: LocalizedStringResource {
        switch self {
        case .checking: "Applying settings…"
        case .signingRequired: "Build the app and helper with the same Apple signing team."
        case .installHelper: "Set up the power helper to use lid-closed mode."
        case .approveHelper: "Allow the power helper in System Settings."
        case .lockPolicyRequired: "Set macOS to require a password immediately after the display turns off."
        case .lockPolicyUnavailable: "Could not read the macOS lock screen policy."
        case .power(.off): "Using macOS sleep settings."
        case .power(.active): "Active on external power."
        case .power(.battery): "Paused on battery."
        case .power(.existingOverride): "macOS already has a system sleep override."
        case .power(.settingsChanged): "Power settings changed outside NoSleep."
        case .power(.failed): "Could not apply the power settings."
        case .power(.restorePending): "The helper is retrying power settings restoration."
        case .power(.unavailable): "The power helper is unavailable."
        case .power(.busy): "Another NoSleep session controls the helper."
        case .power(.inactiveUser): "Open NoSleep from the currently signed-in desktop."
        }
    }
}

@MainActor
@Observable
final class MenuModel {
    private(set) var enabled: Bool
    private(set) var status: MenuStatus = .power(.off)
    private(set) var savedCount: Int
    private(set) var savedUnit: DurationUnit

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let helper = SMAppService.daemon(plistName: ServiceIdentity.daemonPlist)
    @ObservationIgnored private let client = PowerClient()
    @ObservationIgnored private let log = Logger(subsystem: ServiceIdentity.app, category: "Menu")
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var needsApply = false
    @ObservationIgnored private var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "keepAwakeOnAC")
        let unit = defaults.string(forKey: "idleUnit").flatMap(DurationUnit.init(rawValue:)) ?? .minutes
        let count = defaults.integer(forKey: "idleCount")
        if unit.totalMinutes(count) != nil {
            savedUnit = unit
            savedCount = count
        } else {
            savedUnit = .minutes
            savedCount = 10
        }

        if enabled { apply() }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                await self.refreshStatus()
            }
        }
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        defaults.set(value, forKey: "keepAwakeOnAC")
        apply()
    }

    func saveDuration(_ count: Int, unit: DurationUnit) {
        guard unit.totalMinutes(count) != nil,
              count != savedCount || unit != savedUnit else { return }
        savedCount = count
        savedUnit = unit
        defaults.set(count, forKey: "idleCount")
        defaults.set(unit.rawValue, forKey: "idleUnit")
        if enabled { apply() }
    }

    func installHelper() {
        guard enabled, ConnectionSigning.teamID() != nil else { return }
        do {
            try helper.register()
            if helper.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            apply()
        } catch {
            log.error("Helper registration failed: \(error.localizedDescription, privacy: .public)")
            status = .power(.unavailable)
        }
    }

    func openHelperSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openLockSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func apply() {
        revision &+= 1
        needsApply = true
        status = .checking
        guard applyTask == nil else { return }
        applyTask = Task { [weak self] in await self?.applyPending() }
    }

    private func applyPending() async {
        while needsApply {
            needsApply = false
            let newStatus = await reconcile()
            if !needsApply { status = newStatus }
        }
        applyTask = nil
    }

    private func reconcile() async -> MenuStatus {
        guard enabled else {
            if client.isConnected {
                let result = await client.setMode(false, minutes: 0)
                client.close()
                return .power(result)
            }
            return .power(.off)
        }
        guard ConnectionSigning.teamID() != nil else { return .signingRequired }
        let requestRevision = revision
        let policy = await Self.lockPolicy()
        guard requestRevision == revision else { return .checking }
        guard policy == .immediate else {
            client.close()
            return policy == .other ? .lockPolicyRequired : .lockPolicyUnavailable
        }

        switch helper.status {
        case .notRegistered: return .installHelper
        case .requiresApproval:
            client.close()
            return .approveHelper
        case .enabled:
            guard let minutes = savedUnit.totalMinutes(savedCount) else { return .power(.failed) }
            return .power(await client.setMode(true, minutes: minutes))
        default:
            client.close()
            return .power(.unavailable)
        }
    }

    private func refreshStatus() async {
        guard enabled, applyTask == nil else { return }
        if status == .approveHelper || status == .installHelper {
            if helper.status == .enabled { apply() }
            return
        }
        guard client.isConnected else { return }
        let requestRevision = revision
        let result = await client.status()
        if requestRevision == revision { status = .power(result) }
    }

    private enum LockPolicy: Sendable {
        case immediate
        case other
        case unavailable
    }

    private static func lockPolicy() async -> LockPolicy {
        await Task.detached(priority: .utility) {
            guard let output = try? Command.run("/usr/sbin/sysadminctl", ["-screenLock", "status"]) else {
                return .unavailable
            }
            if output.contains("screenLock delay is immediate") { return .immediate }
            if output.contains("screenLock delay is") || output.contains("screenLock is off") { return .other }
            return .unavailable
        }.value
    }
}
