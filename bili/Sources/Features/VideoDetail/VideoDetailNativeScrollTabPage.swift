import SwiftUI

struct VideoDetailNativeScrollTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let content: (VideoDetailContentTab) -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topInset)

                content(tab)
                    .frame(width: layoutWidth, alignment: .top)
            }
        }
        .scrollIndicators(.hidden)
        .nativeTopScrollEdgeEffect()
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            onScrollOffsetChange(tab, offset)
        }
        .frame(width: layoutWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VideoDetailTheme.background)
    }
}
