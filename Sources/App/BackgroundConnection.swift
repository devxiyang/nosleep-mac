import Foundation

@MainActor
final class BackgroundConnection<Endpoint, Status: RawRepresentable & Sendable> where Status.RawValue == String {
    private let identifier: String
    private let interface: NSXPCInterface
    private let options: NSXPCConnection.Options
    private let unavailable: Status
    private var connection: NSXPCConnection?

    var isConnected: Bool { connection != nil }

    init(
        identifier: String,
        interface: NSXPCInterface,
        options: NSXPCConnection.Options = [],
        unavailable: Status
    ) {
        self.identifier = identifier
        self.interface = interface
        self.options = options
        self.unavailable = unavailable
    }

    func close() {
        connection?.invalidate()
        connection = nil
    }

    func call(_ send: (Endpoint, @escaping ModeReply) -> Void) async -> Status {
        guard let current = connection ?? connect() else { return unavailable }
        let result = await Self.sendRequest(on: current, unavailable: unavailable, send)
        if result.rawValue == unavailable.rawValue && connection === current { close() }
        return result
    }

    static func sendRequest(
        on connection: NSXPCConnection,
        unavailable: Status,
        _ send: (Endpoint, @escaping ModeReply) -> Void
    ) async -> Status {
        await withCheckedContinuation { continuation in
            let reply = PendingReply(continuation)
            // Foundation can deliver transport failures on its connection queue.
            let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable _ in
                reply.finish(unavailable)
            }
            guard let service = proxy as? Endpoint else {
                reply.finish(unavailable)
                return
            }
            send(service) { raw in reply.finish(Status(rawValue: raw) ?? unavailable) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 12) { reply.finish(unavailable) }
        }
    }

    private func connect() -> NSXPCConnection? {
        guard let team = ConnectionSigning.teamID() else { return nil }
        let transport = NSXPCConnection(machServiceName: identifier, options: options)
        transport.remoteObjectInterface = interface
        transport.setCodeSigningRequirement(ConnectionSigning.requirement(identifier: identifier, team: team))
        transport.resume()
        connection = transport
        return transport
    }
}

private final class PendingReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Value) {
        let reply = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        reply?.resume(returning: value)
    }
}
