import SwiftUI

/// Integer slider with a label, a signed readout, and double-click-to-zero.
struct ToneSlider: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let room: String
    let onChange: (Int) -> Void

    @State private var local: Double = 0

    var body: some View {
        Text(label).font(.callout).frame(width: 52, alignment: .leading)
        Slider(value: $local, in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
            if !editing, Int(local) != value { onChange(Int(local)) }
        }
        .accessibilityLabel("\(label) for \(room)")
        .accessibilityValue("\(Int(local))")
        .onTapGesture(count: 2) { local = 0; onChange(0) }
        Text(ToneValue.string(Int(local)))
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 30, alignment: .trailing)
            .accessibilityHidden(true)
            .onAppear { local = Double(value) }
            .onChange(of: value) { _, new in local = Double(new) }
    }
}
