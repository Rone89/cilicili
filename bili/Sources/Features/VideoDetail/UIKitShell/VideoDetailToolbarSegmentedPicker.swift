import SwiftUI

struct VideoDetailToolbarSegmentedPickerView: View {
    static let compactWidth: CGFloat = 144
    private static let height: CGFloat = 38

    @Binding var selection: VideoDetailContentTab

    var body: some View {
        HStack(spacing: 0) {
            segment(title: "简介", tab: .detail)
            segment(title: "评论", tab: .comments)
        }
        .frame(width: Self.compactWidth, height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("内容")
        .accessibilityIdentifier("video.detail.toolbar-picker")
    }

    private func segment(title: String, tab: VideoDetailContentTab) -> some View {
        Button {
            selection = tab
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
                .background {
                    if selection == tab {
                        Capsule()
                            .fill(.primary.opacity(0.12))
                    }
                }
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
            .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
    }
}

#Preview("视频详情底部切换器") {
    VideoDetailToolbarSegmentedPickerPreview()
}
