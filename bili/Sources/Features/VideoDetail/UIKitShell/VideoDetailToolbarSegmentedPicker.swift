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
                .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
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
