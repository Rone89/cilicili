import SwiftUI

extension RootTabView {
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                guard tab != selectedTab else {
                    guard activeRootNavigationPathIsEmpty else { return }
                    if tab == .home {
                        homeActionStore.scroll.requestScrollToTop()
                    } else {
                        rootTabScrollRequests[tab] = RootTabScrollRequest()
                    }
                    return
                }
                selectAvailableRootTab(tab)
            }
        )
    }

    func selectAvailableRootTab(_ tab: AppTab) {
        selectedTab = isAvailableRootTab(tab) ? tab : fallbackRootTab(for: tab)
    }

    var visibleRootTabs: [AppTab] {
        runtimeSettings.visibleRootTabs
    }

    // The mounted tabs remain unchanged during pushed settings edits, including
    // transitions between a standalone home stack and a multi-tab container.
    var displayedRootTabs: [AppTab] {
        if let hostedRootTabs { return hostedRootTabs }
        guard !visibleRootTabs.contains(selectedTab), !activeRootNavigationPathIsEmpty else {
            return visibleRootTabs
        }
        return AppTab.normalizedVisibleTabs(visibleRootTabs + [selectedTab])
    }

    func repairSelectedTabIfNeeded(visibleTabs: [AppTab]) {
        guard !visibleTabs.contains(selectedTab) else { return }
        guard activeRootNavigationPathIsEmpty else { return }
        selectedTab = fallbackRootTab(for: selectedTab, visibleTabs: visibleTabs)
    }

    func isAvailableRootTab(_ tab: AppTab) -> Bool {
        visibleRootTabs.contains(tab)
    }

    func fallbackRootTab(for tab: AppTab, visibleTabs: [AppTab]? = nil) -> AppTab {
        let tabs = visibleTabs ?? visibleRootTabs
        if tabs.contains(.home) { return .home }
        if tabs.contains(.mine) { return .mine }
        return tabs.first ?? .home
    }
}
