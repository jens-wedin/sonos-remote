import SwiftUI
import SonosKit
import ServiceManagement
import KeyboardShortcuts

struct SettingsScreen: View {
    @Environment(AppState.self) private var state
    @Environment(UpdateController.self) private var updates
    @State private var launchAtLogin = false
    @State private var loginError: String?

    private static let releasesURL = URL(string: "https://github.com/jens-wedin/sonos-remote/releases")!

    var body: some View {
        @Bindable var updates = updates
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("CONNECTION")
            Card {
                CardRow(isFirst: true) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusText).font(.callout.weight(.medium))
                        Text(detailText).font(.caption).foregroundStyle(Color.supporting)
                    }
                    Spacer()
                    Button { state.retryDiscovery() } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .focusable()
                    .accessibilityLabel("Refresh connection")
                }
            }

            SectionLabel("GENERAL")
            Card {
                CardRow(isFirst: true) {
                    Text("Launch at login").font(.callout).accessibilityHidden(true)
                    Spacer()
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                if let loginError {
                    CardRow { Text(loginError).font(.caption).foregroundStyle(.red) }
                }
                CardRow {
                    Text("Global shortcut").font(.callout)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePanel)
                        .accessibilityLabel("Global shortcut")
                }
                CardRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for updates").font(.callout).accessibilityHidden(true)
                        Text("Asks github.com once a day").font(.caption).foregroundStyle(Color.supporting).accessibilityHidden(true)
                    }
                    Spacer()
                    Toggle("Check for updates", isOn: $updates.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .accessibilityHint("Asks github.com once a day")
                }
            }

            SectionLabel("SYSTEM")
            Card {
                CardRow(isFirst: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version").font(.callout)
                        if let version = updates.latestKnown {
                            Text(verbatim: "Update available: \(version)")
                                .font(.caption).foregroundStyle(Color.supporting)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(AppVersion.display).font(.callout.monospacedDigit()).foregroundStyle(Color.supporting)
                        if updates.canInstall {
                            let updateVersion = updates.state.version ?? updates.latestKnown
                            Button("Update now") { updates.install() }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.link)
                                .focusable()
                                .accessibilityLabel(
                                    updateVersion.map { Text(verbatim: "Update now to version \($0)") } ?? Text("Update now")
                                )
                        } else {
                            manualCheckRow
                        }
                    }
                }
                CardRow {
                    Link(destination: Self.releasesURL) {
                        HStack {
                            Text("Releases").font(.callout)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Color.supporting)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .focusable()
                    .accessibilityLabel("Releases on GitHub")
                }
                CardRow {
                    Button {
                        if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text("Acknowledgements").font(.callout)
                            Spacer()
                            Image(systemName: "doc.text").font(.caption).foregroundStyle(Color.supporting)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .focusable()
                    .accessibilityLabel("Open acknowledgements")
                }
            }
        }
        .padding(.bottom, 12)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .onChange(of: launchAtLogin) { _, on in
            guard on != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    /// Under the version number when there's nothing to install: lets the user re-check a version they
    /// skipped, since Sparkle otherwise never offers a skipped version again until its own next check.
    /// Shows nothing once `.none` if `checkNow()` itself couldn't run right now (state isn't idle, or no
    /// updater is attached) — there's neither something to install, a check to offer, nor a result to show.
    @ViewBuilder private var manualCheckRow: some View {
        switch updates.manualCheck {
        case .none:
            if updates.canCheckNow {
                Button("Check now") { updates.checkNow() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.link)
                    .focusable()
            }
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(verbatim: "Checking…")
            }
            .font(.caption)
            .foregroundStyle(Color.supporting)
            .accessibilityElement(children: .combine)
        case .upToDate:
            Text(verbatim: "Up to date").font(.caption).foregroundStyle(Color.supporting)
        case .failed:
            Text(verbatim: "Couldn't check").font(.caption).foregroundStyle(Color.errorText)
        }
    }

    private var isConnected: Bool {
        if case .ready = state.status { return true }
        return false
    }

    private var statusText: String {
        switch state.status {
        case .ready: "Connected"
        case .discovering: "Looking for Sonos…"
        case .noPlayersFound: "No Sonos found"
        case .unauthorized: "Not authorized"
        case .localNetworkDenied: "Local network access is off"
        }
    }

    /// "3 speakers · S2 · 85.1-63270"
    private var detailText: String {
        let count = state.players.count
        let speakers = count == 1 ? "1 speaker" : "\(count) speakers"
        return [speakers, "S2", state.softwareVersion].compactMap { $0 }.joined(separator: " · ")
    }
}
