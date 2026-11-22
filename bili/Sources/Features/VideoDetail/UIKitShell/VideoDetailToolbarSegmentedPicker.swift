import SwiftUI

struct VideoDetailToolbarSegmentedPickerView: View {
    static let toolbarWidth: CGFloat = 180
    @Binding var selection: VideoDetailContentTab

    var body: some View {
        Picker("内容", selection: $selection) {
            Text("简介").tag(VideoDetailContentTab.detail)
            Text("评论").tag(VideoDetailContentTab.comments)
        }
        .pickerStyle(.segmented)
        .frame(width: Self.toolbarWidth)
        .accessibilityIdentifier("video.detail.toolbar-picker")
    }
}

struct VideoDetailVerticalToolbarTabButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tab: VideoDetailContentTab
    let isSelected: Bool
    let action: () -> Void

    private var symbolName: String {
        switch tab {
        case .detail:
            return "info.circle"
        case .comments:
            return "text.bubble"
        }
    }

    private var symbolFontSize: CGFloat {
        switch tab {
        case .detail:
            return 18
        case .comments:
            return 16
        }
    }

    private var accessibilityID: String {
        switch tab {
        case .detail:
            return "video.detail.toolbar-picker.detail"
        case .comments:
            return "video.detail.toolbar-picker.comments"
        }
    }

    var body: some View {
        Button {
            if reduceMotion {
                action()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    action()
                }
            }
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: symbolFontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.72))
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(isSelected ? 0.11 : 0))
                }
        }
        .tint(.primary)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Phone-style floating Liquid Glass bottom toolbar scoped to the right-hand
/// detail/comments column in landscape `.twoColumnSplit` (iPad / iPhone Duo).
struct VideoDetailSplitColumnBottomToolbar: View {
    let navigationHistory: NavigationHistoryContext?
    let onNavigateBack: () -> Void
    @Binding var selection: VideoDetailContentTab
    let onOpenCommentComposer: (() -> Void)?

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if let navigationHistory {
                    VideoDetailHistoryBackMenu(history: navigationHistory)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Button(action: onNavigateBack) {
                        Image(systemName: "chevron.backward")
                            .frame(width: 44, height: 44)
                    }
                    .tint(.primary)
                    .accessibilityLabel("返回")
                    .accessibilityIdentifier("video.detail.history-back")
                    .glassEffect(.regular.interactive(), in: .circle)
                }

                Spacer(minLength: 8)

                VideoDetailToolbarSegmentedPickerView(selection: $selection)
                    .frame(width: VideoDetailToolbarSegmentedPickerView.toolbarWidth)
                    .glassEffect(.regular.interactive(), in: .capsule)

                Spacer(minLength: 8)

                if let onOpenCommentComposer {
                    VideoDetailToolbarCommentAction(onComment: onOpenCommentComposer)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }
}

private struct VideoDetailToolbarSegmentedPickerPreview: View {
    @State private var selection: VideoDetailContentTab = .detail

    var body: some View {
        VideoDetailToolbarSegmentedPickerView(selection: $selection)
            .frame(width: VideoDetailToolbarSegmentedPickerView.toolbarWidth)
    }
}

#Preview("视频详情底部切换器") {
    VideoDetailToolbarSegmentedPickerPreview()
}
