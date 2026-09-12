import SwiftUI

/// "Update available" notice at the top of the main screen: version, copy-the-brew-command, what's new, dismiss.
struct UpdateCard: View {
    let release: ReleaseInfo
    let onCopy: () -> Void
    let onDismiss: () -> Void

    @Environment(AppState.self) private var state
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var announcedVersion: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "Update available — v\(release.version)")
                    .font(.callout.weight(.semibold))
                HStack(spacing: 14) {
                    CopyCommandButton(onCopy: onCopy)

                    Link(destination: release.notesURL) {
                        Label("What's new", systemImage: "arrow.up.right")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Color.supporting)
                    .focusable()
                    .accessibilityLabel(Text(verbatim: "Show what's new in v\(release.version)"))
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.supporting)
            .focusable()
            .accessibilityLabel("Dismiss update notice")
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border(contrast).opacity(0.6)))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .onAppear(perform: announceOnce)
        .onChange(of: release.version) { announceOnce() }
    }

    private func announceOnce() {
        guard announcedVersion != release.version else { return }
        announcedVersion = release.version
        state.announce("Update available, version \(release.version)")
    }
}

/// "Copy Homebrew command" that reads "Copied" for two seconds after a click and announces it.
/// Shared by the update card and the Settings version row.
struct CopyCommandButton: View {
    let onCopy: () -> Void

    @Environment(AppState.self) private var state
    @State private var copied = false

    var body: some View {
        Button {
            onCopy()
            copied = true
            state.announce("Copied")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy Homebrew command", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .focusable()
        .accessibilityLabel("Copy Homebrew upgrade command")
    }
}
