import SwiftUI

struct VideoDetailScrollAdjustment: Equatable {
    let tab: VideoDetailContentTab
    let offset: CGFloat
    let token: Int
}

struct VideoDetailNativeScrollTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let content: (VideoDetailContentTab) -> Content
    @State private var scrollPosition = ScrollPosition()
    @State private var appliedScrollAdjustmentToken = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topInset)

                content(tab)
                    .frame(width: layoutWidth, alignment: .top)
            }
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.hidden)
        .nativeTopScrollEdgeEffect()
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            onScrollOffsetChange(tab, offset)
        }
        .onAppear {
            applyScrollAdjustment(scrollAdjustment)
        }
        .onChange(of: scrollAdjustment) { _, adjustment in
            applyScrollAdjustment(adjustment)
        }
        .frame(width: layoutWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VideoDetailTheme.background)
    }

    private func applyScrollAdjustment(_ adjustment: VideoDetailScrollAdjustment?) {
        guard let adjustment, adjustment.tab == tab, adjustment.token != appliedScrollAdjustmentToken else { return }
        appliedScrollAdjustmentToken = adjustment.token
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition.scrollTo(y: max(0, adjustment.offset))
        }
    }
}
