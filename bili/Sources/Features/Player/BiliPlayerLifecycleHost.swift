import Foundation
import SwiftUI
import UIKit

struct BiliPlayerLifecycleActions {
    let onAppear: () -> Void
    let onScenePhaseChanged: (ScenePhase) -> Void
    let onDidBecomeActive: () -> Void
    let onDisappear: () -> Void
    let onFullscreenActiveChanged: () -> Void
    let onPresentationChanged: () -> Void
    let onLayoutTransitionChanged: (Bool) -> Void
    let onSecondaryControlsPresentedChanged: (Bool) -> Void
    let onPictureInPictureEnabledChanged: (Bool) -> Void
}

private struct BiliPlayerLifecycleHostModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastActiveRecoveryEventAt: TimeInterval = 0

    let isFullscreenActive: Bool
    let presentation: BiliPlayerPresentation
    let isLayoutTransitioning: Bool
    let isSecondaryControlsPresented: Bool
    let isPictureInPictureEnabled: Bool
    let actions: BiliPlayerLifecycleActions

    func body(content: Content) -> some View {
        content
            .onAppear(perform: actions.onAppear)
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChanged(phase)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                handleWillResignActive()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                handleDidEnterBackground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                handleDidBecomeActive()
            }
            .onDisappear(perform: actions.onDisappear)
            .onChange(of: isFullscreenActive) { _, _ in
                actions.onFullscreenActiveChanged()
            }
            .onChange(of: presentation) { _, _ in
                actions.onPresentationChanged()
            }
            .onChange(of: isLayoutTransitioning) { _, isTransitioning in
                actions.onLayoutTransitionChanged(isTransitioning)
            }
            .onChange(of: isSecondaryControlsPresented) { _, isPresented in
                actions.onSecondaryControlsPresentedChanged(isPresented)
            }
            .onChange(of: isPictureInPictureEnabled) { _, isEnabled in
                actions.onPictureInPictureEnabledChanged(isEnabled)
            }
    }

    private func handleScenePhaseChanged(_ phase: ScenePhase) {
        guard phase == .active else {
            actions.onScenePhaseChanged(phase)
            return
        }
        guard shouldDeliverActiveRecoveryEvent() else { return }
        actions.onScenePhaseChanged(phase)
    }

    private func handleWillResignActive() {
        actions.onScenePhaseChanged(.inactive)
    }

    private func handleDidEnterBackground() {
        actions.onScenePhaseChanged(.background)
    }

    private func handleDidBecomeActive() {
        guard shouldDeliverActiveRecoveryEvent() else { return }
        actions.onDidBecomeActive()
    }

    private func shouldDeliverActiveRecoveryEvent() -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastActiveRecoveryEventAt > 0.35 else { return false }
        lastActiveRecoveryEventAt = now
        return true
    }
}

extension View {
    func biliPlayerLifecycle(
        isFullscreenActive: Bool,
        presentation: BiliPlayerPresentation,
        isLayoutTransitioning: Bool,
        isSecondaryControlsPresented: Bool,
        isPictureInPictureEnabled: Bool,
        actions: BiliPlayerLifecycleActions
    ) -> some View {
        modifier(
            BiliPlayerLifecycleHostModifier(
                isFullscreenActive: isFullscreenActive,
                presentation: presentation,
                isLayoutTransitioning: isLayoutTransitioning,
                isSecondaryControlsPresented: isSecondaryControlsPresented,
                isPictureInPictureEnabled: isPictureInPictureEnabled,
                actions: actions
            )
        )
    }
}
