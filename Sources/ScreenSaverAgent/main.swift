import Darwin
import Foundation

guard geteuid() != 0, let team = ConnectionSigning.teamID() else { exit(EX_NOPERM) }

let agent = ScreenSaverAgent()
let monitor = ExternalPowerMonitor { agent.powerChanged() }
let shutdown = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
signal(SIGTERM, SIG_IGN)
shutdown.setEventHandler {
    agent.stop()
    exit(EXIT_SUCCESS)
}
shutdown.resume()
agent.start(powerMonitoringAvailable: monitor.start())

let delegate = ScreenSaverListener(agent: agent, team: team)
let listener = NSXPCListener(machServiceName: ServiceIdentity.screenSaverAgent)
listener.delegate = delegate
listener.resume()
withExtendedLifetime((monitor, delegate, listener, shutdown)) { RunLoop.main.run() }
