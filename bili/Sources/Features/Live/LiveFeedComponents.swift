import SwiftUI

struct LiveFeedSkeletonList: View {
    var horizontalPadding: CGFloat = 16
    var topPadding: CGFloat = 10

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                LiveRoomSkeletonCard()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 22)
    }
}

struct LiveFeedFooter: View {
    let text: String
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}
