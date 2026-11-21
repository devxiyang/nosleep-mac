import CoreFoundation
import IOKit.ps

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
        powerSource() == .ac
    }

    static func powerSource() -> PowerSource {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return .unknown }
        switch source as String {
        case kIOPSACPowerValue: return .ac
        case kIOPSBatteryPowerValue: return .battery
        default: return .unknown
        }
    }
}
