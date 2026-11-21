import Foundation
import Testing

@MainActor
@Test func xpcConnectionRejectionReturnsUnavailable() async {
    let listener = NSXPCListener.anonymous()
    let delegate = RejectingXPCListenerDelegate()
    listener.delegate = delegate
    listener.resume()

    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: PowerServiceProtocol.self)
    connection.resume()
    defer {
        connection.invalidate()
        listener.invalidate()
        withExtendedLifetime(delegate) {}
    }

    let start = ContinuousClock.now
    let result = await BackgroundConnection<PowerServiceProtocol, PowerModeStatus>.sendRequest(
        on: connection,
        unavailable: .unavailable
    ) { service, reply in
        service.status(reply: reply)
    }
    #expect(delegate.didReject)
    #expect(result == .unavailable)
    #expect(ContinuousClock.now - start < .seconds(10))
}

private final class RejectingXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let lock = NSLock()
    private var rejected = false

    var didReject: Bool { lock.withLock { rejected } }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lock.withLock { rejected = true }
        return false
    }
}
