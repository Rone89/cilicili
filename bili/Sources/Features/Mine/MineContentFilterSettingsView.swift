import SwiftUI

struct MineContentFilterSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { libraryStore.blocksAdDynamics },
                    set: { libraryStore.setBlocksAdDynamics($0) }
                )) {
                    Label("屏蔽广告动态", systemImage: "megaphone.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsDynamics },
                    set: { libraryStore.setBlocksGoodsDynamics($0) }
                )) {
                    Label("屏蔽带货动态", systemImage: "bag.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsComments },
                    set: { libraryStore.setBlocksGoodsComments($0) }
                )) {
                    Label("屏蔽带货评论", systemImage: "text.bubble.badge.minus")
                }

                NavigationLink {
                    DynamicKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    HStack {
                        Label("自定义动态关键词", systemImage: "line.3.horizontal.decrease.circle")
                        Spacer()
                        Text("\(libraryStore.blockedDynamicKeywords.count) 个")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("广告动态会按常见推广关键词过滤；带货动态会按 B 站商品组件和商品元数据过滤；自定义关键词会匹配动态正文、标题和转发内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}
