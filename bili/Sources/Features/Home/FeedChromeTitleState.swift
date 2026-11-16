import Combine
import SwiftUI

/// Scroll-driven state for a feed root title (home / dynamic).
///
/// Mirrors Ibili's floating feed title: the title lifts and fades over the
/// first 44pt of upward scroll, then stays hidden while the feed keeps
/// scrolling. Kept as a reference type so per-frame scroll updates invalidate
/// only the navigation chrome instead of the whole feed hierarchy.
final class FeedChromeTitleState: ObservableObject {
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

private struct FeedChromeTitleStateKey: EnvironmentKey {
    static let defaultValue: FeedChromeTitleState? = nil
}

extension EnvironmentValues {
    /// Optional so previews, fixtures and non-feed hosts do not need to
    /// provide the state object.
    var feedChromeTitleState: FeedChromeTitleState? {
        get { self[FeedChromeTitleStateKey.self] }
        set { self[FeedChromeTitleStateKey.self] = newValue }
    }
}

private struct IsRootTabContentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the view is the root of a bottom-tab navigation stack (rather
    /// than a pushed destination). Feed roots hide the native navigation bar
    /// and draw their own top chrome; pushed destinations keep the bar so the
    /// back button remains available.
    var isRootTabContent: Bool {
        get { self[IsRootTabContentKey.self] }
        set { self[IsRootTabContentKey.self] = newValue }
    }
}
