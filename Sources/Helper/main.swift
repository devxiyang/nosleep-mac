import Darwin
import Foundation
import OSLog

guard geteuid() == 0 else {
    Logger(subsystem: ServiceIdentity.app, category: "PowerHelper").error("A system launch daemon must run as root.")
    exit(EX_NOPERM)
}

let powerOverride = PowerOverride(settings: PmsetSettings(), journal: FileRecoveryJournal())
let policy = PowerPolicy(override: powerOverride, onExternalPower: ExternalPowerMonitor.isOnAC)
let daemon = PowerDaemon(policy: policy)
let monitor = ExternalPowerMonitor { daemon.powerChanged() }

signal(SIGTERM, SIG_IGN)
let shutdown = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
shutdown.setEventHandler {
    daemon.stop()
    exit(EXIT_SUCCESS)
}
shutdown.resume()
daemon.start(canMonitorPower: monitor.start())

let delegate = PowerListener(daemon: daemon, team: ConnectionSigning.teamID())
let listener = NSXPCListener(machServiceName: ServiceIdentity.helper)
listener.delegate = delegate
listener.resume()
withExtendedLifetime((monitor, delegate, listener, shutdown)) {
    RunLoop.main.run()
}
