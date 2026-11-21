import Darwin
import Foundation

final class ScreenSaverAgent: @unchecked Sendable {
    private let queue = DispatchQueue(label: ServiceIdentity.screenSaverAgent)
    private let policy: ScreenSaverPolicy
    private var clients: Set<UUID> = []
    private var powerMonitoringAvailable = false
    private var timer: DispatchSourceTimer?

    init() {
        policy = ScreenSaverPolicy(
            settings: SystemScreenSaverSettings(),
            journal: ScreenSaverFileJournal(),
            isEligible: Self.isEligible
        )
    }

    func start(powerMonitoringAvailable: Bool) {
        queue.sync {
            self.powerMonitoringAvailable = powerMonitoringAvailable
            policy.release()
            updateMonitoring()
        }
    }

    func stop() {
        queue.sync { _ = policy.release() }
    }

    func connect() -> UUID {
        queue.sync {
            let client = UUID()
            clients.insert(client)
            return client
        }
    }

    func disconnect(_ client: UUID) {
        queue.async {
            self.clients.remove(client)
            self.policy.disconnect(client: client)
            self.updateMonitoring()
        }
    }

    func powerChanged() {
        queue.async { self.refresh() }
    }

    func apply(client: UUID, minimumSeconds: Int, reply: @escaping ModeReply) {
        queue.async {
            guard self.clients.contains(client), self.powerMonitoringAvailable else {
                reply(ScreenSaverStatus.unavailable.rawValue)
                return
            }
            let result = self.policy.apply(client: client, minimumSeconds: minimumSeconds)
            self.updateMonitoring()
            reply(result.rawValue)
        }
    }

    func restore(client: UUID, reply: @escaping ModeReply) {
        queue.async {
            guard self.clients.contains(client) else {
                reply(ScreenSaverStatus.unavailable.rawValue)
                return
            }
            let result = self.policy.release(client: client)
            self.updateMonitoring()
            reply(result.rawValue)
        }
    }

    private static func isEligible() -> Bool {
        ExternalPowerMonitor.isOnAC() && ConsoleUser.isActive(geteuid())
    }

    private func refresh() {
        policy.refresh()
        updateMonitoring()
    }

    private func updateMonitoring() {
        guard policy.needsMonitoring else {
            timer?.cancel()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: .seconds(5), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer
        timer.resume()
    }
}

final class ScreenSaverListener: NSObject, NSXPCListenerDelegate {
    private let agent: ScreenSaverAgent
    private let requirement: String

    init(agent: ScreenSaverAgent, team: String) {
        self.agent = agent
        requirement = ConnectionSigning.requirement(identifier: ServiceIdentity.app, team: team)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == geteuid() else { return false }
        connection.setCodeSigningRequirement(requirement)
        let client = agent.connect()
        connection.exportedInterface = NSXPCInterface(with: ScreenSaverServiceProtocol.self)
        connection.exportedObject = ScreenSaverEndpoint(client: client, agent: agent)
        connection.interruptionHandler = { [agent] in agent.disconnect(client) }
        connection.invalidationHandler = { [agent] in agent.disconnect(client) }
        connection.resume()
        return true
    }
}

private final class ScreenSaverEndpoint: NSObject, ScreenSaverServiceProtocol {
    let client: UUID
    let agent: ScreenSaverAgent

    init(client: UUID, agent: ScreenSaverAgent) {
        self.client = client
        self.agent = agent
    }

    func apply(minimumSeconds: Int, reply: @escaping ModeReply) {
        agent.apply(client: client, minimumSeconds: minimumSeconds, reply: reply)
    }

    func restore(reply: @escaping ModeReply) {
        agent.restore(client: client, reply: reply)
    }
}
