import SwiftUI
import SonosKit

struct HeaderView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            if state.screen == .main {
                Text(Screen.main.title)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
            } else {
                Button { state.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .keyboardShortcut("[", modifiers: .command)
                Artwork(url: state.selectedGroup?.nowPlaying?.artworkURL, size: 22)
                Text(state.screen.title)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.6)
            }
            Spacer()
            ForEach(Screen.iconScreens, id: \.self) { screen in
                IconButton(systemImage: screen.systemImage, label: screen.accessibilityName, isActive: state.screen == screen) {
                    withAnimation(.easeInOut(duration: 0.2)) { state.show(screen) }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .accessibilityElement(children: .contain)
    }
}
