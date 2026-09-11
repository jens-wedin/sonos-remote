import SwiftUI
import SonosKit

/// A 0–100 slider with a mute button. Sends through VolumeCommandGate so dragging
/// does not flood the speaker and incoming events do not fight the thumb.
struct VolumeSliderView: View {
    enum Style {
        /// Rooms list: slider and mute only.
        case compact
        /// Main screen volume row: mute glyph on the left, slider, readout.
        case hero
    }

    let volume: Volume
    let accessibilityName: String
    var style: Style
    let onChange: (Int) -> Void
    let onMute: (Bool) -> Void

    @State private var local: Double = 0
    @State private var gate = VolumeCommandGate()
    @State private var flushTask: Task<Void, Never>?
    /// True while the user is actively dragging the slider (set by `onEditingChanged`).
    @State private var isUserEditing = false
    /// True while `local` is being written by us (onAppear / an accepted incoming update), so the
    /// resulting `onChange(of: local)` is not mistaken for a user edit and echoed back out.
    @State private var isProgrammaticUpdate = false

    var body: some View {
        HStack(spacing: 8) {
            if style == .hero { muteButton(glyph: "speaker.wave.1", size: 15) }
            Slider(value: $local, in: 0...100, step: 1) { editing in
                isUserEditing = editing
                if !editing { commit() }
            }
            .disabled(volume.fixed)
            .accessibilityLabel("\(accessibilityName) volume")
            .accessibilityValue("\(Int(local)) percent\(volume.muted ? ", muted" : "")")
            .onChange(of: local) { _, newValue in
                // Only a genuine user edit (drag or, since keyboard arrow changes never call
                // onEditingChanged, a focused-slider arrow press) reaches here with the flag
                // clear; a write we made ourselves (onAppear, accepted incoming volume) always
                // sets the flag first, so this early return is what stops incoming updates from
                // being echoed straight back out as outgoing commands.
                guard !isProgrammaticUpdate else { return }
                if let send = gate.userChanged(to: Int(newValue), at: .now) { onChange(send) } else { scheduleFlush() }
            }
            if style != .compact {
                Text("\(Int(local))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            if style != .hero { muteButton(glyph: "speaker.wave.2.fill", size: 12) }
        }
        .onAppear { setLocalProgrammatically(Double(volume.level)) }
        .onChange(of: volume.level) { _, incoming in
            if !isUserEditing, gate.shouldAcceptIncoming(at: .now) { setLocalProgrammatically(Double(incoming)) }
        }
        .onDisappear { flushTask?.cancel() }
    }

    private func muteButton(glyph: String, size: CGFloat) -> some View {
        Button { onMute(!volume.muted) } label: {
            Image(systemName: volume.muted ? "speaker.slash.fill" : glyph)
                .font(.system(size: size))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable()
        .accessibilityLabel(volume.muted ? "Unmute \(accessibilityName)" : "Mute \(accessibilityName)")
    }

    /// Writes `local` on our own behalf (not a user edit) with the guard flag held across the
    /// write and released on the next run-loop turn, so the `onChange(of: local)` this triggers
    /// still sees the flag set and skips sending.
    private func setLocalProgrammatically(_ value: Double) {
        isProgrammaticUpdate = true
        local = value
        Task { @MainActor in isProgrammaticUpdate = false }
    }

    /// Drag ended: send any queued value now if the interval has passed, otherwise the scheduled flush will.
    private func commit() {
        if let send = gate.flush(at: .now) {
            flushTask?.cancel()
            onChange(send)
        }
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            if let send = gate.flush(at: .now) { onChange(send) }
        }
    }
}
