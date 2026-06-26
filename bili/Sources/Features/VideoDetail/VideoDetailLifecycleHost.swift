import SwiftUI
import UIKit

struct VideoDetailLifecycleActions {
    let onRotationLayoutTransitionBegan: () -> Void
    let onRotationLayoutTransition: () -> Void
    let onRotationLayoutTransitionCompleted: () -> Void
    let onDeviceOrientationChanged: () -> Void
    let onStopActiveVideoPlayback: () -> Void
    let onPauseActiveVideoPlaybackForNavigation: () -> Void
    let onResumeActiveVideoPlaybackAfterCancelledNavigation: () -> Void
}

private struct VideoDetailLifecycleHostModifier: ViewModifier {
    let actions: VideoDetailLifecycleActions
    let supportedOrientations: UIInterfaceOrientationMask
    let hidesSystemChrome: Bool
    let lifecycleActions: VideoDetailLifecycleHostNotificationActions

    func body(content: Content) -> some View {
        content
            .background(
                VideoDetailRotationLayoutBridge(
                    supportedOrientations: supportedOrientations,
                    hidesSystemChrome: hidesSystemChrome,
                    onLayoutTransitionBegan: actions.onRotationLayoutTransitionBegan,
                    onLayoutTransition: actions.onRotationLayoutTransition,
                    onTransitionCompleted: actions.onRotationLayoutTransitionCompleted
                )
            )
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                lifecycleActions.handleDeviceOrientationChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: .biliStopActiveVideoPlayback)) { _ in
                lifecycleActions.handleStopActiveVideoPlayback()
            }
            .onReceive(NotificationCenter.default.publisher(for: .biliPauseActiveVideoPlaybackForNavigation)) { _ in
                lifecycleActions.handlePauseActiveVideoPlaybackForNavigation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .biliResumeActiveVideoPlaybackAfterCancelledNavigation)) { _ in
                lifecycleActions.handleResumeActiveVideoPlaybackAfterCancelledNavigation()
            }
    }
}

extension View {
    func videoDetailLifecycle(
        actions: VideoDetailLifecycleActions,
        supportedOrientations: UIInterfaceOrientationMask,
        hidesSystemChrome: Bool
    ) -> some View {
        modifier(
            VideoDetailLifecycleHostModifier(
                actions: actions,
                supportedOrientations: supportedOrientations,
                hidesSystemChrome: hidesSystemChrome,
                lifecycleActions: VideoDetailLifecycleHostNotificationActions(actions: actions)
            )
        )
    }
}
