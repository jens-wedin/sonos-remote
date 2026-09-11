import Testing
import SonosKit
@testable import SonosRemote

@Suite struct TonePresetTests {
    @Test func presetsHaveTheSpecifiedValues() {
        #expect(TonePreset.all.map(\.name) == ["Flat", "Warm", "Bright"])
        #expect(TonePreset.flat.bass == 0 && TonePreset.flat.treble == 0)
        #expect(TonePreset.warm.bass == 3 && TonePreset.warm.treble == -2)
        #expect(TonePreset.bright.bass == -2 && TonePreset.bright.treble == 3)
    }

    @Test func matchingIgnoresLoudnessAndSub() {
        #expect(TonePreset.matching(EQSettings(bass: 3, treble: -2, loudness: true, subGain: -5)) == .warm)
        #expect(TonePreset.matching(EQSettings(bass: 0, treble: 0, loudness: false, subGain: nil)) == .flat)
        #expect(TonePreset.matching(EQSettings(bass: 1, treble: 0, loudness: false, subGain: nil)) == nil)
    }

    @Test func applyingKeepsLoudnessAndSub() {
        let applied = TonePreset.bright.applied(to: EQSettings(bass: 0, treble: 0, loudness: true, subGain: -4))
        #expect(applied == EQSettings(bass: -2, treble: 3, loudness: true, subGain: -4))
    }

    @Test func toneValuesUseSignsAndARealMinus() {
        #expect(ToneValue.string(3) == "+3")
        #expect(ToneValue.string(-2) == "−2")
        #expect(ToneValue.string(0) == "0")
    }
}
