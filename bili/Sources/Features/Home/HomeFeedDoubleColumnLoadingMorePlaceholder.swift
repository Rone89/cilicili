import SwiftUI

struct HomeFeedDoubleColumnLoadingMorePlaceholder: View {
    let columnCount: Int

    var body: some View {
        InlineLoadingStateView(title: "正在加载更多")
            .padding(.vertical, 8)
            .gridCellColumns(columnCount)
    }
}
