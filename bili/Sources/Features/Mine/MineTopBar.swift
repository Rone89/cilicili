import SwiftUI

struct MineTopBar: ToolbarContent {
    let titleState: FeedChromeTitleState
    let isRootTabContent: Bool
    @Binding var isSearching: Bool
    let containerWidth: CGFloat
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            MineMorphTopBar(
                titleState: titleState,
                isSearching: $isSearching,
                containerWidth: containerWidth,
                searchText: $searchText,
                isSearchFocused: isSearchFocused,
                isRootTabContent: isRootTabContent
            )
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

struct MineMorphTopBar: View {
    @ObservedObject var titleState: FeedChromeTitleState
    @Binding var isSearching: Bool
    let containerWidth: CGFloat
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    var isRootTabContent: Bool = true

    var body: some View {
        RootMorphSearchTopBar(
            titleState: titleState,
            configuration: RootMorphSearchTopBarConfiguration(
                title: AppTab.mine.title,
                titleAccessibilityID: "mine.feed.title",
                searchPrompt: "搜索我的页功能",
                searchButtonAccessibilityLabel: "搜索我的页功能",
                searchButtonAccessibilityID: "mine.search.button",
                fieldAccessibilityID: "mine.search.field",
                clearAccessibilityID: "mine.search.clear",
                cancelAccessibilityID: "mine.search.cancel",
                trailingExpandedGlassID: "mineSearchCancelControl",
                containerWidth: containerWidth,
                dismissesFocusOnNonEmptySubmit: true
            ),
            isSearching: $isSearching,
            searchText: $searchText,
            isSearchFocused: isSearchFocused,
            isRootTabContent: isRootTabContent,
            onSubmit: {},
            compactAccessory: { EmptyView() },
            expandedTrailingAccessory: { closeButton in closeButton }
        )
    }
}
