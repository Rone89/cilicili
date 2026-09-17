import SwiftUI

struct MineSearchResultsSection: View {
    let query: String
    let onOpenRoute: (MineOverlayRoute) -> Void

    private var results: [MineSearchItem] {
        MineSearchCatalog.search(query)
    }

    var body: some View {
        if results.isEmpty {
            Section {
                ContentUnavailableView(
                    "没有找到相关功能",
                    systemImage: "magnifyingglass",
                    description: Text("试试搜索“播放”“缓存”或“账号管理”。")
                )
            }
        } else {
            ForEach(MineSearchSection.allCases) { section in
                let sectionResults = results.filter { $0.section == section }
                if !sectionResults.isEmpty {
                    Section(section.title) {
                        ForEach(sectionResults) { item in
                            Button {
                                onOpenRoute(item.route)
                            } label: {
                                SettingsNavigationRow(
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    systemImage: item.systemImage
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("mine.search.\(item.id)")
                        }
                    }
                }
            }
        }
    }
}
