import SwiftUI
import SonosKit

struct OpenRowView: View {
    @Environment(AppState.self) private var state
    let group: SonosGroup

    var body: some View {
        ClosedRowView(group: group)
    }
}
