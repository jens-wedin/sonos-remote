import SwiftUI
import SonosKit

struct StatusBannerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.snapshot.status != .ready {
            Text(String(describing: state.snapshot.status))
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
    }
}
