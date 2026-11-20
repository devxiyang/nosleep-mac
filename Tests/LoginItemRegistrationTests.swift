import Foundation
import ServiceManagement
import Testing

@Test func loginItemDefaultsOnOnlyOnce() throws {
    let suite = "NoSleepTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var requests = 0

    LoginItemRegistration.applyDefault(defaults: defaults, isReadOnlyVolume: true, state: .off) { requests += 1 }
    #expect(requests == 0)

    LoginItemRegistration.applyDefault(defaults: defaults, isReadOnlyVolume: false, state: .off) { requests += 1 }
    #expect(requests == 1)

    LoginItemRegistration.applyDefault(defaults: defaults, isReadOnlyVolume: false, state: .off) { requests += 1 }
    #expect(requests == 1)
}

@Test func existingLoginItemApprovalAndExplicitChoicesAreRespected() throws {
    let suite = "NoSleepTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var requests = 0

    LoginItemRegistration.applyDefault(defaults: defaults, isReadOnlyVolume: false, state: .approvalRequired) {
        requests += 1
    }
    LoginItemRegistration.applyDefault(defaults: defaults, isReadOnlyVolume: false, state: .off) { requests += 1 }
    #expect(requests == 0)

    defaults.removePersistentDomain(forName: suite)
    LoginItemRegistration.recordChoice(in: defaults)
    LoginItemRegistration.applyDefault(defaults: defaults, isReadOnlyVolume: false, state: .off) { requests += 1 }
    #expect(requests == 0)
}

@Test(arguments: [SMAppService.Status.notRegistered, .notFound])
func loginItemCanRegisterAndCancelWhileApprovalIsPending(initialStatus: SMAppService.Status) throws {
    var status = initialStatus
    var operations: [String] = []

    func setEnabled(_ enabled: Bool) throws -> LoginItemRegistration.State {
        try LoginItemRegistration.setEnabled(
            enabled,
            status: { status },
            register: {
                operations.append("register")
                status = .requiresApproval
            },
            unregister: {
                operations.append("unregister")
                status = .notRegistered
            }
        )
    }

    let pending = try setEnabled(true)
    #expect(pending == .approvalRequired)
    #expect(pending.isRegistered)
    #expect(try setEnabled(true) == .approvalRequired)
    #expect(try setEnabled(false) == .off)
    #expect(try setEnabled(false) == .off)
    #expect(operations == ["register", "unregister"])
}

@Test func loginItemKeepsActualSystemStateIfItChangesDuringRegistration() throws {
    enum RegistrationError: Error { case serviceChanged }

    var status = SMAppService.Status.notRegistered
    let state = try LoginItemRegistration.setEnabled(
        true,
        status: { status },
        register: {
            status = .enabled
            throw RegistrationError.serviceChanged
        },
        unregister: { Issue.record("Enabling must not unregister") }
    )
    #expect(state == .enabled)
}

@Test func loginItemReportsUpdateFailureWhenTheSettingDidNotChange() {
    enum RegistrationError: Error { case denied }

    #expect(throws: RegistrationError.denied) {
        try LoginItemRegistration.setEnabled(
            false,
            status: { .enabled },
            register: { Issue.record("Disabling must not register") },
            unregister: { throw RegistrationError.denied }
        )
    }
}
