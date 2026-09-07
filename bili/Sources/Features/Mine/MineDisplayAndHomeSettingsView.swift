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

                Toggle(isOn: Binding(
                    get: { libraryStore.dynamicDetailComposerExperimentEnabled },
                    set: { libraryStore.setDynamicDetailComposerExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("动态详情交互栏实验", systemImage: "text.bubble")

                        Text("使用可展开的底部输入栏发表评论、表情和图片，并统一动态的点赞与收藏操作。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("dynamic-detail-composer-experiment-toggle")

                Toggle(isOn: Binding(
                    get: { libraryStore.richCommentComposerExperimentEnabled },
                    set: { libraryStore.setRichCommentComposerExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("原生评论编辑", systemImage: "text.bubble")

                        Text("使用系统 Toolbar、富文本评论编辑器和键盘区域表情切换。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("rich-comment-composer-experiment-toggle")

                Toggle(isOn: Binding(
                    get: { libraryStore.dynamicDetailTelegramInputStyleExperimentEnabled },
                    set: { libraryStore.setDynamicDetailTelegramInputStyleExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Telegram 输入栏样式", systemImage: "text.bubble")

                        Text("在动态详情页预览附件、输入框和语音按钮的 Telegram 尺寸与位置，不执行互动操作。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("dynamic-detail-telegram-input-style-experiment-toggle")

                Toggle(isOn: Binding(
                    get: { libraryStore.dynamicCommentSwipeReplyExperimentEnabled },
                    set: { libraryStore.setDynamicCommentSwipeReplyExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("左滑回复动态评论", systemImage: "arrow.left.circle")

                        Text("在动态详情评论区左滑评论，快速打开回复入口。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("dynamic-comment-swipe-reply-experiment-toggle")

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

                Toggle(isOn: Binding(
                    get: { libraryStore.keyboardAnchoredCommentEmotePickerExperimentEnabled },
                    set: { libraryStore.setKeyboardAnchoredCommentEmotePickerExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("键盘区域表情选择器", systemImage: "face.smiling")

                        Text("将表情选择器固定在评论输入容器中，替代系统弹出菜单。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("keyboard-anchored-comment-emote-picker-experiment-toggle")

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
