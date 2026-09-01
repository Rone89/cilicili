import SwiftUI

struct MineSearchSettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("搜索") {
            Toggle(isOn: Binding(
                get: { libraryStore.showsHotSearches },
                set: { libraryStore.setShowsHotSearches($0) }
            )) {
                Label("显示热门搜索", systemImage: "flame")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.searchTabExpansionExperimentEnabled },
                set: { libraryStore.setSearchTabExpansionExperimentEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("系统搜索 Tab 展开实验", systemImage: "magnifyingglass")

                    Text("开启后，底部搜索按钮会使用系统搜索角色，并展开为 Liquid Glass 搜索框。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
