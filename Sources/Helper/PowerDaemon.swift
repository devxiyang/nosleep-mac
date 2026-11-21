import Darwin
import Foundation

// The queue serializes XPC calls, disconnect handling, and power notifications.
final class PowerDaemon: @unchecked Sendable {
    private let queue = DispatchQueue(label: ServiceIdentity.helper)
    private let policy: PowerPolicy
    private var clients: [UUID: uid_t] = [:]
    private var canMonitorPower = false
    private var retryTimer: DispatchSourceTimer?

    init(policy: PowerPolicy) {
        self.policy = policy
    }

    func start(canMonitorPower: Bool) {
        queue.sync {
            self.canMonitorPower = canMonitorPower
            policy.recover()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: .seconds(5), leeway: .seconds(1))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.releaseWhenConsoleUserChanges()
                switch self.policy.status {
                case .restorePending:
                    self.policy.refresh()
                case .active where !ExternalPowerMonitor.isOnAC(),
                     .battery where ExternalPowerMonitor.isOnAC():
                    self.policy.refresh()
                default:
                    break
                }
            }
            retryTimer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync { policy.recover() }
    }

    func connect(user: uid_t) -> UUID {
        queue.sync {
            let client = UUID()
            clients[client] = user
            return client
        }
    }

    func disconnect(_ client: UUID) {
        queue.async {
            self.clients.removeValue(forKey: client)
            self.policy.disconnect(client: client)
        }
    }

    func powerChanged() {
        queue.async {
            self.releaseWhenConsoleUserChanges()
            self.policy.refresh()
        }
    }

    func setMode(client: UUID, enabled: Bool, minutes: Int, reply: @escaping ModeReply) {
        queue.async {
            guard let user = self.clients[client] else {
                reply(PowerModeStatus.unavailable.rawValue)
                return
            }
            if enabled && !self.canMonitorPower {
                reply(PowerModeStatus.unavailable.rawValue)
                return
            }
            if enabled && !ConsoleUser.isActive(user) {
                self.policy.disconnect(client: client)
                reply(PowerModeStatus.inactiveUser.rawValue)
                return
            }
            reply(self.policy.setMode(client: client, enabled: enabled, displayMinutes: minutes).rawValue)
        }
    }

    func status(client: UUID, reply: @escaping ModeReply) {
        queue.async {
            guard let user = self.clients[client], ConsoleUser.isActive(user) else {
                self.policy.disconnect(client: client)
                reply(PowerModeStatus.inactiveUser.rawValue)
                return
            }
            reply(self.policy.status(for: client).rawValue)
        }
    }

    private func releaseWhenConsoleUserChanges() {
        if let owner = policy.owner, let user = clients[owner], !ConsoleUser.isActive(user) {
            policy.disconnect(client: owner)
        }
    }
}

final class PowerListener: NSObject, NSXPCListenerDelegate {
    private let daemon: PowerDaemon
    private let requirement: String?

    init(daemon: PowerDaemon, team: String?) {
        self.daemon = daemon
        requirement = team.map { ConnectionSigning.requirement(identifier: ServiceIdentity.app, team: $0) }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement else { return false }
        connection.setCodeSigningRequirement(requirement)

        let client = daemon.connect(user: connection.effectiveUserIdentifier)
        connection.exportedInterface = NSXPCInterface(with: PowerServiceProtocol.self)
        connection.exportedObject = PowerEndpoint(client: client, daemon: daemon)
        connection.interruptionHandler = { [daemon] in daemon.disconnect(client) }
        connection.invalidationHandler = { [daemon] in daemon.disconnect(client) }
        connection.resume()
        return true
    }
}

private final class PowerEndpoint: NSObject, PowerServiceProtocol {
    private let client: UUID
    private let daemon: PowerDaemon

    init(client: UUID, daemon: PowerDaemon) {
        self.client = client
        self.daemon = daemon
    }

    func setMode(_ enabled: Bool, displayMinutes: Int, reply: @escaping ModeReply) {
        daemon.setMode(client: client, enabled: enabled, minutes: displayMinutes, reply: reply)
    }

    func status(reply: @escaping ModeReply) {
        daemon.status(client: client, reply: reply)
    }
}
