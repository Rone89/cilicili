import SwiftUI

extension EnvironmentValues {
    @Entry var showsHiddenRootPageSwitcher = false
}

extension RootTabView {
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { isShowingHiddenRootPage ? .home : selectedTab },
            set: { tab in
                guard tab != selectedTab else {
                    guard activeRootNavigationPathIsEmpty else { return }
                    rootTabScrollRequests[tab] = RootTabScrollRequest()
                    return
                }
                selectAvailableRootTab(tab)
            }
        )
    }

    func selectAvailableRootTab(_ tab: AppTab) {
        openedHiddenRootPage = false
        selectedTab = isAvailableRootTab(tab) ? tab : fallbackRootTab(for: tab)
    }

    func selectRootPageFromMenu(_ tab: AppTab) {
        guard tab == .home || tab.canHideFromRootTabBar else { return }
        openedHiddenRootPage = !visibleRootTabs.contains(tab)
        selectedTab = tab
    }

    var isShowingHiddenRootPage: Bool {
        openedHiddenRootPage && !displayedRootTabs.contains(selectedTab)
    }

    var hiddenRootPages: [AppTab] {
        AppTab.defaultVisibleTabs.filter { $0.canHideFromRootTabBar && !visibleRootTabs.contains($0) }
    }

    var visibleRootTabs: [AppTab] {
        runtimeSettings.visibleRootTabs
    }

    // The mounted tabs remain unchanged during pushed settings edits, including
    // transitions between a standalone home stack and a multi-tab container.
    var displayedRootTabs: [AppTab] {
        if let hostedRootTabs { return hostedRootTabs }
        guard !openedHiddenRootPage, !visibleRootTabs.contains(selectedTab), !activeRootNavigationPathIsEmpty else {
            return visibleRootTabs
        }
        return AppTab.normalizedVisibleTabs(visibleRootTabs + [selectedTab])
    }

    func repairSelectedTabIfNeeded(visibleTabs: [AppTab]) {
        if visibleTabs.contains(selectedTab) {
            openedHiddenRootPage = false
            return
        }
        guard !openedHiddenRootPage else { return }
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
