import CoreFoundation
import Foundation
import IOKit.ps

enum PmsetOutput {
    enum ParseError: Error {
        case unrecognized
    }

    static func sleepDisabled(_ output: String) throws -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line.split(whereSeparator: \.isWhitespace)
            if columns.first == "SleepDisabled" || columns.first == "disablesleep" {
                if columns.dropFirst().first == "1" { return true }
                if columns.dropFirst().first == "0" { return false }
                throw ParseError.unrecognized
            }
        }

        guard output.contains("Currently in use:") || output.contains("System-wide power settings:"),
              output.split(whereSeparator: \.isNewline).contains(where: {
                  $0.split(whereSeparator: \.isWhitespace).first == "displaysleep"
              })
        else { throw ParseError.unrecognized }
        return false
    }

    static func acDisplayMinutes(_ output: String) throws -> Int {
        var onAC = false
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasSuffix(":") {
                onAC = text == "AC Power:"
                continue
            }
            let columns = text.split(whereSeparator: \.isWhitespace)
            if onAC, columns.first == "displaysleep",
               let value = columns.dropFirst().first.flatMap({ Int($0) }),
               (0...Int(Int32.max)).contains(value) {
                return value
            }
        }
        throw ParseError.unrecognized
    }
}

struct PmsetSettings: SystemPowerSettings {
    private let pmset = "/usr/bin/pmset"

    func sleepDisabled() throws -> Bool {
        try PmsetOutput.sleepDisabled(Command.run(pmset, ["-g"]))
    }

    func acDisplayMinutes() throws -> Int {
        try PmsetOutput.acDisplayMinutes(Command.run(pmset, ["-g", "custom"]))
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        _ = try Command.run(pmset, ["-a", "disablesleep", disabled ? "1" : "0"])
    }

    func setACDisplayMinutes(_ minutes: Int) throws {
        _ = try Command.run(pmset, ["-c", "displaysleep", String(minutes)])
    }
}

final class ExternalPowerMonitor {
    private let changed: @Sendable () -> Void
    private var source: CFRunLoopSource?

    init(changed: @escaping @Sendable () -> Void) {
        self.changed = changed
    }

    func start() -> Bool {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let notification = IOPSNotificationCreateRunLoopSource({ info in
            guard let info else { return }
            Unmanaged<ExternalPowerMonitor>.fromOpaque(info).takeUnretainedValue().changed()
        }, context)?.takeRetainedValue() else { return false }

        source = notification
        CFRunLoopAddSource(CFRunLoopGetMain(), notification, .commonModes)
        return true
    }

    deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
    }

    static func isOnAC() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return source as String == kIOPSACPowerValue
    }
}
