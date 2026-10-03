import SwiftUI

struct VideoDetailToolbarSegmentedPickerView: View {
    static let toolbarWidth: CGFloat = 180
    private static let height: CGFloat = 38

    @Binding var selection: VideoDetailContentTab
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 0) {
            segment(title: "简介", tab: .detail)
            segment(title: "评论", tab: .comments)
        }
        .frame(width: Self.toolbarWidth, height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("内容")
        .accessibilityIdentifier("video.detail.toolbar-picker")
        .animation(.smooth(duration: 0.22), value: selection)
    }

    private func segment(title: String, tab: VideoDetailContentTab) -> some View {
        Button {
            guard selection != tab else { return }
            withAnimation(.smooth(duration: 0.22)) {
                selection = tab
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selection == tab ? .primary : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selection == tab {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .padding(.horizontal, 1)
                            .matchedGeometryEffect(
                                id: "video-detail-toolbar-selection",
                                in: selectionNamespace
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selection == tab ? "已选中" : "未选中")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
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
