import Darwin
import Foundation

enum CommandError: Error {
    case timeout
    case failed(Int32, String)
}

enum Command {
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 3) throws -> String {
        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        // The selected commands have small, bounded output.
        guard finished.wait(timeout: .now() + timeout) == .success else {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw CommandError.timeout
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CommandError.failed(process.terminationStatus, text)
        }
        return text
    }
}
