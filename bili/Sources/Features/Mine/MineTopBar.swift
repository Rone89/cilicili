import SwiftUI

struct MineTopBar: ToolbarContent {
    @Environment(\.rootHiddenPageSwitcher) private var rootHiddenPageSwitcher
    let titleState: FeedChromeTitleState
    let isRootTabContent: Bool

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if isRootTabContent {
            ToolbarItem(placement: .topBarLeading) {
                FeedScrolledToolbarTitle(
                    title: AppTab.mine.title,
                    accessibilityID: "mine.feed.title",
                    state: titleState
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }

        DefaultToolbarItem(kind: .search, placement: .topBarTrailing)

        if isRootTabContent, let rootHiddenPageSwitcher {
            ToolbarItem(placement: .topBarTrailing) {
                RootHiddenPageSwitcherButton(switcher: rootHiddenPageSwitcher)
            }
        }
    }
}
