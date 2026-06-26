import SwiftUI

@MainActor
final class HomeFeedRefreshActions {
    private var didTriggerConfiguredPullRefresh = false

    func retry(refresh: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            await refresh()
        }
    }

    func handleConfiguredPullRefresh(
        pullDistance: CGFloat,
        triggerDistance: CGFloat,
        isRefreshing: Bool,
        refresh: @escaping @MainActor () async -> Bool
    ) {
        if pullDistance < max(12, triggerDistance * 0.32) {
            didTriggerConfiguredPullRefresh = false
            return
        }
        guard pullDistance >= triggerDistance,
              !didTriggerConfiguredPullRefresh,
              !isRefreshing
        else { return }
        didTriggerConfiguredPullRefresh = true
        Haptics.medium()
        Task { @MainActor in
            if await refresh() {
                Haptics.success()
            }
        }
    }
}
