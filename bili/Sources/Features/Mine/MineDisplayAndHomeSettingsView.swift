import SwiftUI

struct MineInterfaceSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            MineDisplaySettingsSection(libraryStore: libraryStore)

            Section("实验功能") {
                Toggle(isOn: Binding(
                    get: { libraryStore.dynamicCommentExpandedReplyTapExperimentEnabled },
                    set: { libraryStore.setDynamicCommentExpandedReplyTapExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("点击评论区域回复", systemImage: "hand.tap")

                        Text("点击评论内容和信息区域，快速打开该评论的回复输入框。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("dynamic-comment-expanded-reply-tap-experiment-toggle")

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
