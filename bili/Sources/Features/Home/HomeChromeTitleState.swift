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

    func update(contentOffsetY: CGFloat) {
        let next = Self.progress(forContentOffsetY: contentOffsetY)
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
