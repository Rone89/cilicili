import SwiftUI

extension RootTabView {
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                selectedTab = isAvailableRootTab(tab) ? tab : fallbackRootTab(for: tab)
            }
        )
    }

    var visibleRootTabs: [AppTab] {
        runtimeSettings.visibleRootTabs
    }

    func repairSelectedTabIfNeeded(visibleTabs: [AppTab]) {
        guard !visibleTabs.contains(selectedTab) else { return }
        guard selectedTab != .search else { return }
        selectedTab = fallbackRootTab(for: selectedTab, visibleTabs: visibleTabs)
    }

    func isAvailableRootTab(_ tab: AppTab) -> Bool {
        tab == .search || visibleRootTabs.contains(tab)
    }

    func fallbackRootTab(for tab: AppTab, visibleTabs: [AppTab]? = nil) -> AppTab {
        let tabs = visibleTabs ?? visibleRootTabs
        if tab == .search { return .search }
        if tabs.contains(.home) { return .home }
        if tabs.contains(.mine) { return .mine }
        return tabs.first ?? .home
    }
}
