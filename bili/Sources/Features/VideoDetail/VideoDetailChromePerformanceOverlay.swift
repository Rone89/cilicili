import SwiftUI

struct VideoDetailChromePerformanceOverlay: View {
    @ObservedObject var store: VideoDetailNetworkDiagnosticsRenderStore
    let isPresented: Bool
    let hidesSystemChrome: Bool

    var body: some View {
        if isPresented {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VideoDetailPerformanceOverlayContainer(
                        store: store,
                        panelWidth: panelWidth(in: proxy),
                        maximumHeight: maximumHeight(in: proxy)
                    )
                    .padding(.bottom, bottomPadding(in: proxy))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func panelWidth(in proxy: GeometryProxy) -> CGFloat {
        let horizontalInset: CGFloat = proxy.size.width >= 700 ? 56 : 20
        let availableWidth = max(proxy.size.width - horizontalInset * 2, 300)
        return min(availableWidth, proxy.size.width >= 700 ? 560 : 430)
    }

    private func maximumHeight(in proxy: GeometryProxy) -> CGFloat {
        let heightRatio = hidesSystemChrome ? 0.38 : 0.34
        let availableHeight = max(proxy.size.height - bottomPadding(in: proxy) - 12, 220)
        return min(max(availableHeight * heightRatio, 220), 360)
    }

    private func bottomPadding(in proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.bottom, hidesSystemChrome ? 10 : 8) + 10
    }
}
