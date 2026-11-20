import Foundation
import SwiftUI
import UIKit

struct BiliPlayerLifecycleActions {
    let onAppear: () -> Void
    let onPlayerChanged: () -> Void
    let onScenePhaseChanged: (ScenePhase) -> Void
    let onDisappear: () -> Void
    let onFullscreenActiveChanged: () -> Void
    let onPresentationChanged: () -> Void
    let onLayoutTransitionChanged: (Bool) -> Void
    let onSecondaryControlsPresentedChanged: (Bool) -> Void
    let onPictureInPictureEnabledChanged: (Bool) -> Void
}

private struct BiliPlayerLifecycleHostModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastDeliveredScenePhase: ScenePhase?

    let isFullscreenActive: Bool
    let presentation: BiliPlayerPresentation
    let isLayoutTransitioning: Bool
    let isSecondaryControlsPresented: Bool
    let isPictureInPictureEnabled: Bool
    let actions: BiliPlayerLifecycleActions

    func body(content: Content) -> some View {
        content
            .onAppear {
                let phase = currentApplicationScenePhase
                lastDeliveredScenePhase = phase
                actions.onAppear()
                if phase != .active {
                    actions.onScenePhaseChanged(phase)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                deliver(.inactive)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                deliver(.background)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                deliver(.active)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background,
                   !BiliPlayerLifecycleHostPolicy.shouldDeliverBackgroundScenePhase(
                       applicationState: UIApplication.shared.applicationState,
                       hasForegroundKeyWindow: UIApplication.shared.playbackDetailForegroundKeyWindow != nil
                   ) {
                    PlayerMetricsLog.diagnostic("appLifecycle ignoreSwiftUIScenePhaseBackground appActive=true")
                    return
                }
                deliver(phase)
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

    private func deliver(_ phase: ScenePhase) {
        guard lastDeliveredScenePhase != phase else { return }
        lastDeliveredScenePhase = phase
        actions.onScenePhaseChanged(phase)
    }

    private var currentApplicationScenePhase: ScenePhase {
        switch UIApplication.shared.applicationState {
        case .active:
            .active
        case .background:
            .background
        default:
            .inactive
        }
    }
}

@MainActor
enum BiliPlayerLifecycleHostPolicy {
    static func shouldDeliverBackgroundScenePhase(
        applicationState: UIApplication.State,
        hasForegroundKeyWindow: Bool
    ) -> Bool {
        !(applicationState == .active && hasForegroundKeyWindow)
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
