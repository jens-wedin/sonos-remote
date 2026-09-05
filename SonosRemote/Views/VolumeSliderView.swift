import SwiftUI
import SonosKit

/// A labelled 0–100 slider with a mute button. Sends through VolumeCommandGate so dragging
/// does not flood the speaker and incoming events do not fight the thumb.
struct VolumeSliderView: View {
    let label: String
    let volume: Volume
    let accessibilityName: String
    var indent = false
    let onChange: (Int) -> Void
    let onMute: (Bool) -> Void

    @State private var local: Double = 0
    @State private var gate = VolumeCommandGate()
    @State private var flushTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: indent ? 66 : 78, alignment: .leading)
                .padding(.leading, indent ? 12 : 0)
            Slider(value: $local, in: 0...100, step: 1) { editing in
                if !editing { commit(Int(local)) }
            }
            .disabled(volume.fixed)
            .accessibilityLabel("\(accessibilityName) volume")
            .accessibilityValue("\(Int(local)) percent\(volume.muted ? ", muted" : "")")
            .onChange(of: local) { _, newValue in
                if let send = gate.userChanged(to: Int(newValue), at: .now) { onChange(send) } else { scheduleFlush() }
            }
            Text("\(Int(local))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .accessibilityHidden(true)
            Button { onMute(!volume.muted) } label: {
                Image(systemName: volume.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(volume.muted ? "Unmute \(accessibilityName)" : "Mute \(accessibilityName)")
        }
        .onAppear { local = Double(volume.level) }
        .onChange(of: volume.level) { _, incoming in
            if gate.shouldAcceptIncoming(at: .now) { local = Double(incoming) }
        }
    }

    /// Drag ended: send any queued value now if the interval has passed, otherwise the scheduled flush will.
    private func commit(_ value: Int) {
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
