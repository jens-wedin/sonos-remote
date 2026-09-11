import Foundation
import SonosKit

struct TonePreset: Hashable, Identifiable {
    let id: String
    let name: String
    let bass: Int
    let treble: Int

    static let flat = TonePreset(id: "flat", name: "Flat", bass: 0, treble: 0)
    static let warm = TonePreset(id: "warm", name: "Warm", bass: 3, treble: -2)
    static let bright = TonePreset(id: "bright", name: "Bright", bass: -2, treble: 3)
    static let all = [flat, warm, bright]

    /// The preset whose bass and treble equal the settings, ignoring loudness and sub.
    static func matching(_ eq: EQSettings) -> TonePreset? {
        all.first { $0.bass == eq.bass && $0.treble == eq.treble }
    }

    func applied(to eq: EQSettings) -> EQSettings {
        var next = eq
        next.bass = bass
        next.treble = treble
        return next
    }
}
