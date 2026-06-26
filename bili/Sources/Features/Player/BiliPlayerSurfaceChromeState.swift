import Foundation
import SwiftUI

struct BiliPlayerSurfaceChromeState {
    let presentation: BiliPlayerPresentation
    let surfaceOverlay: AnyView?
    let rotationSnapshot: PlaybackTransitionSnapshot?
    let rotationFallbackCoverURL: URL?
    let rotationSnapshotOpacity: Double
    let constrainsRotationSnapshotToVideoAspect: Bool
    let showsPlayerLoadingChrome: Bool
    let isBuffering: Bool
    let showsInlineLoadingProgress: Bool
    let isUserSeeking: Bool
    let isSpeedBoostActive: Bool
    let showsActivePlaybackControls: Bool
    let topLeadingControlsAccessory: AnyView?
    let isFullscreenActive: Bool
    let controlsBottomLift: CGFloat
    let errorMessage: String?
}
