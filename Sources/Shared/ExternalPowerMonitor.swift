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
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return source as String == kIOPSACPowerValue
    }
}
