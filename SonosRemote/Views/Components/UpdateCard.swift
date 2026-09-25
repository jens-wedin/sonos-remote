import SwiftUI

/// The update notice at the top of the main screen. Offers an update ("Update now · What's new"),
/// then shows download and install progress in place until Sparkle relaunches the app.
struct UpdateCard: View {
    @Environment(AppState.self) private var appState
    @Environment(UpdateController.self) private var updates

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isFailure ? "exclamationmark.triangle" : "arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.callout.weight(.semibold))
                    detail
                        .font(.caption.weight(.medium))
                }

                Spacer(minLength: 0)

                closeButton
            }
            .padding(12)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .onAppear(perform: announceOffer)
        .onChange(of: updates.state) { announceOffer() }
    }

    private var isFailure: Bool {
        if case .failed = updates.state { true } else { false }
    }

    private var title: String {
        switch updates.state {
        case .available(let version, _): "Update available — v\(version)"
        case .downloading(let version, _), .installing(let version): "Updating to v\(version)"
        case .failed: "Update failed"
        case .idle: ""
        }
    }

    @ViewBuilder private var detail: some View {
        switch updates.state {
        case .available(let version, let notesURL):
            HStack(spacing: 6) {
                Button("Update now") { updates.install() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.link)
                    .focusable()
                    .accessibilityLabel(Text(verbatim: "Update now to version \(version)"))
                if let notesURL {
                    separator
                    Link("What's new", destination: notesURL)
                        .foregroundStyle(Color.link)
                        .focusable()
                        .accessibilityLabel(Text(verbatim: "Show what's new in v\(version)"))
                }
            }
        case .downloading(_, let fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: fraction.map { "Downloading… \(Int(($0 * 100).rounded()))%" } ?? "Downloading…")
                    .foregroundStyle(Color.supporting)
                progress(fraction)
            }
        case .installing:
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Installing…")
                    .foregroundStyle(Color.supporting)
                progress(nil)
            }
        case .failed:
            HStack(spacing: 6) {
                Button("Try again") { updates.retry() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.link)
                    .focusable()
                separator
                CopyCommandButton(title: "Update via Homebrew", showsIcon: false, onCopy: { updates.copyCommand() })
                    .foregroundStyle(Color.link)
                    .help("Copies the Homebrew upgrade command; paste it in Terminal")
            }
        case .idle:
            EmptyView()
        }
    }

    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(Color.supporting)
            .accessibilityHidden(true)
    }

    /// Determinate once Sparkle knows the download's length, indeterminate otherwise.
    private func progress(_ fraction: Double?) -> some View {
        SwiftUI.Group {
            if let fraction { ProgressView(value: fraction) } else { ProgressView() }
        }
        .progressViewStyle(.linear)
        .controlSize(.small)
        .accessibilityLabel("Update progress")
    }

    @ViewBuilder private var closeButton: some View {
        switch updates.state {
        case .available: dismissButton("Skip this version") { updates.skip() }
        case .failed: dismissButton("Dismiss update error") { updates.dismissFailure() }
        case .idle, .downloading, .installing: EmptyView()
        }
    }

    private func dismissButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.supporting)
        .focusable()
        .accessibilityLabel(Text(verbatim: label))
    }

    /// "Update available" is announced once per version per session; the steps after a click are announced by the controller.
    private func announceOffer() {
        guard case .available(let version, _) = updates.state, updates.shouldAnnounce(version) else { return }
        appState.announce("Update available, version \(version)")
    }
}

/// Copies the Homebrew command, reads "Copied" for two seconds after a click and announces it.
/// Used by the update card's failure state ("Update via Homebrew").
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
