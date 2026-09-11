import SwiftUI

/// Flat / Warm / Bright / Custom. `current == nil` lights Custom; Custom itself is not a button.
struct PresetChips: View {
    let current: TonePreset?
    let onSelect: (TonePreset) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TonePreset.all) { preset in
                Button { onSelect(preset) } label: {
                    Chip(title: preset.name, lit: current == preset)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(current == preset ? [.isSelected] : [])
            }
            Chip(title: "Custom", lit: current == nil)
                .accessibilityLabel(current == nil ? "Custom, selected" : "Custom")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct Chip: View {
    let title: String
    let lit: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(lit ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
            .foregroundStyle(lit ? Color.accentColor : Color.primary)
    }
}
