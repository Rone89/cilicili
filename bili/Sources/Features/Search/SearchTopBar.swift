import SwiftUI

struct SearchTopBar: ToolbarContent {
    @Environment(\.rootHiddenPageSwitcher) private var rootHiddenPageSwitcher
    let titleState: FeedChromeTitleState
    let isRootTabContent: Bool
    let viewModel: SearchViewModel?

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if isRootTabContent {
            ToolbarItem(placement: .topBarLeading) {
                FeedScrolledToolbarTitle(
                    title: AppTab.search.title,
                    accessibilityID: "search.feed.title",
                    state: titleState
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }

        if isRootTabContent, let viewModel {
            ToolbarItem(placement: .topBarTrailing) {
                SearchFilterToolbarMenu(viewModel: viewModel, iconPointSize: 18)
            }
        }

        if isRootTabContent, let rootHiddenPageSwitcher {
            ToolbarItem(placement: .topBarTrailing) {
                RootHiddenPageSwitcherButton(switcher: rootHiddenPageSwitcher)
            }
        }
    }
}
