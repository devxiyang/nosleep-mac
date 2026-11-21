import Foundation
import Testing

@MainActor
@Test func localAgentControlUsesOneSettingsStateAndHonorsTheToggle() async throws {
    let directory = URL(fileURLWithPath: "/private/tmp")
        .appending(path: "nosleep-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let address = AgentControlAddress(directory: directory)
    let settings = TestAgentSettings()
    let server = try AgentControlServer(address: address) { settings.perform($0) }
    defer { withExtendedLifetime(server) {} }

    func call(_ request: AgentControlRequest) async throws -> AgentControlReply {
        try await Task.detached { try AgentControlSocket.call(request, at: address) }.value
    }

    #expect(try await call(.getStatus) == .failure(.controlDisabled))
    #expect(try await call(.setKeepAwakeOnAC(enabled: true)) == .failure(.controlDisabled))
    #expect(try await call(.setIdleLockAfter(minutes: 240)) == .failure(.controlDisabled))
    #expect(!settings.keepAwake && settings.minutes == 10)

    settings.allowed = true
    #expect(try await call(.setKeepAwakeOnAC(enabled: true)) == .status(settings.status))
    #expect(try await call(.setIdleLockAfter(minutes: 240)) == .status(settings.status))
    #expect(settings.keepAwake && settings.minutes == 240)
    #expect(settings.status.keepAwakeStatus == .pausedOnBattery)
    #expect(settings.status.displaySleepAfterMinutes == nil)
    #expect(try await call(.getStatus) == .status(settings.status))

    #expect(try await call(.setIdleLockAfter(minutes: 0)) == .failure(.invalidArguments))
    #expect(try await call(.setIdleLockAfter(minutes: Int(Int32.max) + 1)) == .failure(.invalidArguments))
    settings.allowed = false
    #expect(try await call(.setKeepAwakeOnAC(enabled: false)) == .failure(.controlDisabled))
    #expect(settings.keepAwake && settings.minutes == 240)
}

@MainActor
@Test func secondAgentControlListenerLeavesTheRunningListenerInPlace() async throws {
    let directory = URL(fileURLWithPath: "/private/tmp")
        .appending(path: "nosleep-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let address = AgentControlAddress(directory: directory)
    let server = try AgentControlServer(address: address) { _ in .failure(.controlDisabled) }
    defer { withExtendedLifetime(server) {} }

    #expect(throws: AgentControlError.connectionFailed) {
        try AgentControlServer(address: address) { _ in .failure(.appNotRunning) }
    }
    let reply = try await Task.detached { try AgentControlSocket.call(.getStatus, at: address) }.value
    #expect(reply == .failure(.controlDisabled))
}

@Test func missingAgentControlSocketReportsAppNotRunning() {
    let directory = URL(fileURLWithPath: "/private/tmp")
        .appending(path: "nosleep-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    #expect(throws: AgentControlError.appNotRunning) {
        try AgentControlSocket.call(.getStatus, at: AgentControlAddress(directory: directory))
    }
}

@MainActor
private final class TestAgentSettings {
    var allowed = false
    var keepAwake = false
    var minutes = 10

    var status: AgentControlStatus {
        AgentControlStatus(
            powerSource: .battery,
            keepAwakeOnAC: keepAwake,
            keepAwakeStatus: keepAwake ? .pausedOnBattery : .off,
            idleLockAfterMinutes: minutes,
            displaySleepAfterMinutes: nil,
            idleLockStatus: .inactive
        )
    }

    func perform(_ request: AgentControlRequest) -> AgentControlReply {
        request.perform(
            allowed: allowed,
            setKeepAwake: { keepAwake = $0 },
            setIdleLock: { minutes = $0 },
            status: { status }
        )
    }
}
