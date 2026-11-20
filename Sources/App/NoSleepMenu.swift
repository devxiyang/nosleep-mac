import AppKit
import SwiftUI

struct NoSleepMenu: View {
    let model: MenuModel

    @State private var showingSettings = false

    var body: some View {
        let locale = model.language.resolved().locale

        VStack(alignment: .leading, spacing: 12) {
            if showingSettings {
                MenuSettings(model: model) { showingSettings = false }
            } else {
                ModeControls(
                    enabled: Binding(get: { model.enabled }, set: model.setEnabled),
                    status: model.status,
                    perform: model.perform
                )

                Divider()

                IdleDurationField(duration: IdleDuration(count: model.savedCount, unit: model.savedUnit)) { value in
                    model.saveDuration(value.count, unit: value.unit)
                }

                Divider()

                MenuFooter { showingSettings = true }
            }
        }
        .padding(14)
        .frame(width: 340)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
        .onDisappear { showingSettings = false }
    }
}

private struct ModeControls: View {
    private static let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    @Binding var enabled: Bool
    let status: MenuStatus
    let perform: (MenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: Self.appIcon)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Keep awake with lid closed")
                        .font(.headline)
                    Text(status.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle("Keep awake with lid closed", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if enabled, let action = status.action {
                Button {
                    perform(action)
                } label: {
                    Text(action.title)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.leading, 44)
            }
        }
    }
}

private struct MenuFooter: View {
    private static let octoiiURL = URL(string: "https://octoii.com")!

    let showSettings: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "❤️ By")
                    .foregroundStyle(.secondary)

                Link(destination: Self.octoiiURL) {
                    Text(verbatim: "Octoii")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                        .underline()
                }
            }
            .font(.body.weight(.medium))

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button(action: showSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")

                Button("Quit NoSleep") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
    }
}
