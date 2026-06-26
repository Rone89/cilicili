import SwiftUI

struct MineRootTabSettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section {
            ForEach(AppTab.defaultVisibleTabs.filter(\.participatesInRootTabVisibilitySettings)) { tab in
                Toggle(isOn: Binding(
                    get: { libraryStore.visibleRootTabs.contains(tab) },
                    set: { libraryStore.setRootTab(tab, isVisible: $0) }
                )) {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .disabled(!tab.canHideFromRootTabBar)
            }

            Button {
                libraryStore.resetVisibleRootTabs()
            } label: {
                Label("恢复默认 Tab", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("底部 Tab")
        } footer: {
            Text("首页和我的固定显示，搜索使用系统独立搜索按钮。")
        }
    }
}
