import SwiftUI

/// One-line inline error under the control that failed; AppState clears it after a few seconds.
struct ErrorLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.errorText)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
