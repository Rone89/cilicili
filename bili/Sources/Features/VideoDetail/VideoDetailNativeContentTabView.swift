import SwiftUI
import UIKit

struct VideoDetailNativeContentTabView<Content: View>: View {
    private let segmentedPickerHeight: CGFloat = 40
    @Environment(\.appThemeTintColor) private var appTintColor
    @EnvironmentObject private var libraryStore: LibraryStore
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let mountsSecondaryContent: Bool
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    var summary: AnyView? = nil
    let content: (VideoDetailContentTab, Bool) -> Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset).accessibilityHidden(true)
            tabContent
        }
        .toolbarVisibility(.hidden, for: .tabBar, .bottomBar)
        .tint(appTintColor)
    }

    private var tabContent: some View {
        ZStack {
            ForEach(VideoDetailContentTab.allCases) { tab in
                page(for: tab)
                    .opacity(selection == tab ? 1 : 0)
                    .allowsHitTesting(selection == tab)
                    .accessibilityHidden(selection != tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.smooth(duration: 0.28), value: selection)
        .background(VideoDetailTheme.background)
    }

    private func page(for tab: VideoDetailContentTab) -> some View {
        VideoDetailPinnedTabPage(
            tab: tab,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            summary: summary,
            header: {
                VideoDetailTransparentSegmentedPicker(selection: $selection)
                    .frame(width: 144, height: segmentedPickerHeight)
                    .videoDetailSegmentedPickerGlassEffect(libraryStore.videoDetailSegmentedPickerGlassStyle)
                    .frame(maxWidth: .infinity)
                    .background(VideoDetailTheme.background)
            },
            content: { tab in
                content(
                    tab,
                    mountsSecondaryContent || (tab == .comments && selection == .comments)
                )
            }
        )
    }
}

private struct VideoDetailPinnedTabPage<Header: View, Content: View>: View {
    let tab: VideoDetailContentTab
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let summary: AnyView?
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: (VideoDetailContentTab) -> Content
    @State private var position = ScrollPosition()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                summary
                Section {
                    content(tab)
                } header: {
                    header()
                }
            }
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .nativeTopScrollEdgeEffect()
        .onScrollGeometryChange(for: CGFloat.self) {
            max(0, $0.contentOffset.y + $0.contentInsets.top)
        } action: { _, offset in
            onScrollOffsetChange?(tab, offset)
        }
        .onChange(of: scrollAdjustment) { _, adjustment in
            guard let adjustment, adjustment.tab == tab else { return }
            position.scrollTo(y: adjustment.offset)
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func videoDetailSegmentedPickerGlassEffect(
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
    #if DEBUG
        private var lastWindowFrame = CGRect.null

        override func layoutSubviews() {
            super.layoutSubviews()
            let windowFrame = convert(bounds, to: window)
            if windowFrame != lastWindowFrame {
                lastWindowFrame = windowFrame
                print("[VideoDetailGeometry] headerFrame(window)=\(windowFrame)")
            }
        }
    #endif
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
