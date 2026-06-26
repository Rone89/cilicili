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
        HStack(spacing: 7) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: progress >= 1 ? "checkmark" : "arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(Double(progress) * 180))
                    .symbolEffect(.bounce, value: progress >= 1)
            }

            Text(isRefreshing ? "正在刷新" : progress >= 1 ? "松开刷新" : "下拉刷新")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .biliPlayerClearGlass(interactive: false, in: Capsule())
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.82)
        .offset(y: isVisible ? min(max(pullDistance * 0.18, 0), 14) : -8)
        .animation(.smooth(duration: 0.18), value: isVisible)
        .animation(.smooth(duration: 0.18), value: isRefreshing)
        .accessibilityHidden(!isVisible)
    }
}
