import SwiftUI

struct IdleDurationField: View {
    @Environment(\.locale) private var locale

    let duration: IdleDuration
    let save: (IdleDuration) -> Void

    @State private var editingCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Idle display & lock")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Menu {
                    ForEach(IdleDuration.presets, id: \.self) { preset in
                        Button {
                            apply(preset)
                        } label: {
                            let label = preset.formatted(in: locale)
                            if preset == duration {
                                Label {
                                    Text(verbatim: label)
                                } icon: {
                                    Image(systemName: "checkmark")
                                }
                            } else {
                                Text(verbatim: label)
                            }
                        }
                    }

                    Divider()

                    Button("Custom…") { editingCustom = true }
                } label: {
                    Text(verbatim: duration.formatted(in: locale))
                        .monospacedDigit()
                }
                .fixedSize()
                .accessibilityLabel("Idle time")
            }

            if editingCustom {
                CustomIdleDurationEditor(
                    duration: duration,
                    apply: apply,
                    cancel: { editingCustom = false }
                )
            }
        }
    }

    private func apply(_ value: IdleDuration) {
        save(value)
        editingCustom = false
    }
}

private struct CustomIdleDurationEditor: View {
    let apply: (IdleDuration) -> Void
    let cancel: () -> Void

    @State private var text: String
    @State private var unit: DurationUnit

    init(duration: IdleDuration, apply: @escaping (IdleDuration) -> Void, cancel: @escaping () -> Void) {
        _text = State(initialValue: String(duration.count))
        _unit = State(initialValue: duration.unit)
        self.apply = apply
        self.cancel = cancel
    }

    private var value: IdleDuration? {
        IdleDuration.custom(text, unit: unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField("Idle time", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onSubmit(commit)

                Picker("Unit", selection: $unit) {
                    Text("Minutes").tag(DurationUnit.minutes)
                    Text("Hours").tag(DurationUnit.hours)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if value == nil {
                Text("Enter a positive whole number within the supported range.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)

                Button("Apply", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(value == nil)
            }
            .controlSize(.small)
        }
    }

    private func commit() {
        if let value { apply(value) }
    }
}
