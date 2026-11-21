import SwiftUI

struct LiveFeedSkeletonList: View {
    var columnCount: Int = 2

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: max(columnCount, 1))
    }

    var body: some View {
        SkeletonLoadingContainer {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(0..<max(6, columnCount * 3), id: \.self) { _ in
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
