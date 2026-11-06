import SwiftUI

/// 分P选择器：紧凑单行入口（区块名 + 当前项 + 总数），点按打开单列选择弹窗。
struct VideoDetailPageMenu: View {
    @ObservedObject var store: VideoDetailPageSelectorRenderStore
    let selectPage: (VideoPage) -> Void

    @State private var isPageSheetPresented = false

    private var compactItems: [VideoDetailCompactSelectionItem] {
        store.pages.map { page in
            VideoDetailCompactSelectionItem(
                page: page,
                isSelected: page.cid == store.selectedCID,
                fallbackCoverURL: store.coverDisplay?.sourceCoverURL?.absoluteString
            )
        }
    }

    var body: some View {
        if store.shouldShowPageSelector {
            VideoDetailCompactEntryButton(
                sectionTitle: "分P",
                countUnit: "P",
                items: compactItems,
                accessibilityIdentifier: "video.detail.pageMenu.compact",
                showsSheet: $isPageSheetPresented
            )
            .sheet(isPresented: $isPageSheetPresented) {
                VideoDetailCompactSelectionSheet(
                    sectionTitle: "全部分P",
                    items: compactItems,
                    selectItem: { item in
                        // UGC 条目的 id 即 cid。
                        guard let page = store.pages.first(where: { $0.cid == item.id }) else { return }
                        selectPage(page)
                    }
                )
            }
        }
    }
}
