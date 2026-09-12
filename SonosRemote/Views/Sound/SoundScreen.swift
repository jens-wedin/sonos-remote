import SwiftUI
import SonosKit

struct SoundScreen: View {
    @Environment(AppState.self) private var state

    private var playerID: String? { state.soundPlayerID ?? state.selectedGroup?.coordinatorID }
    private var player: Player? { playerID.flatMap { state.player($0) } }
    private var playerOptions: [(id: String, name: String)] {
        state.players
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { ($0.id, $0.name) }
    }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 0) {
            StatusBannerView()
            SectionLabel("TUNING") {
                RoomPicker(title: "Room to tune", selection: $state.soundPlayerID, options: playerOptions)
            }
            if let playerID, let player {
                if let eq = state.eqByPlayer[playerID] {
                    PresetChips(current: TonePreset.matching(eq)) { state.applyPreset($0, player: playerID) }
                    SectionLabel("TONE") {
                        Button("Reset") { state.resetTone(player: playerID) }
                            .buttonStyle(.link)
                            .focusable()
                            .font(.caption)
                            .accessibilityLabel("Reset tone for \(player.name)")
                    }
                    Card {
                        CardRow(isFirst: true) {
                            ToneSlider(label: "Bass", value: eq.bass, range: EQSettings.bassRange, room: player.name) { new in
                                var next = eq; next.bass = new; state.updateEQ(next, player: playerID)
                            }
                        }
                        CardRow {
                            ToneSlider(label: "Treble", value: eq.treble, range: EQSettings.trebleRange, room: player.name) { new in
                                var next = eq; next.treble = new; state.updateEQ(next, player: playerID)
                            }
                        }
                        if player.hasSub, let sub = eq.subGain {
                            CardRow {
                                ToneSlider(label: "Sub", value: sub, range: EQSettings.subGainRange, room: player.name) { new in
                                    var next = eq; next.subGain = new; state.updateEQ(next, player: playerID)
                                }
                            }
                        }
                    }
                    Card {
                        CardRow(isFirst: true) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Loudness").font(.callout).accessibilityHidden(true)
                                Text("Boosts bass and treble at low volume").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Loudness", isOn: Binding(
                                get: { eq.loudness },
                                set: { on in var next = eq; next.loudness = on; state.updateEQ(next, player: playerID) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .accessibilityLabel("Loudness for \(player.name)")
                        }
                    }
                    .padding(.top, 12)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading EQ…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .accessibilityElement(children: .combine)
                }
                if let error = state.rowErrors[state.group(containing: playerID)?.id ?? playerID] {
                    ErrorLine(text: error)
                }
            } else {
                Text("No room selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .padding(.bottom, 12)
        .task(id: playerID) {
            if let playerID { state.loadEQ(player: playerID) }
        }
    }
}
