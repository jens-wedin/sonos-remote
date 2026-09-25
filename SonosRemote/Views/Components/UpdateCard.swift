import SwiftUI

/// "Update available" notice at the top of the main screen: version, then "Update via Homebrew · What's new",
/// and a dismiss button. "Update via Homebrew" copies the upgrade command for Terminal.
struct UpdateCard: View {
    let release: ReleaseInfo
    let onCopy: () -> Void
    let onDismiss: () -> Void

    @Environment(AppState.self) private var state
    @Environment(UpdateChecker.self) private var updates

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Update available — v\(release.version)")
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 6) {
                        CopyCommandButton(title: "Update via Homebrew", showsIcon: false, onCopy: onCopy)
                            .foregroundStyle(Color.link)
                            .help("Copies the Homebrew upgrade command; paste it in Terminal")
                        Text(verbatim: "·")
                            .foregroundStyle(Color.supporting)
                            .accessibilityHidden(true)
                        Link("What's new", destination: release.notesURL)
                            .foregroundStyle(Color.link)
                            .focusable()
                            .accessibilityLabel(Text(verbatim: "Show what's new in v\(release.version)"))
                    }
                    .font(.caption.weight(.medium))
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.supporting)
                .focusable()
                .accessibilityLabel("Dismiss update notice")
            }
            .padding(12)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .onAppear(perform: announceOnce)
        .onChange(of: release.version) { announceOnce() }
    }

    private func announceOnce() {
        guard updates.shouldAnnounce(release.version) else { return }
        state.announce("Update available, version \(release.version)")
    }
}

/// Copies the Homebrew command, reads "Copied" for two seconds after a click and announces it.
/// Shared by the update card ("Update via Homebrew") and the Settings version row ("Copy Homebrew command").
struct CopyCommandButton: View {
    var title = "Copy Homebrew command"
    var showsIcon = true
    let onCopy: () -> Void

    @Environment(AppState.self) private var state
    @State private var copied = false
    @State private var clicks = 0

    var body: some View {
        Button {
            onCopy()
            clicks += 1
            state.announce("Copied")
        } label: {
            // The hidden long label reserves the width so the row does not shift while "Copied" shows.
            ZStack(alignment: .leading) {
                label(title, icon: "doc.on.doc").hidden()
                label(copied ? "Copied" : title, icon: copied ? "checkmark" : "doc.on.doc")
            }
        }
        .buttonStyle(.plain)
        .focusable()
        .accessibilityLabel("Copy Homebrew upgrade command")
        .task(id: clicks) {
            guard clicks > 0 else { return }
            copied = true
            do {
                try await Task.sleep(for: .seconds(2))
                copied = false
            } catch {
                // A newer click restarted the window; leave `copied` to that task.
            }
        }
        .onDisappear {
            clicks = 0
            copied = false
        }
    }

    @ViewBuilder private func label(_ text: String, icon: String) -> some View {
        if showsIcon {
            Label(text, systemImage: icon).font(.caption.weight(.semibold))
        } else {
            Text(verbatim: text)
        }
    }
}
