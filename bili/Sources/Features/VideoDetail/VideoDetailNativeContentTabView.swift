import SwiftUI
import UIKit

struct VideoDetailNativeContentTabView<Content: View>: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @EnvironmentObject private var libraryStore: LibraryStore
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let mountsSecondaryContent: Bool
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let content: (VideoDetailContentTab, Bool) -> Content

    var body: some View {
        Group {
            if libraryStore.videoDetailSystemBottomBarExperimentEnabled {
                tabContent
                    .toolbarVisibility(.hidden, for: .tabBar)
            } else {
                tabContent
                    .ignoresSafeArea(.container, edges: .bottom)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VideoDetailTransparentSegmentedPicker(selection: $selection)
                            .frame(width: 144, height: 40)
                            .videoDetailSegmentedPickerGlassEffect(
                                libraryStore.videoDetailSegmentedPickerGlassStyle
                            )
                            .offset(y: 2)
                            .padding(.horizontal, 16)
                            .accessibilityIdentifier("video.detail.glass-panel-picker")
                    }
                    .toolbarVisibility(.hidden, for: .tabBar, .bottomBar)
            }
        }
        .tint(appTintColor)
    }

    private var tabContent: some View {
        ZStack {
            if selection == .detail {
                page(for: .detail)
                    .transition(.move(edge: .leading))
            }

            if selection == .comments {
                page(for: .comments)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.smooth(duration: 0.28), value: selection)
        .background(VideoDetailTheme.background)
    }

    private func page(for tab: VideoDetailContentTab) -> some View {
        VideoDetailNativeContentTabPage(
            tab: tab,
            layoutWidth: layoutWidth,
            topInset: topInset,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            content: { tab in
                content(
                    tab,
                    mountsSecondaryContent || (tab == .comments && selection == .comments)
                )
            }
        )
    }
}

private extension View {
    @ViewBuilder
    func videoDetailSegmentedPickerGlassEffect(
        _ glassStyle: VideoDetailSegmentedPickerGlassStyle
    ) -> some View {
        switch glassStyle {
        case .clear:
            glassEffect(.clear.interactive(), in: .capsule)
        case .regular:
            glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}

private struct VideoDetailTransparentSegmentedPicker: UIViewRepresentable {
    @Binding var selection: VideoDetailContentTab

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> VideoDetailSegmentedControl {
        let control = VideoDetailSegmentedControl(items: ["简介", "评论"])
        control.backgroundColor = .clear
        control.tintColor = .label
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium)
        ]
        control.setTitleTextAttributes(titleAttributes, for: .normal)
        control.setTitleTextAttributes(titleAttributes, for: .selected)
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:)),
            for: .valueChanged
        )
        control.accessibilityIdentifier = "video.detail.glass-panel-picker"
        control.accessibilityLabel = "切换视图"
        update(control)
        return control
    }

    func updateUIView(_ control: VideoDetailSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        update(control)
    }

    private func update(_ control: VideoDetailSegmentedControl) {
        control.selectedSegmentIndex = selection == .detail ? 0 : 1
        control.accessibilityValue = selection.title
    }

    final class Coordinator: NSObject {
        var selection: Binding<VideoDetailContentTab>

        init(selection: Binding<VideoDetailContentTab>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: UISegmentedControl) {
            selection.wrappedValue = sender.selectedSegmentIndex == 0 ? .detail : .comments
        }
    }
}

private final class VideoDetailSegmentedControl: UISegmentedControl {
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.height = 40
        return size
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var fittedSize = super.sizeThatFits(size)
        fittedSize.height = 40
        return fittedSize
    }
}
