import SwiftUI

/// Menu-style picker showing a speaker glyph and the chosen name; used for "Play to" and "Tuning".
struct RoomPicker: View {
    let title: String
    @Binding var selection: String?
    let options: [(id: String, name: String)]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.id) { option in
                Label(option.name, systemImage: "hifispeaker").tag(Optional(option.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(title)
    }
}
