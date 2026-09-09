import SwiftUI

struct VideoDetailNativeContentTabView<Content: View>: View {
    private let segmentedPickerHeight: CGFloat = 40
    @Environment(\.appThemeTintColor) private var appTintColor
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var bottomInset: CGFloat = 0
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
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer(minLength: 0)
                VideoDetailToolbarSegmentedPickerView(selection: $selection)
                    .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
                Spacer(minLength: 0)
            }
        }
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbarVisibility(.hidden, for: .tabBar)
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
        VideoDetailScrollingTabPage(
            tab: tab,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            summary: tab == .detail ? summary : nil,
            bottomInset: bottomInset + segmentedPickerHeight + 16,
            content: { tab in
                content(
                    tab,
                    mountsSecondaryContent || (tab == .comments && selection == .comments)
                )
            }
        )
    }
}

private struct VideoDetailScrollingTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let summary: AnyView?
    let bottomInset: CGFloat
    @ViewBuilder let content: (VideoDetailContentTab) -> Content
    @State private var position = ScrollPosition()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                summary
                content(tab)
            }
            .padding(.top, 12)
        }
        .scrollPosition($position)
        .contentMargins(.bottom, bottomInset, for: .scrollContent)
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
