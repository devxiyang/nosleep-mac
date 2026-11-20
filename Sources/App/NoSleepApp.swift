import SwiftUI

@main
struct NoSleepApp: App {
    @State private var model = MenuModel()

    var body: some Scene {
        MenuBarExtra {
            NoSleepMenu(model: model)
        } label: {
            Label("NoSleep", systemImage: model.status == .power(.active) ? "bolt.fill" : "bolt")
        }
        .menuBarExtraStyle(.window)
    }
}
