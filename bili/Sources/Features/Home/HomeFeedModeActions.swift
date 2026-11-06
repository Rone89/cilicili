import SwiftUI

@MainActor
final class HomeNativeRefreshActionStore {
    var action: RefreshAction?
}

@MainActor
final class HomeFeedModeActions {
    private var switchTask: Task<Void, Never>?

    func switchMode(
        _ mode: HomeFeedMode,
        viewModel: HomeViewModel,
        scrollActions: HomeFeedScrollActions,
        nativeRefreshActionStore: HomeNativeRefreshActionStore
    ) {
        guard viewModel.mode != mode else { return }
        switchTask?.cancel()
        // 切换模式时瞬时回顶：与取消的过渡动画配合，整页不再有任何切换动画。
        scrollActions.requestScrollToTop(animated: false)
        let nativeRefreshAction = nativeRefreshActionStore.action
        switchTask = Task { @MainActor in
            await viewModel.switchMode(mode, using: nativeRefreshAction)
        }
    }

    deinit {
        switchTask?.cancel()
    }
}
