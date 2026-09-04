import SwiftUI

struct MineInterfaceSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            MineDisplaySettingsSection(libraryStore: libraryStore)

            Section("实验功能") {
                Toggle(isOn: Binding(
                    get: { libraryStore.nativeTypographyRefinementExperimentEnabled },
                    set: { libraryStore.setNativeTypographyRefinementExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("原生排版精修", systemImage: "textformat")

                        Text("减少过度加粗和固定字号，使用更接近 iOS 的文字层级、颜色和动态布局。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("native-typography-refinement-experiment-toggle")

                Toggle(isOn: Binding(
                    get: { libraryStore.dynamicDetailBottomInteractionBarExperimentEnabled },
                    set: { libraryStore.setDynamicDetailBottomInteractionBarExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("动态详情底部互动栏", systemImage: "bubble.left.and.bubble.right")

                        Text("在动态详情页底部固定显示点赞、评论和收藏操作，并支持直接展开评论输入框。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("dynamic-detail-bottom-interaction-bar-experiment-toggle")
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}

struct MineHomeAndSearchSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            MineHomeSettingsSection(libraryStore: libraryStore)
            MineSearchSettingsSection(libraryStore: libraryStore)
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}
