import SwiftUI
import SonosKit

struct VolumeRowView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        VolumeSliderView(
            volume: group.volume,
            accessibilityName: group.name,
            style: .hero,
            onChange: { state.setGroupVolume($0, group: group.id) },
            onMute: { state.setGroupMuted($0, group: group.id) }
        )
        .padding(.horizontal, 16)
    }
}
