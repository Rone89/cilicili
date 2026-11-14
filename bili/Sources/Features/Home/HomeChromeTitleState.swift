import Combine
import SwiftUI

/// Scroll-driven state for the home root title.
///
/// Mirrors Ibili's floating feed title: the title lifts and fades over the
/// first 44pt of upward scroll, then stays hidden while the feed keeps
/// scrolling. Kept as a reference type so per-frame scroll updates invalidate
/// only the navigation chrome instead of the whole home hierarchy.
final class HomeChromeTitleState: ObservableObject {
    static let fadeDistance: CGFloat = 44
    static let slideDistance: CGFloat = 24

    @Published private(set) var progress: CGFloat = 0
    private var restingInsetsTop: CGFloat = 0

    /// - Parameters:
    ///   - scrollSum: `contentOffset.y + contentInsets.top` (0 at resting top).
    ///   - insetsTop: the scroll view's current top content inset.
    ///   - isRefreshing: view-model refresh flag (best-effort extra guard).
    func update(scrollSum: CGFloat, insetsTop: CGFloat, isRefreshing: Bool = false) {
        // The pull-to-refresh control inflates the top inset, but SwiftUI does
        // not compensate contentOffset for it, so `scrollSum` transiently reads
        // as a downward scroll and would flicker the title out. Track the
        // resting inset and treat any inflation above it as refresh activity,
        // freezing the title visible until the inset settles back.
        if restingInsetsTop == 0 || scrollSum <= 0.5 {
            restingInsetsTop = insetsTop
        }
        let insetInflatedByRefresh = insetsTop > restingInsetsTop + 1
        if isRefreshing || insetInflatedByRefresh {
            if progress != 0 { progress = 0 }
            return
        }
        let next = Self.progress(forContentOffsetY: scrollSum)
        guard abs(next - progress) >= 0.01 else { return }
        progress = next
    }

    func reset() {
        guard progress != 0 else { return }
        progress = 0
    }

    static func progress(forContentOffsetY offset: CGFloat) -> CGFloat {
        min(max(offset, 0), fadeDistance) / fadeDistance
    }
}

private struct HomeChromeTitleStateKey: EnvironmentKey {
    static let defaultValue: HomeChromeTitleState? = nil
}

extension EnvironmentValues {
    /// Optional so previews, fixtures and non-home hosts do not need to
    /// provide the state object.
    var homeChromeTitleState: HomeChromeTitleState? {
        get { self[HomeChromeTitleStateKey.self] }
        set { self[HomeChromeTitleStateKey.self] = newValue }
    }
}
