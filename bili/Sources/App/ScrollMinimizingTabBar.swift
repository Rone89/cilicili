import Combine
import SwiftUI

enum ScrollMinimizingTabBarMetrics {
    static let minimumScale: CGFloat = 0.85
    static let progressDistance: CGFloat = 84
    static let settleThreshold: CGFloat = 0.5
    static let fastScrollDelta: CGFloat = 3
    static let horizontalPadding: CGFloat = 16
    static let bottomPadding: CGFloat = 6
    static let buttonHeight: CGFloat = 52
}

struct ScrollMinimizingTabBarProgress: Equatable {
    private(set) var value: CGFloat = 0
    private var shiftOffset: CGFloat?
    private var lastOffset: CGFloat?
    private var lastDelta: CGFloat = 0

    mutating func update(
        offset: CGFloat,
        contentHeight: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        guard contentHeight > containerHeight + 1, offset > 0 else {
            reset()
            return value
        }

        let normalizedOffset = max(offset, 0)
        if let lastOffset {
            let delta = normalizedOffset - lastOffset
            if delta * lastDelta < 0 {
                shiftOffset = normalizedOffset - value * ScrollMinimizingTabBarMetrics.progressDistance
            }
            lastDelta = delta
        }
        if shiftOffset == nil {
            shiftOffset = normalizedOffset - value * ScrollMinimizingTabBarMetrics.progressDistance
        }

        value = min(
            max((normalizedOffset - (shiftOffset ?? normalizedOffset)) / ScrollMinimizingTabBarMetrics.progressDistance, 0),
            1
        )
        lastOffset = normalizedOffset
        return value
    }

    mutating func settle() -> CGFloat {
        if abs(lastDelta) >= ScrollMinimizingTabBarMetrics.fastScrollDelta {
            value = lastDelta > 0 ? 1 : 0
        } else {
            value = value >= ScrollMinimizingTabBarMetrics.settleThreshold ? 1 : 0
        }
        shiftOffset = lastOffset.map {
            $0 - value * ScrollMinimizingTabBarMetrics.progressDistance
        }
        return value
    }

    mutating func reset() {
        value = 0
        shiftOffset = nil
        lastOffset = nil
        lastDelta = 0
    }
}

@MainActor
final class ScrollMinimizingTabBarState: ObservableObject {
    @Published private(set) var progress: CGFloat = 0

    private var activeTab: AppTab?
    private var model = ScrollMinimizingTabBarProgress()
    private var reducesMotion = false

    var scale: CGFloat {
        1 - progress * (1 - ScrollMinimizingTabBarMetrics.minimumScale)
    }

    func configure(reducesMotion: Bool) {
        self.reducesMotion = reducesMotion
    }

    func select(_ tab: AppTab) {
        guard activeTab != tab else { return }
        activeTab = tab
        model.reset()
        setProgress(0, animated: false)
    }

    func update(
        tab: AppTab,
        offset: CGFloat,
        contentHeight: CGFloat,
        containerHeight: CGFloat
    ) {
        guard activeTab == tab else { return }
        setProgress(
            model.update(
                offset: offset,
                contentHeight: contentHeight,
                containerHeight: containerHeight
            ),
            animated: false
        )
    }

    func finishScrolling(for tab: AppTab) {
        guard activeTab == tab else { return }
        setProgress(model.settle(), animated: true)
    }

    func expand() {
        model.reset()
        setProgress(0, animated: true)
    }

    private func setProgress(_ value: CGFloat, animated: Bool) {
        let update = { self.progress = value }
        guard animated, !reducesMotion else {
            update()
            return
        }
        withAnimation(.smooth(duration: 0.22), update)
    }
}

private struct ScrollMinimizingTabBarStateKey: EnvironmentKey {
    static let defaultValue: ScrollMinimizingTabBarState? = nil
}

private struct ScrollMinimizingTabBarExperimentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var scrollMinimizingTabBarState: ScrollMinimizingTabBarState? {
        get { self[ScrollMinimizingTabBarStateKey.self] }
        set { self[ScrollMinimizingTabBarStateKey.self] = newValue }
    }

    var scrollMinimizingTabBarExperimentEnabled: Bool {
        get { self[ScrollMinimizingTabBarExperimentKey.self] }
        set { self[ScrollMinimizingTabBarExperimentKey.self] = newValue }
    }
}

private struct RootTabBarScrollGeometry: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
}

private struct RootTabBarScrollObserver: ViewModifier {
    @Environment(\.scrollMinimizingTabBarState) private var state
    let tab: AppTab

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: RootTabBarScrollGeometry.self) { geometry in
                RootTabBarScrollGeometry(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height
                )
            } action: { _, geometry in
                state?.update(
                    tab: tab,
                    offset: geometry.offset,
                    contentHeight: geometry.contentHeight,
                    containerHeight: geometry.containerHeight
                )
            }
            .onScrollPhaseChange { _, phase in
                guard phase == .idle else { return }
                state?.finishScrolling(for: tab)
            }
    }
}

private struct ScrollMinimizingTabBarContentPadding: ViewModifier {
    @Environment(\.scrollMinimizingTabBarExperimentEnabled) private var isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.safeAreaPadding(.bottom, RootFloatingTabBarMetrics.contentBottomPadding)
        } else {
            content
        }
    }
}

extension View {
    func observesRootTabBarScroll(for tab: AppTab) -> some View {
        modifier(RootTabBarScrollObserver(tab: tab))
    }

    func scrollMinimizingTabBarContentPadding() -> some View {
        modifier(ScrollMinimizingTabBarContentPadding())
    }
}

struct ScrollMinimizingTabBar: View {
    @Binding var selection: AppTab
    let tabs: [AppTab]
    let tintColor: Color
    @ObservedObject var state: ScrollMinimizingTabBarState
    let selectTab: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    state.expand()
                    selectTab(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: tab == selection ? .semibold : .regular))
                        Text(tab.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(tab == selection ? tintColor : .secondary)
                    .frame(maxWidth: .infinity, minHeight: ScrollMinimizingTabBarMetrics.buttonHeight)
                    .background {
                        if tab == selection {
                            Capsule()
                                .fill(tintColor.opacity(0.15))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(tab == selection ? "已选中" : "")
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .padding(4)
        .biliRegularGlassEffect(interactive: true, in: Capsule())
        .scaleEffect(state.scale, anchor: .bottom)
        .padding(.horizontal, ScrollMinimizingTabBarMetrics.horizontalPadding)
        .padding(.bottom, ScrollMinimizingTabBarMetrics.bottomPadding)
        .accessibilityIdentifier("root.scrollMinimizingTabBar")
    }
}
