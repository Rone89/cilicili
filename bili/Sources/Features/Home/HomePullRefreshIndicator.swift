import SwiftUI

struct HomePullRefreshIndicator: View {
    let pullDistance: CGFloat
    let triggerDistance: CGFloat
    let isRefreshing: Bool

    private var progress: CGFloat {
        guard triggerDistance > 0 else { return 0 }
        return min(max(pullDistance / triggerDistance, 0), 1)
    }

    private var isVisible: Bool {
        isRefreshing || progress > 0.08
    }

    var body: some View {
        ZStack {
            if isVisible {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.82)))
                } else {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.secondary)
                        .frame(width: 28, height: 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
                }
            }
        }
        .frame(width: 32, height: 32)
        .offset(y: isVisible ? min(max(pullDistance * 0.18, 0), 14) : -8)
        .animation(.smooth(duration: 0.18), value: isVisible)
        .animation(.smooth(duration: 0.18), value: isRefreshing)
        .animation(.easeOut(duration: 0.12), value: progress)
        .accessibilityLabel(isRefreshing ? "正在刷新" : "下拉刷新")
        .accessibilityValue(isRefreshing ? "" : "(Int((progress * 100).rounded()))%")
        .accessibilityHidden(!isVisible)
    }
}
