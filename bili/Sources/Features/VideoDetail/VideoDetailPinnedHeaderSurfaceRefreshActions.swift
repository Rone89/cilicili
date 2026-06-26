import Foundation

struct VideoDetailPinnedHeaderSurfaceRefreshActions {
    let playerIdentityStore: VideoDetailPlayerIdentityRenderStore
    let surfaceRefreshCoordinator: VideoDetailPinnedDynamicPlayerHeaderSurfaceRefreshCoordinator

    @MainActor
    func schedule() {
        guard let playerViewModel = playerIdentityStore.playerViewModel,
              !playerViewModel.isTerminated
        else {
            surfaceRefreshCoordinator.cancel()
            return
        }
        surfaceRefreshCoordinator.schedule(playerIdentityStore: playerIdentityStore)
    }

    @MainActor
    func cancel() {
        surfaceRefreshCoordinator.cancel()
    }
}
