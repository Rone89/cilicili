import SwiftUI

struct PlayerStartupLoadingChrome: View {
    let isBuffering: Bool

    var body: some View {
        VStack(spacing: 7) {
            ProgressView()
            if isBuffering {
                Text("缓冲中")
                    .font(.caption2.weight(.medium))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.5))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}
