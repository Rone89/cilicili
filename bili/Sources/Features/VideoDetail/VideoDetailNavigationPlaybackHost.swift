import Combine
import Foundation
import SwiftUI
import UIKit

struct VideoDetailNavigationPlaybackActions {
    let onNavigationWillDisappear: () -> Void
    let onNavigationDidAppear: () -> Void
    let onNavigationTransitionCompleted: (Bool) -> Void
    let onSystemBackGestureBegan: () -> Void
    let onAppear: () -> Void
    let onDisappear: () -> Void
    let onSceneBecameActive: () -> Void
}

private struct VideoDetailNavigationPlaybackHostModifier: ViewModifier {
    let scenePhase: ScenePhase
    let actions: VideoDetailNavigationPlaybackActions
    let lifecycleActions: VideoDetailNavigationPlaybackHostLifecycleActions
    @State private var lastActiveLifecycleEventAt: TimeInterval = 0

    func body(content: Content) -> some View {
        content
            .background(
                VideoDetailLifecycleBridge(
                    onWillDisappear: actions.onNavigationWillDisappear,
                    onDidAppear: actions.onNavigationDidAppear,
                    onTransitionCompleted: actions.onNavigationTransitionCompleted
                )
            )
            .background(
                VideoDetailSystemBackGestureBridge {
                    lifecycleActions.handleSystemBackGestureBegan()
                }
            )
            .onAppear(perform: actions.onAppear)
            .onDisappear(perform: actions.onDisappear)
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChanged(phase)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                handleApplicationDidBecomeActive()
            }
    }

    private func handleScenePhaseChanged(_ phase: ScenePhase) {
        guard phase == .active else { return }
        guard shouldDeliverActiveLifecycleEvent() else { return }
        lifecycleActions.handleScenePhaseChanged(phase)
    }

    private func handleApplicationDidBecomeActive() {
        guard shouldDeliverActiveLifecycleEvent() else { return }
        lifecycleActions.handleApplicationDidBecomeActive()
    }

    private func shouldDeliverActiveLifecycleEvent() -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastActiveLifecycleEventAt > 0.35 else { return false }
        lastActiveLifecycleEventAt = now
        return true
    }
}

extension View {
    func videoDetailNavigationPlaybackHost(
        scenePhase: ScenePhase,
        actions: VideoDetailNavigationPlaybackActions
    ) -> some View {
        modifier(
            VideoDetailNavigationPlaybackHostModifier(
                scenePhase: scenePhase,
                actions: actions,
                lifecycleActions: VideoDetailNavigationPlaybackHostLifecycleActions(actions: actions)
            )
        )
    }
}
