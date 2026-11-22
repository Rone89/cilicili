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
                    VideoDetailHistoryBackMenu(
                        history: navigationHistory,
                        onBack: onNavigateBack,
                        circularControlSize: 44
                    )
                    .glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Button(action: onNavigateBack) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .tint(.primary)
                    .accessibilityLabel("返回")
                    .accessibilityIdentifier("video.detail.history-back")
                    .glassEffect(.regular.interactive(), in: .circle)
                }

                Spacer(minLength: 8)

                VideoDetailSplitColumnSegmentedControl(selection: $selection)

                Spacer(minLength: 8)

                if let onOpenCommentComposer {
                    Button(action: onOpenCommentComposer) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .tint(.primary)
                    .accessibilityLabel("发表评论")
                    .accessibilityIdentifier("video.detail.toolbar-comment")
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

private struct VideoDetailSplitColumnSegmentedControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @Binding var selection: VideoDetailContentTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(VideoDetailContentTab.allCases) { tab in
                let isSelected = selection == tab
                let segmentTitle = tab == .detail ? "简介" : "评论"
                Button {
                    guard selection != tab else { return }
                    if reduceMotion {
                        selection = tab
                    } else {
                        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                            selection = tab
                        }
                    }
                } label: {
                    Text(segmentTitle)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.75))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.11))
                                    .matchedGeometryEffect(id: "video.detail.split.segment.thumb", in: selectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segmentTitle)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(width: VideoDetailToolbarSegmentedPickerView.toolbarWidth, height: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video.detail.toolbar-picker")
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
