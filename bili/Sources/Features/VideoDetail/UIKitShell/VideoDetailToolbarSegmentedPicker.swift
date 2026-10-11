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
