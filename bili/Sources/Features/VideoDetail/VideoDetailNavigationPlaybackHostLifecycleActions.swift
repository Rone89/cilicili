import SwiftUI

struct VideoDetailNavigationPlaybackHostLifecycleActions {
    let actions: VideoDetailNavigationPlaybackActions

    func handleSystemBackGestureBegan() {
        actions.onSystemBackGestureBegan()
    }

    func handleScenePhaseChanged(_ phase: ScenePhase) {
        guard phase == .active else { return }
        actions.onSceneBecameActive()
    }

    func handleApplicationDidBecomeActive() {
        actions.onSceneBecameActive()
    }
}
