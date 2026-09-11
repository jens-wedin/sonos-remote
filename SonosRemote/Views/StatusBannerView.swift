import SwiftUI
import SonosKit

struct StatusBannerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.snapshot.status {
        case .ready:
            EmptyView()
        case .discovering:
            Banner(color: .gray) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Sonos…").font(.callout).foregroundStyle(.secondary)
                }
            }
        case .noPlayersFound:
            // combine: false — this banner has a real interactive control (Retry); combining
            // would demote it from a focusable button to, at best, an activate action on the
            // merged text.
            Banner(color: .gray, combine: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No Sonos found on this network").font(.callout.weight(.semibold))
                    Text("Your Mac must be on the same Wi‑Fi or wired network as the speakers.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { state.retryDiscovery() }.controlSize(.small)
                }
            }
        case .unauthorized:
            Banner(color: .yellow) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Authentication is switched on in the Sonos app").font(.callout.weight(.semibold))
                    Text("Turn it off under Settings → System → Network → Connection security so this app can control your speakers.").font(.caption)
                }
            }
        case .localNetworkDenied:
            Banner(color: .yellow) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Local Network access is off").font(.callout.weight(.semibold))
                    Text("Allow Remote for Sonos under System Settings → Privacy & Security → Local Network, then quit and reopen the app.").font(.caption)
                }
            }
        }
    }
}

/// The status card: a coloured dot, the content, the shared rounded background.
private struct Banner<Content: View>: View {
    let color: Color
    /// False when the content has its own interactive control (e.g. a Retry button): combining
    /// would merge it into one non-interactive element and demote it below a focusable button.
    var combine = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5).accessibilityHidden(true)
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: combine ? .combine : .contain)
    }
}
