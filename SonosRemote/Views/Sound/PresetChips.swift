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
                .focusable()
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
            .font(.caption.weight(lit ? .semibold : .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(lit ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
            .foregroundStyle(lit ? Color.primary : Color.supporting)
            .overlay {
                if lit {
                    Capsule().strokeBorder(Color.accentColor, lineWidth: 1)
                }
            }
    }
}
