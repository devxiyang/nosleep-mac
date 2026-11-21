import SwiftUI

struct MenuSettings: View {
    let model: MenuModel
    let goBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: goBack) {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Back")

                Text("Settings")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()
            }

            Divider()

            Toggle(isOn: Binding(
                get: { model.loginItemState.isRegistered },
                set: model.setLaunchAtLogin
            )) {
                Text("Launch at Login")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(model.loginItemState == .unavailable)

            if model.loginItemState == .approvalRequired {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Approve NoSleep in Login Items.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Login Items", action: model.openLoginItemsSettings)
                        .buttonStyle(.bordered)
                }
                .font(.caption)
            } else if model.loginItemState == .unavailable {
                Text("The login item is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.loginItemUpdateFailed {
                Text("Could not update the login item.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Toggle(isOn: Binding(
                get: { model.agentControlEnabled },
                set: model.setAgentControlEnabled
            )) {
                Text("Allow Local Agent Control")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)

            if model.agentControlEnabled && !model.agentControlAvailable {
                Text("Could not start local Agent control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 12) {
                Text("Language")
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                Picker("Language", selection: Binding(get: { model.language }, set: model.setLanguage)) {
                    Text("Follow System").tag(MenuLanguage.system)

                    ForEach(MenuLanguage.supported) { option in
                        Text(verbatim: option.nativeName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .font(.caption)

            if let action = model.idleLockNotice?.settingsAction {
                Divider()

                Button {
                    model.perform(action)
                } label: {
                    Label {
                        Text(action.title)
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .controlSize(.small)
        .task {
            while !Task.isCancelled {
                model.refreshLoginItemStatus()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
