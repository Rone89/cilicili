import SwiftUI

struct HomeFeedDoubleColumnLoadingMorePlaceholder: View {
    let columnCount: Int

    var body: some View {
        ForEach(0..<2, id: \.self) { _ in
            VideoFeedSkeletonCard(style: .grid)
                .allowsHitTesting(false)
        }

        Color.clear
            .frame(height: 1)
            .gridCellColumns(columnCount)
    }
}
