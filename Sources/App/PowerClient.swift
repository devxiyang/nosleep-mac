import Foundation

@MainActor
final class PowerClient {
    private var connection: NSXPCConnection?

    var isConnected: Bool { connection != nil }

    func setMode(_ enabled: Bool, minutes: Int) async -> PowerModeStatus {
        await call(.set(enabled: enabled, minutes: minutes))
    }

    func status() async -> PowerModeStatus {
        await call(.status)
    }

    func close() {
        connection?.invalidate()
        connection = nil
    }

    private enum Request {
        case set(enabled: Bool, minutes: Int)
        case status
    }

    private func call(_ request: Request) async -> PowerModeStatus {
        guard let current = connection ?? connect() else { return .unavailable }
        let result = await withCheckedContinuation { continuation in
            let reply = PendingReply(continuation)
            let proxy = current.remoteObjectProxyWithErrorHandler { _ in
                reply.finish(.unavailable)
            }

            guard let service = proxy as? PowerServiceProtocol else {
                reply.finish(.unavailable)
                return
            }
            let receive: ModeReply = { rawStatus in
                reply.finish(PowerModeStatus(rawValue: rawStatus) ?? .unavailable)
            }
            switch request {
            case let .set(enabled, minutes):
                service.setMode(enabled, displayMinutes: minutes, reply: receive)
            case .status:
                service.status(reply: receive)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
                reply.finish(.unavailable)
            }
        }

        if result == .unavailable && connection === current { close() }
        return result
    }

    private func connect() -> NSXPCConnection? {
        guard let team = ConnectionSigning.teamID() else { return nil }
        let transport = NSXPCConnection(machServiceName: ServiceIdentity.helper, options: .privileged)
        transport.remoteObjectInterface = NSXPCInterface(with: PowerServiceProtocol.self)
        transport.setCodeSigningRequirement(
            ConnectionSigning.requirement(identifier: ServiceIdentity.helper, team: team)
        )
        transport.resume()
        connection = transport
        return transport
    }
}

private final class PendingReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PowerModeStatus, Never>?

    init(_ continuation: CheckedContinuation<PowerModeStatus, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: PowerModeStatus) {
        let reply = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        reply?.resume(returning: value)
    }
}
