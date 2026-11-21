import AppKit
import Carbon
import Foundation
import OSLog

struct SystemScreenSaverSettings: ScreenSaverSettings, Sendable {
    private static let systemEventsID = "com.apple.systemevents"
    private static let systemEventsURL = URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")
    private static let log = Logger(subsystem: ServiceIdentity.app, category: "Screen Saver")
    // The property codes are declared in the installed System Events scripting dictionary.
    private static let preferencesCode: DescType = 0x73737670 // ssvp
    private static let delayCode: DescType = 0x646C7969 // dlyi

    func idleSeconds() throws -> Int {
        let reply = try send(AEEventID(kAEGetData))
        guard let value = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)),
              value.descriptorType == typeSInt32, value.int32Value >= 0
        else { throw ScreenSaverAccessError.unavailable }
        return Int(value.int32Value)
    }

    func setIdleSeconds(_ seconds: Int) throws {
        guard let value = Int32(exactly: seconds), value >= 0 else { throw ScreenSaverAccessError.unavailable }
        _ = try send(AEEventID(kAESetData), value: NSAppleEventDescriptor(int32: value))
    }

    func requestAuthorization() -> ScreenSaverAuthorizationResult {
        do {
            let target = try address()
            guard let descriptor = target.aeDesc else { return .failed }
            // Request consent for this target even if a particular event is exempt.
            let result = AEDeterminePermissionToAutomateTarget(
                descriptor, AEEventClass(typeWildCard), AEEventID(typeWildCard), true
            )
            switch result {
            case noErr: return .granted
            case OSStatus(errAEEventNotPermitted): return .denied
            default:
                Self.log.error("System Events authorization failed (\(result, privacy: .public)).")
                return .failed
            }
        } catch {
            return .failed
        }
    }

    private func send(_ eventID: AEEventID, value: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kAECoreSuite),
            eventID: eventID,
            targetDescriptor: try address(),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        let preferences = try property(Self.preferencesCode, in: .null())
        let delay = try property(Self.delayCode, in: preferences)
        event.setParam(delay, forKeyword: AEKeyword(keyDirectObject))
        if let value { event.setParam(value, forKeyword: AEKeyword(keyAEData)) }

        let reply: NSAppleEventDescriptor
        do {
            let noPrompt = NSAppleEventDescriptor.SendOptions(rawValue: UInt(kAEDoNotPromptForUserConsent))
            reply = try event.sendEvent(options: [.waitForReply, .neverInteract, noPrompt], timeout: 2)
        } catch {
            throw Self.accessError((error as NSError).code)
        }
        if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
            throw Self.accessError(Int(error.int32Value))
        }
        return reply
    }

    private func property(_ code: DescType, in container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        guard let specifier = record.coerce(toDescriptorType: typeObjectSpecifier) else {
            throw ScreenSaverAccessError.unavailable
        }
        return specifier
    }

    private func address() throws -> NSAppleEventDescriptor {
        if let target = runningTarget() { return target }
        _ = try Command.run("/usr/bin/open", ["-gj", Self.systemEventsURL.path], timeout: 2)
        for _ in 0..<10 {
            if let target = runningTarget() { return target }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw ScreenSaverAccessError.unavailable
    }

    private func runningTarget() -> NSAppleEventDescriptor? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.systemEventsID)
            .first { $0.bundleURL?.standardizedFileURL.path == Self.systemEventsURL.path && !$0.isTerminated }
            .map { NSAppleEventDescriptor(processIdentifier: $0.processIdentifier) }
    }

    private static func accessError(_ code: Int) -> ScreenSaverAccessError {
        switch code {
        case Int(errAEEventWouldRequireUserConsent): .authorizationRequired
        case Int(errAEEventNotPermitted): .permissionDenied
        default: .unavailable
        }
    }
}
