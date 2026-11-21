import Foundation
import ServiceManagement
import Testing

@Test func screenSaverAgentUsesItsOwnBundledManifestForFirstRegistration() throws {
    let bundle = try TemporaryBundle()
    defer { bundle.remove() }
    try bundle.addManifest()
    #expect(BundledServiceRegistration.readiness(for: .notFound, bundleURL: bundle.url, service: .screenSaverAgent) == .unavailable)

    let manifest = bundle.url.appending(path: BundledServiceRegistration.Service.screenSaverAgent.manifestPath)
    try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: manifest)
    #expect(BundledServiceRegistration.readiness(for: .notFound, bundleURL: bundle.url, service: .screenSaverAgent) == .setupRequired)
}

@Test func firstRunNotFoundOffersSetupOnlyWhenTheDaemonIsBundled() throws {
    let bundle = try TemporaryBundle()
    defer { bundle.remove() }

    #expect(BundledServiceRegistration.readiness(for: .notRegistered, bundleURL: bundle.url, service: .powerHelper) == .setupRequired)
    #expect(BundledServiceRegistration.readiness(for: .notFound, bundleURL: bundle.url, service: .powerHelper) == .unavailable)

    try bundle.addManifest()

    #expect(BundledServiceRegistration.readiness(for: .notFound, bundleURL: bundle.url, service: .powerHelper) == .setupRequired)
    #expect(BundledServiceRegistration.readiness(for: .requiresApproval, bundleURL: bundle.url, service: .powerHelper) == .approvalRequired)
    #expect(BundledServiceRegistration.readiness(for: .enabled, bundleURL: bundle.url, service: .powerHelper) == .ready)
}

@Test func firstEnableRegistersThenOpensApprovalSettings() throws {
    let bundle = try TemporaryBundle()
    defer { bundle.remove() }
    try bundle.addManifest()

    var status = SMAppService.Status.notFound
    var actions: [String] = []

    let first = try BundledServiceRegistration.prepare(
        bundleURL: bundle.url,
        service: .powerHelper,
        mayRequestAuthorization: true,
        status: { status },
        register: {
            actions.append("register")
            status = .requiresApproval
        },
        openApprovalSettings: { actions.append("open") }
    )
    #expect(first == .approvalRequired)
    #expect(actions == ["register", "open"])

    status = .enabled
    let approved = try BundledServiceRegistration.prepare(
        bundleURL: bundle.url,
        service: .powerHelper,
        mayRequestAuthorization: false,
        status: { status },
        register: { actions.append("register") },
        openApprovalSettings: { actions.append("open") }
    )
    #expect(approved == .ready)
    #expect(actions == ["register", "open"])
}

@Test func passiveRefreshNeverRequestsPermission() throws {
    let bundle = try TemporaryBundle()
    defer { bundle.remove() }
    try bundle.addManifest()
    var actions = 0

    let waiting = try BundledServiceRegistration.prepare(
        bundleURL: bundle.url,
        service: .powerHelper,
        mayRequestAuthorization: false,
        status: { .notFound },
        register: { actions += 1 },
        openApprovalSettings: { actions += 1 }
    )
    let pending = try BundledServiceRegistration.prepare(
        bundleURL: bundle.url,
        service: .powerHelper,
        mayRequestAuthorization: false,
        status: { .requiresApproval },
        register: { actions += 1 },
        openApprovalSettings: { actions += 1 }
    )
    #expect(waiting == .setupRequired)
    #expect(pending == .approvalRequired)
    #expect(actions == 0)
}

@Test func explicitEnableReopensApprovalWithoutRegisteringAgain() throws {
    let bundle = try TemporaryBundle()
    defer { bundle.remove() }
    var actions: [String] = []
    let pending = try BundledServiceRegistration.prepare(
        bundleURL: bundle.url,
        service: .powerHelper,
        mayRequestAuthorization: true,
        status: { .requiresApproval },
        register: { actions.append("register") },
        openApprovalSettings: { actions.append("open") }
    )
    #expect(pending == .approvalRequired)
    #expect(actions == ["open"])
}

@Test func delayedRegistrationRecordStillOpensApprovalOnce() throws {
    let bundle = try TemporaryBundle()
    defer { bundle.remove() }
    try bundle.addManifest()
    var actions: [String] = []
    let pending = try BundledServiceRegistration.prepare(
        bundleURL: bundle.url,
        service: .powerHelper,
        mayRequestAuthorization: true,
        status: { .notFound },
        register: { actions.append("register") },
        openApprovalSettings: { actions.append("open") }
    )
    #expect(pending == .approvalRequired)
    #expect(actions == ["register", "open"])
}

@Test func failedRegistrationLeavesThePermissionPageClosed() throws {
    enum RegistrationError: Error { case denied }

    let bundle = try TemporaryBundle()
    defer { bundle.remove() }
    var opened = false

    #expect(throws: RegistrationError.denied) {
        try BundledServiceRegistration.prepare(
            bundleURL: bundle.url,
        service: .powerHelper,
            mayRequestAuthorization: true,
            status: { .notRegistered },
            register: { throw RegistrationError.denied },
            openApprovalSettings: { opened = true }
        )
    }
    #expect(!opened)
}

private struct TemporaryBundle {
    let url: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NoSleepTests-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        url = root
    }

    func addManifest() throws {
        let folder = url.appending(path: "Contents/Library/LaunchDaemons")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let declaration = ["Label": ServiceIdentity.helper, "BundleProgram": "Contents/MacOS/NoSleepPowerHelper"]
        try PropertyListSerialization.data(fromPropertyList: declaration, format: .xml, options: 0)
            .write(to: folder.appending(path: ServiceIdentity.daemonPlist))
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
