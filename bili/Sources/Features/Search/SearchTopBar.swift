import SwiftUI

struct SearchTopBar: ToolbarContent {
    let titleState: FeedChromeTitleState
    let isRootTabContent: Bool
    @Binding var isSearching: Bool
    let containerWidth: CGFloat
    let viewModel: SearchViewModel?
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            SearchMorphTopBar(
                titleState: titleState,
                isSearching: $isSearching,
                containerWidth: containerWidth,
                viewModel: viewModel,
                searchText: $searchText,
                isSearchFocused: isSearchFocused,
                onSubmit: onSubmit,
                isRootTabContent: isRootTabContent
            )
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

struct SearchMorphTopBar: View {
    @ObservedObject var titleState: FeedChromeTitleState
    @Binding var isSearching: Bool
    let containerWidth: CGFloat
    let viewModel: SearchViewModel?
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    var isRootTabContent: Bool = true

    private let controlHeight: CGFloat = 44

    var body: some View {
        RootMorphSearchTopBar(
            titleState: titleState,
            configuration: RootMorphSearchTopBarConfiguration(
                title: AppTab.search.title,
                titleAccessibilityID: "search.feed.title",
                searchPrompt: viewModel?.searchPrompt ?? "搜索",
                searchButtonAccessibilityLabel: "搜索",
                searchButtonAccessibilityID: "search.top.button",
                fieldAccessibilityID: "search.top.field",
                clearAccessibilityID: "search.top.clear",
                cancelAccessibilityID: "search.top.cancel",
                trailingExpandedGlassID: "searchFilterControl",
                containerWidth: containerWidth,
                dismissesFocusOnNonEmptySubmit: false
            ),
            isSearching: $isSearching,
            searchText: $searchText,
            isSearchFocused: isSearchFocused,
            isRootTabContent: isRootTabContent,
            onSubmit: onSubmit,
            compactAccessory: {
                if let viewModel {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 0.5, height: controlHeight - 18)
                    SearchFilterToolbarMenu(viewModel: viewModel, iconPointSize: 18)
                        .frame(width: controlHeight, height: controlHeight)
                }
            },
            expandedTrailingAccessory: { closeButton in
                if let viewModel {
                    SearchFilterToolbarMenu(
                        viewModel: viewModel,
                        iconPointSize: 18,
                        controlSize: controlHeight
                    )
                } else {
                    closeButton
                }
            }
        )
    }
}
