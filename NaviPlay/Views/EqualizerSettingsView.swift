import SwiftUI

struct EqualizerSettingsView: View {
    @EnvironmentObject private var player: PlayerController

    private var enabled: Binding<Bool> {
        Binding(get: { player.equalizerSettings.enabled },
                set: { player.setEqualizerEnabled($0) })
    }

    private var preset: Binding<EqualizerPreset> {
        Binding(get: { player.equalizerSettings.preset },
                set: { player.selectEqualizerPreset($0) })
    }

    private var mode: Binding<EqualizerMode> {
        Binding(get: { player.equalizerSettings.mode },
                set: { player.selectEqualizerMode($0) })
    }

    private func gain(at index: Int) -> Binding<Double> {
        Binding(get: { player.equalizerSettings.gains[index] },
                set: { player.setEqualizerGain($0, at: index) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Enable Equalizer", isOn: enabled)
                    .font(.system(size: 14, weight: .semibold))
                    .tint(.spAccent)

                Picker("Bands", selection: mode) {
                    ForEach(EqualizerMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Text("Preset")
                        .font(.system(size: 13))
                        .foregroundColor(.spText)
                    Spacer()
                    Picker("Preset", selection: preset) {
                        ForEach(EqualizerPreset.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    .disabled(!player.equalizerSettings.enabled)
                    Button("Reset") { player.selectEqualizerPreset(.flat) }
                        .controlSize(.small)
                        .disabled(!player.equalizerSettings.enabled)
                }

                Rectangle().fill(Color.spBorder).frame(height: 1)

                VStack(spacing: player.equalizerSettings.mode == .simple ? 22 : 9) {
                    ForEach(player.equalizerSettings.frequencies.indices, id: \.self) { index in
                        HStack(spacing: 14) {
                            Text(player.equalizerSettings.mode == .simple
                                 ? player.equalizerSettings.mode.labels[index]
                                 : "\(player.equalizerSettings.mode.labels[index]) Hz")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.spText)
                                .frame(width: 55, alignment: .leading)
                            Slider(value: gain(at: index), in: -12...12, step: 0.5)
                                .tint(.spAccent)
                                .accessibilityLabel("\(player.equalizerSettings.mode.labels[index]) gain")
                            Text(String(format: "%+.1f dB", player.equalizerSettings.gains[index]))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.spSubtext)
                                .frame(width: 65, alignment: .trailing)
                        }
                    }
                }
                .disabled(!player.equalizerSettings.enabled)

                HStack {
                    Text("−12 dB")
                    Spacer()
                    Text("0 dB")
                    Spacer()
                    Text("+12 dB")
                }
                .font(.system(size: 10))
                .foregroundColor(.spSubtext)
                .padding(.leading, 69)
                .padding(.trailing, 65)

                Text("Changes are saved automatically. Wallsy lowers the overall level when you boost a band to reduce clipping.")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.spBackground)
    }
}
