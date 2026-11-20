import AppKit
import SwiftUI

struct NoSleepMenu: View {
    let model: MenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Keep running when plugged in with the lid closed",
                isOn: Binding(get: { model.enabled }, set: model.setEnabled)
            )
            .toggleStyle(.switch)

            IdleDurationField(
                count: model.savedCount,
                unit: model.savedUnit,
                save: model.saveDuration
            )

            Divider()

            StatusControls(model: model)

            Button("Quit NoSleep") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 330)
    }
}

private struct IdleDurationField: View {
    @State private var countText: String
    @State private var unit: DurationUnit
    @FocusState private var editingCount: Bool
    let save: (Int, DurationUnit) -> Void

    init(count: Int, unit: DurationUnit, save: @escaping (Int, DurationUnit) -> Void) {
        _countText = State(initialValue: String(count))
        _unit = State(initialValue: unit)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn off the display and lock after")
            HStack {
                TextField("Idle time", text: $countText)
                    .labelsHidden()
                    .frame(width: 72)
                    .focused($editingCount)
                    .onSubmit(commit)
                Picker("Unit", selection: $unit) {
                    Text("Minutes").tag(DurationUnit.minutes)
                    Text("Hours").tag(DurationUnit.hours)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: unit) { commit() }
            }

            if Int(countText).flatMap(unit.totalMinutes) == nil {
                Text("Enter a positive whole number within the supported range.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: editingCount) {
            if !editingCount { commit() }
        }
    }

    private func commit() {
        guard let count = Int(countText), unit.totalMinutes(count) != nil else { return }
        save(count, unit)
    }
}

private struct StatusControls: View {
    let model: MenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.status.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch model.status {
            case .installHelper:
                Button("Set Up Power Helper", action: model.installHelper)
            case .approveHelper:
                Button("Open Background Items", action: model.openHelperSettings)
            case .lockPolicyRequired:
                HStack {
                    Button("Open Lock Screen Settings", action: model.openLockSettings)
                    Button("Check Again", action: model.apply)
                }
            case .lockPolicyUnavailable, .power(.off), .power(.failed), .power(.unavailable),
                 .power(.busy), .power(.settingsChanged), .power(.existingOverride):
                if model.enabled {
                    Button("Retry", action: model.apply)
                }
            default:
                EmptyView()
            }
        }
    }
}
