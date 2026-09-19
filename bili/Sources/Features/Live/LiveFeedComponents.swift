import SwiftUI

struct LiveFeedSkeletonList: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        SkeletonLoadingContainer {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(0..<6, id: \.self) { _ in
                    LiveRoomSkeletonCard()
                }
            }
        }
        .padding(.bottom, 22)
        .allowsHitTesting(false)
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
