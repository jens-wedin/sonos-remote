import Foundation
import SonosKit

let usage = """
sonosctl list
sonosctl play|pause|next|prev <room>
sonosctl volume <room> <0-100>
sonosctl eq <room>
sonosctl watch
"""

@main
struct Sonosctl {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { print(usage); exit(2) }

        let transport = URLSessionTransport()
        let household = Household(discovery: BonjourDiscovery(), transport: transport, trustStore: transport.trustStore)
        let stream = await household.snapshots()
        await household.start()

        // Wait for discovery to settle, then give the websockets a moment to push current state.
        for await snapshot in stream {
            switch snapshot.status {
            case .ready where !snapshot.groups.isEmpty:
                break
            case .noPlayersFound:
                print("No Sonos found on this network."); exit(1)
            case .unauthorized:
                print("Authentication is switched on in the Sonos app; turn it off under connection security."); exit(1)
            case .localNetworkDenied:
                print("Local Network permission denied. System Settings → Privacy & Security → Local Network."); exit(1)
            case .discovering, .ready:
                continue
            }
            break
        }
        try? await Task.sleep(for: .seconds(1.5))
        let snapshot = await household.current

        func group(named name: String) -> Group? {
            let needle = name.lowercased()
            if let byGroup = snapshot.groups.first(where: { $0.name.lowercased().hasPrefix(needle) }) { return byGroup }
            if let player = snapshot.players.first(where: { $0.name.lowercased().hasPrefix(needle) }) {
                return snapshot.group(containing: player.id)
            }
            return nil
        }

        do {
            switch command {
            case "list":
                for g in snapshot.groups {
                    let track = g.nowPlaying.map { "\($0.title) — \($0.artist ?? "")" } ?? "—"
                    print("\(g.name) [\(g.playbackState)] vol \(g.volume.level)\(g.volume.muted ? " muted" : "")  \(track)")
                    for id in g.playerIDs {
                        let player = snapshot.player(id)
                        let volume = snapshot.playerVolumes[id]?.level ?? -1
                        print("    \(player?.name ?? id) @ \(player?.address ?? "?") vol \(volume)\(player?.hasSub == true ? " +sub" : "")")
                    }
                }
            case "play", "pause", "next", "prev":
                guard let target = group(named: arguments.dropFirst().joined(separator: " ")) else { print("No such room"); exit(1) }
                switch command {
                case "play": try await household.play(group: target.id)
                case "pause": try await household.pause(group: target.id)
                case "next": try await household.next(group: target.id)
                default: try await household.previous(group: target.id)
                }
                print("ok: \(command) \(target.name)")
            case "volume":
                guard arguments.count >= 3, let level = Int(arguments[arguments.count - 1]),
                      let target = group(named: arguments[1..<(arguments.count - 1)].joined(separator: " ")) else { print(usage); exit(2) }
                try await household.setGroupVolume(level, group: target.id)
                print("ok: \(target.name) volume \(level)")
            case "eq":
                guard let target = group(named: arguments.dropFirst().joined(separator: " ")) else { print("No such room"); exit(1) }
                for id in target.playerIDs {
                    let eq = try await household.eq(player: id)
                    print("\(snapshot.player(id)?.name ?? id): bass \(eq.bass) treble \(eq.treble) loudness \(eq.loudness) sub \(eq.subGain.map(String.init) ?? "n/a")")
                }
            case "watch":
                print("Watching events, Ctrl-C to stop…")
                for await snapshot in await household.snapshots() {
                    let line = snapshot.groups.map { "\($0.name):\($0.playbackState.rawValue.replacingOccurrences(of: "PLAYBACK_STATE_", with: "")):\($0.volume.level)" }.joined(separator: "  ")
                    print(Date.now.formatted(date: .omitted, time: .standard), line)
                }
            default:
                print(usage); exit(2)
            }
        } catch {
            print("error: \(error)"); exit(1)
        }
        await household.stop()
        exit(0)
    }
}
