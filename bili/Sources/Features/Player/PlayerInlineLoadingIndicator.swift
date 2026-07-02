import SwiftUI

struct PlayerInlineLoadingIndicator: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 30)
        .biliPlayerClearGlass(interactive: false, in: Capsule())
        .allowsHitTesting(false)
    }
}
