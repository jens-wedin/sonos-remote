import SwiftUI

/// Rounded surface used by every sub-screen. Put `CardRow`s inside; they draw their own separators.
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
    }
}

/// One row inside a Card: 12 pt padding and a hairline above every row but the first.
struct CardRow<Content: View>: View {
    var isFirst = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if !isFirst { Divider().padding(.leading, 12) }
            HStack(spacing: 12) { content() }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }
}
