import SwiftUI
import SonosKit

struct EQTabView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    private var players: [Player] { group.playerIDs.compactMap { state.snapshot.player($0) } }
    private var playerID: String { state.eqPlayerID ?? group.coordinatorID }
    private var player: Player? { state.snapshot.player(playerID) }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 6) {
            if players.count > 1 {
                Picker("Room", selection: $state.eqPlayerID) {
                    ForEach(players) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Room for EQ")
            }

            if let eq = state.eqByPlayer[playerID], let player {
                EQSlider(label: "Bass", value: eq.bass, range: EQSettings.bassRange, room: player.name) { new in
                    var next = eq; next.bass = new; state.updateEQ(next, player: playerID)
                }
                EQSlider(label: "Treble", value: eq.treble, range: EQSettings.trebleRange, room: player.name) { new in
                    var next = eq; next.treble = new; state.updateEQ(next, player: playerID)
                }
                if player.hasSub, let sub = eq.subGain {
                    EQSlider(label: "Sub", value: sub, range: EQSettings.subGainRange, room: player.name) { new in
                        var next = eq; next.subGain = new; state.updateEQ(next, player: playerID)
                    }
                }
                Toggle("Loudness", isOn: Binding(
                    get: { eq.loudness },
                    set: { on in var next = eq; next.loudness = on; state.updateEQ(next, player: playerID) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
                .accessibilityLabel("Loudness for \(player.name)")
            } else {
                HStack { ProgressView().controlSize(.small); Text("Reading EQ…").font(.caption).foregroundStyle(.secondary) }
                    .padding(.vertical, 8)
            }
        }
        .task(id: playerID) { state.loadEQ(player: playerID) }
    }
}

/// Integer slider with a label, a value readout, and double-click-to-zero.
private struct EQSlider: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let room: String
    let onChange: (Int) -> Void

    @State private var local: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Slider(value: $local, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
                if !editing, Int(local) != value { onChange(Int(local)) }
            }
            .accessibilityLabel("\(label) for \(room)")
            .accessibilityValue("\(Int(local))")
            .onTapGesture(count: 2) { local = 0; onChange(0) }
            Text(Int(local) > 0 ? "+\(Int(local))" : "\(Int(local))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .onAppear { local = Double(value) }
        .onChange(of: value) { _, new in local = Double(new) }
    }
}
