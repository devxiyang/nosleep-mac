import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement

enum MenuAction {
    case authorizeHelper
    case openBackgroundItems
    case openLockScreenSettings
    case openScreenSaverSettings
    case retry

    var title: LocalizedStringResource {
        switch self {
        case .authorizeHelper: "Continue Setup"
        case .openBackgroundItems: "Open Background Items"
        case .openLockScreenSettings: "Open Lock Screen Settings"
        case .openScreenSaverSettings: "Open Screen Saver Settings"
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
    case power(PowerModeStatus)

    var message: LocalizedStringResource {
        switch self {
        case .checking: "Applying settings…"
        case .signingRequired: "Build the app and helper with the same Apple signing team."
        case .setupHelper: "Background access is required."
        case .approveHelper: "Waiting for background approval."
        case .helperRegistrationFailed: "Could not register the power helper."
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
        case .helperRegistrationFailed, .power(.off), .power(.failed),
             .power(.unavailable), .power(.busy), .power(.settingsChanged), .power(.existingOverride): .retry
        default: nil
        }
    }
}

enum IdleLockNotice: Equatable {
    case passwordRequired
    case passwordPolicyUnavailable
    case setupScreenSaver
    case approveScreenSaver
    case screenSaverConflict
    case restorePending

    var message: LocalizedStringResource {
        switch self {
        case .passwordRequired: "Require a password immediately after the display turns off."
        case .passwordPolicyUnavailable: "Could not read the macOS lock screen policy."
        case .setupScreenSaver: "Allow NoSleep to adjust the system screen saver."
        case .approveScreenSaver: "Waiting for screen saver background approval."
        case .screenSaverConflict: "The system screen saver may lock your Mac earlier."
        case .restorePending: "Restoring the previous screen saver delay…"
        }
    }

    var action: MenuAction {
        switch self {
        case .passwordRequired, .passwordPolicyUnavailable: .openLockScreenSettings
        case .setupScreenSaver: .authorizeHelper
        case .approveScreenSaver: .openBackgroundItems
        case .screenSaverConflict, .restorePending: .openScreenSaverSettings
        }
    }
}

@MainActor
@Observable
final class MenuModel {
    private(set) var enabled: Bool
    private(set) var status: MenuStatus = .power(.off)
    private(set) var idleLockNotice: IdleLockNotice?
    private(set) var savedCount: Int
    private(set) var savedUnit: DurationUnit
    private(set) var language: MenuLanguage
    private(set) var loginItemState: LoginItemRegistration.State = .off
    private(set) var loginItemUpdateFailed = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let helper = SMAppService.daemon(plistName: ServiceIdentity.daemonPlist)
    @ObservationIgnored private let screenSaverAgent = SMAppService.agent(plistName: ServiceIdentity.screenSaverAgentPlist)
    @ObservationIgnored private let loginItem = SMAppService.mainApp
    @ObservationIgnored private let client = BackgroundConnection<PowerServiceProtocol, PowerModeStatus>(
        identifier: ServiceIdentity.helper,
        interface: NSXPCInterface(with: PowerServiceProtocol.self),
        options: .privileged,
        unavailable: .unavailable
    )
    @ObservationIgnored private let screenSaver = BackgroundConnection<ScreenSaverServiceProtocol, ScreenSaverStatus>(
        identifier: ServiceIdentity.screenSaverAgent,
        interface: NSXPCInterface(with: ScreenSaverServiceProtocol.self),
        unavailable: .unavailable
    )
    @ObservationIgnored private let log = Logger(subsystem: ServiceIdentity.app, category: "Menu")
    @ObservationIgnored private var powerMonitor: ExternalPowerMonitor?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var screenSaverAuthorization: Task<Void, Never>?
    @ObservationIgnored private var pendingRequest: ApplyRequest?
    @ObservationIgnored private var needsScreenSaverRestore = false
    @ObservationIgnored private var requestedPowerMinutes: Int?
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
        let monitor = ExternalPowerMonitor { [weak self] in
            let lostExternalPower = !ExternalPowerMonitor.isOnAC()
            Task { @MainActor in self?.recheckPower(restoringScreenSaver: lostExternalPower) }
        }
        if monitor.start() { powerMonitor = monitor }
        let wakeEvents = NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification)
        wakeTask = Task { [weak self] in
            for await _ in wakeEvents {
                guard let self else { return }
                self.recheckPower(restoringScreenSaver: true)
            }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.poll()
            }
        }
    }

    deinit { wakeTask?.cancel() }

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
        switch action {
        case .authorizeHelper, .openBackgroundItems, .retry:
            if enabled { apply(.authorize) }
        case .openLockScreenSettings:
            openSettings("com.apple.Lock-Screen-Settings.extension")
        case .openScreenSaverSettings:
            openSettings("com.apple.Wallpaper-Settings.extension?ScreenSaver")
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(url) }
    }

    private enum ApplyRequest: Int {
        case poll
        case powerChanged
        case refresh
        case authorize
    }

    private func poll() {
        if enabled || idleLockNotice == .restorePending { apply(.poll) }
    }

    private func recheckPower(restoringScreenSaver: Bool) {
        guard enabled || idleLockNotice == .restorePending else { return }
        needsScreenSaverRestore = needsScreenSaverRestore || restoringScreenSaver
        apply(.powerChanged)
    }

    private func apply(_ request: ApplyRequest = .refresh) {
        if request == .poll, applyTask != nil { return }
        revision &+= 1
        // A power change must not consume a newer duration or an explicit setup request.
        let queued = pendingRequest ?? request
        pendingRequest = enabled && queued.rawValue > request.rawValue ? queued : request
        if request == .refresh || request == .authorize { status = .checking }
        guard applyTask == nil else { return }
        applyTask = Task { [weak self] in await self?.applyPending() }
    }

    private func applyPending() async {
        while let request = pendingRequest {
            pendingRequest = nil
            let requestRevision = revision
            let mustRestore = needsScreenSaverRestore
            needsScreenSaverRestore = false
            var notice: IdleLockNotice?
            if !enabled || mustRestore {
                // Recover the prior screen saver session before starting another one or releasing system sleep.
                notice = await restoreScreenSaver(checkAgent: mustRestore)
                if mustRestore && notice != nil { needsScreenSaverRestore = true }
            }
            guard requestRevision == revision else { continue }
            let power = await reconcilePower(request, revision: requestRevision)
            guard requestRevision == revision else { continue }
            if enabled && notice == nil {
                notice = await reconcileIdleLock(power: power, request: request, revision: requestRevision)
            }
            if requestRevision == revision {
                status = power
                idleLockNotice = notice
            }
        }
        applyTask = nil
    }

    private func reconcilePower(_ request: ApplyRequest, revision requestRevision: Int) async -> MenuStatus {
        guard enabled else {
            if client.isConnected {
                let result = await client.call { $0.setMode(false, displayMinutes: 0, reply: $1) }
                client.close()
                return .power(result)
            }
            return .power(.off)
        }
        guard ConnectionSigning.teamID() != nil else { return .signingRequired }

        let readiness: BundledServiceRegistration.Readiness
        do {
            readiness = try BundledServiceRegistration.prepare(
                bundleURL: Bundle.main.bundleURL,
                service: .powerHelper,
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

        guard let minutes = savedUnit.totalMinutes(savedCount) else { return .power(.failed) }
        if (request == .poll || request == .powerChanged), client.isConnected, requestedPowerMinutes == minutes {
            let current = await client.call { $0.status(reply: $1) }
            guard requestRevision == revision else { return .checking }
            // A restarted helper has lost its in-memory request. Reapply the saved choice.
            if current != .off && current != .unavailable { return .power(current) }
        }
        requestedPowerMinutes = minutes
        return .power(await client.call { $0.setMode(true, displayMinutes: minutes, reply: $1) })
    }

    private func reconcileIdleLock(
        power: MenuStatus,
        request: ApplyRequest,
        revision requestRevision: Int
    ) async -> IdleLockNotice? {
        guard power == .power(.active) else { return await restoreScreenSaver() }
        let lockPolicy = await Self.lockPolicy()
        guard requestRevision == revision else { return nil }
        guard lockPolicy == .immediate else {
            if let restoration = await restoreScreenSaver() { return restoration }
            return lockPolicy == .other ? .passwordRequired : .passwordPolicyUnavailable
        }

        let readiness: BundledServiceRegistration.Readiness
        do {
            readiness = try BundledServiceRegistration.prepare(
                bundleURL: Bundle.main.bundleURL,
                service: .screenSaverAgent,
                mayRequestAuthorization: request == .authorize,
                status: { screenSaverAgent.status },
                register: { try screenSaverAgent.register() },
                openApprovalSettings: openLoginItemsSettings
            )
        } catch {
            let details = error as NSError
            log.error("Screen saver agent registration failed (\(details.domain, privacy: .public) \(details.code, privacy: .public)).")
            return .screenSaverConflict
        }

        switch readiness {
        case .ready: break
        case .setupRequired: return .setupScreenSaver
        case .approvalRequired: return .approveScreenSaver
        case .unavailable: return .screenSaverConflict
        }

        guard let minutes = savedUnit.totalMinutes(savedCount) else { return .screenSaverConflict }
        // The app's duration can be larger than the Apple event's integer range.
        let result = await screenSaver.call { $0.apply(minimumSeconds: minutes * 60, reply: $1) }
        guard requestRevision == revision else { return nil }
        switch result {
        case .synchronized, .inactive: return nil
        case .authorizationRequired:
            if request == .authorize { requestScreenSaverAuthorization() }
            return .setupScreenSaver
        case .restorePending: return .restorePending
        case .permissionDenied, .settingsChanged, .unavailable: return .screenSaverConflict
        }
    }

    private func restoreScreenSaver(checkAgent: Bool = false) async -> IdleLockNotice? {
        let checkRegisteredAgent = checkAgent || idleLockNotice == .restorePending
        guard screenSaver.isConnected ||
                (checkRegisteredAgent && screenSaverAgent.status == .enabled)
        else { return idleLockNotice == .restorePending ? .restorePending : nil }
        let result = await screenSaver.call { $0.restore(reply: $1) }
        if result == .inactive { screenSaver.close() }
        return result == .inactive ? nil : .restorePending
    }

    private func requestScreenSaverAuthorization() {
        guard screenSaverAuthorization == nil else { return }
        screenSaverAuthorization = Task { [weak self] in
            guard let self else { return }
            _ = await self.screenSaver.call(timeout: nil) { $0.requestAuthorization(reply: $1) }
            self.screenSaverAuthorization = nil
            self.poll()
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
