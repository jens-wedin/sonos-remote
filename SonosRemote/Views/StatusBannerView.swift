import SwiftUI
import SonosKit

struct StatusBannerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.snapshot.status {
        case .ready:
            EmptyView()
        case .discovering:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for Sonos…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        case .noPlayersFound:
            VStack(alignment: .leading, spacing: 6) {
                Text("No Sonos found on this network").font(.callout.weight(.semibold))
                Text("Your Mac must be on the same Wi‑Fi or wired network as the speakers.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry") { state.retryDiscovery() }.controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        case .unauthorized:
            Banner(
                title: "Authentication is switched on in the Sonos app",
                detail: "Turn it off under Settings → System → Network → Connection security so this app can control your speakers.",
                color: .yellow
            )
        case .localNetworkDenied:
            Banner(
                title: "Local Network access is off",
                detail: "Allow Sonos Remote under System Settings → Privacy & Security → Local Network, then quit and reopen the app.",
                color: .yellow
            )
        }
    }
}

private struct Banner: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.callout.weight(.semibold))
            Text(detail).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
