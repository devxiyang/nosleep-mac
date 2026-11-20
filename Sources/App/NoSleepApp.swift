import AppKit
import SwiftUI

@main
struct NoSleepApp: App {
    @State private var model = MenuModel()

    var body: some Scene {
        MenuBarExtra {
            NoSleepMenu(model: model)
        } label: {
            Label {
                Text("NoSleep")
            } icon: {
                Image(nsImage: model.status == .power(.active) ? MenuBarMark.active : MenuBarMark.idle)
                    .renderingMode(.template)
            }
            .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private enum MenuBarMark {
    static let active = make(filled: true)
    static let idle = make(filled: false)

    private static func make(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()

            let notebook = NSBezierPath()
            notebook.appendRoundedRect(
                NSRect(x: 1.25, y: 1.6, width: 15.5, height: 1.65),
                xRadius: 0.8, yRadius: 0.8
            )
            notebook.appendRoundedRect(
                NSRect(x: 1.25, y: 4, width: 15.5, height: 1.8),
                xRadius: 0.9, yRadius: 0.9
            )
            notebook.fill()

            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: 9.2, y: 16.35))
            bolt.line(to: NSPoint(x: 5.95, y: 11.15))
            bolt.line(to: NSPoint(x: 8.45, y: 11.15))
            bolt.line(to: NSPoint(x: 7.25, y: 7.15))
            bolt.line(to: NSPoint(x: 12.1, y: 13.05))
            bolt.line(to: NSPoint(x: 9.65, y: 13.05))
            bolt.line(to: NSPoint(x: 11.2, y: 16.35))
            bolt.close()

            if filled {
                bolt.fill()
            } else {
                bolt.lineWidth = 1
                bolt.lineJoinStyle = .round
                bolt.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
