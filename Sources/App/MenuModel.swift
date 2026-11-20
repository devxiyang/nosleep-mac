import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement

enum MenuAction {
    case authorizeHelper
    case openBackgroundItems
    case openLockScreenSettings
    case retry

    var title: LocalizedStringResource {
        switch self {
        case .authorizeHelper: "Continue Setup"
        case .openBackgroundItems: "Open Background Items"
        case .openLockScreenSettings: "Open Lock Screen Settings"
        case .retry: "Retry"
        }
    }
}

enum MenuStatus: Equatable {
    case checking
    case signingRequired
    case setupHelper
    case approveHelper
    case helperRegistrationFailed
    case lockPolicyRequired
    case lockPolicyUnavailable
    case power(PowerModeStatus)

    var message: LocalizedStringResource {
        switch self {
        case .checking: "Applying settings…"
        case .signingRequired: "Build the app and helper with the same Apple signing team."
        case .setupHelper: "Background access is required."
        case .approveHelper: "Waiting for background approval."
        case .helperRegistrationFailed: "Could not register the power helper."
        case .lockPolicyRequired: "Require a password immediately after the display turns off."
        case .lockPolicyUnavailable: "Could not read the macOS lock screen policy."
        case .power(.off): "Off · works when plugged in"
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

    var action: MenuAction? {
        switch self {
        case .setupHelper: .authorizeHelper
        case .approveHelper: .openBackgroundItems
        case .lockPolicyRequired: .openLockScreenSettings
        case .helperRegistrationFailed, .lockPolicyUnavailable, .power(.off), .power(.failed),
             .power(.unavailable), .power(.busy), .power(.settingsChanged), .power(.existingOverride): .retry
        default: nil
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
    private(set) var language: MenuLanguage
    private(set) var loginItemState: LoginItemRegistration.State = .off
    private(set) var loginItemUpdateFailed = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let helper = SMAppService.daemon(plistName: ServiceIdentity.daemonPlist)
    @ObservationIgnored private let loginItem = SMAppService.mainApp
    @ObservationIgnored private let client = PowerClient()
    @ObservationIgnored private let log = Logger(subsystem: ServiceIdentity.app, category: "Menu")
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRequest: ApplyRequest?
    @ObservationIgnored private var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "keepAwakeOnAC")
        language = MenuLanguage.preference(defaults.string(forKey: "menuLanguage"))
        let unit = defaults.string(forKey: "idleUnit").flatMap(DurationUnit.init(rawValue:)) ?? .minutes
        let count = defaults.integer(forKey: "idleCount")
        if unit.totalMinutes(count) != nil {
            savedUnit = unit
            savedCount = count
        } else {
            savedUnit = .minutes
            savedCount = 10
        }

        refreshLoginItemStatus()
        // Launching from the installer image should not register that copy as a login item.
        let volume = try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        LoginItemRegistration.applyDefault(
            defaults: defaults,
            isReadOnlyVolume: volume?.volumeIsReadOnly == true,
            state: loginItemState,
            enable: { updateLoginItem(true) }
        )

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
        apply(value ? .authorize : .refresh)
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

    func setLanguage(_ value: MenuLanguage) {
        guard value != language else { return }
        language = value
        defaults.set(value.rawValue, forKey: "menuLanguage")
    }

    func refreshLoginItemStatus() {
        let state = LoginItemRegistration.State(loginItem.status)
        if state != loginItemState {
            loginItemState = state
            loginItemUpdateFailed = false
        }
    }

    func setLaunchAtLogin(_ value: Bool) {
        LoginItemRegistration.recordChoice(in: defaults)
        updateLoginItem(value)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func updateLoginItem(_ value: Bool) {
        loginItemUpdateFailed = false
        do {
            loginItemState = try LoginItemRegistration.setEnabled(
                value,
                status: { loginItem.status },
                register: { try loginItem.register() },
                unregister: { try loginItem.unregister() }
            )
        } catch {
            refreshLoginItemStatus()
            loginItemUpdateFailed = true
            let details = error as NSError
            log.error("Login item update failed (\(details.domain, privacy: .public) \(details.code, privacy: .public)).")
        }
    }

    func perform(_ action: MenuAction) {
        guard enabled else { return }
        switch action {
        case .authorizeHelper, .openBackgroundItems, .retry:
            apply(.authorize)
        case .openLockScreenSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private enum ApplyRequest {
        case refresh
        case authorize
    }

    private func apply(_ request: ApplyRequest = .refresh) {
        revision &+= 1
        // A passive refresh must not consume an explicit request queued by the switch.
        let wantsAuthorization = request == .authorize || pendingRequest == .authorize
        pendingRequest = enabled && wantsAuthorization ? .authorize : .refresh
        status = .checking
        guard applyTask == nil else { return }
        applyTask = Task { [weak self] in await self?.applyPending() }
    }

    private func applyPending() async {
        while let request = pendingRequest {
            pendingRequest = nil
            let newStatus = await reconcile(request)
            if pendingRequest == nil { status = newStatus }
        }
        applyTask = nil
    }

    private func reconcile(_ request: ApplyRequest) async -> MenuStatus {
        guard enabled else {
            if client.isConnected {
                let result = await client.setMode(false, minutes: 0)
                client.close()
                return .power(result)
            }
            return .power(.off)
        }
        guard ConnectionSigning.teamID() != nil else { return .signingRequired }

        let readiness: PowerHelperRegistration.Readiness
        do {
            readiness = try PowerHelperRegistration.prepare(
                bundleURL: Bundle.main.bundleURL,
                mayRequestAuthorization: request == .authorize,
                status: { helper.status },
                register: { try helper.register() },
                openApprovalSettings: openLoginItemsSettings
            )
        } catch {
            client.close()
            let details = error as NSError
            log.error("Helper registration failed (\(details.domain, privacy: .public) \(details.code, privacy: .public)).")
            return .helperRegistrationFailed
        }

        switch readiness {
        case .setupRequired:
            client.close()
            return .setupHelper
        case .approvalRequired:
            client.close()
            return .approveHelper
        case .unavailable:
            client.close()
            return .power(.unavailable)
        case .ready:
            break
        }

        let requestRevision = revision
        let policy = await Self.lockPolicy()
        guard requestRevision == revision else { return .checking }
        guard policy == .immediate else {
            client.close()
            return policy == .other ? .lockPolicyRequired : .lockPolicyUnavailable
        }
        guard let minutes = savedUnit.totalMinutes(savedCount) else { return .power(.failed) }
        return .power(await client.setMode(true, minutes: minutes))
    }

    private func refreshStatus() async {
        guard enabled, applyTask == nil else { return }

        switch status {
        case .setupHelper, .approveHelper, .helperRegistrationFailed:
            let readiness = PowerHelperRegistration.readiness(for: helper.status, bundleURL: Bundle.main.bundleURL)
            if readiness == .ready || (readiness == .approvalRequired && status != .approveHelper) {
                apply()
            }
            return
        case .lockPolicyRequired:
            let requestRevision = revision
            let policy = await Self.lockPolicy()
            if requestRevision == revision, policy == .immediate { apply() }
            return
        default:
            break
        }

        guard client.isConnected else { return }
        let requestRevision = revision
        let result = await client.status()
        guard requestRevision == revision else { return }
        if result == .unavailable && helper.status != .enabled {
            apply()
        } else {
            status = .power(result)
        }
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
