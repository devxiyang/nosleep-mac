import AppKit
import SwiftUI

struct NoSleepMenu: View {
    let model: MenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            MenuFooter(language: Binding(get: { model.language }, set: model.setLanguage))
        }
        .padding(14)
        .frame(width: 340)
        .environment(\.locale, model.language.locale)
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

    @Binding var language: MenuLanguage

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "by")
                    .foregroundStyle(.secondary)

                Link(destination: Self.octoiiURL) {
                    Text(verbatim: "octoii")
                }
            }
            .font(.body.weight(.medium))

            Spacer()

            Picker("Language", selection: $language) {
                ForEach(MenuLanguage.allCases) { option in
                    Text(verbatim: option.nativeName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .help("Language")

            Button("Quit NoSleep") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
