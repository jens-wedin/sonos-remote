import SwiftUI
import SonosKit

/// A labelled 0–100 slider with a mute button. Sends through VolumeCommandGate so dragging
/// does not flood the speaker and incoming events do not fight the thumb.
struct VolumeSliderView: View {
    let label: String
    let volume: Volume
    let accessibilityName: String
    var indent = false
    /// Closed-row layout: no label, no numeric readout, just the slider and mute button.
    var compact = false
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
            if !compact {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: indent ? 66 : 78, alignment: .leading)
                    .padding(.leading, indent ? 12 : 0)
            }
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
            if !compact {
                Text("\(Int(local))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            Button { onMute(!volume.muted) } label: {
                Image(systemName: volume.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(volume.muted ? "Unmute \(accessibilityName)" : "Mute \(accessibilityName)")
        }
        .onAppear { setLocalProgrammatically(Double(volume.level)) }
        .onChange(of: volume.level) { _, incoming in
            if !isUserEditing, gate.shouldAcceptIncoming(at: .now) { setLocalProgrammatically(Double(incoming)) }
        }
        .onDisappear { flushTask?.cancel() }
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
