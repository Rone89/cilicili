import Combine
import SwiftUI
import UIKit

enum VideoDetailFullscreenTrigger {
    case none
    case manual
    case rotation
}

@MainActor
final class VideoDetailFullscreenCoordinator: ObservableObject {
    typealias PlayerCurrentPredicate = @MainActor (PlayerStateViewModel) -> Bool

    @Published var mode: PlayerFullscreenMode?
    @Published var exitingMode: PlayerFullscreenMode?
    @Published var trigger: VideoDetailFullscreenTrigger = .none
    @Published var isCompletingExit = false
    @Published var isSystemRotationLayoutTransitioning = false
    @Published var morphState: VideoDetailFullscreenMorphState?

    static let inlineTransitionDuration: TimeInterval = 0.24
    static let inlineTransitionCompletionDelayNanoseconds: UInt64 = 260_000_000
    static let portraitExitSurfaceSettleDelayNanoseconds: UInt64 = 260_000_000
    static let enterSurfaceReadinessPollDelayNanoseconds: UInt64 = 34_000_000
    static let enterSurfaceReadinessMaximumWaitNanoseconds: UInt64 = 620_000_000
    static let enterSurfaceRequiredStableSamples = 1
    static let inlineTransitionAnimation = Animation.smooth(duration: inlineTransitionDuration)
    static let rotationPortraitExitOverlayDuration: TimeInterval = 0.46
    static let morphTransitionDuration: TimeInterval = 0.50
    static let morphTransitionAnimation = Animation.timingCurve(
        0.22,
        0.72,
        0.18,
        1,
        duration: morphTransitionDuration
    )
    static let morphTransitionCompletionDelayNanoseconds: UInt64 = 540_000_000
    static let morphFadeDuration: TimeInterval = 0.14
    static let morphFadeDurationNanoseconds: UInt64 = 140_000_000
    static let morphClearDelayNanoseconds: UInt64 = 170_000_000
    // 快照在 surface「布局刷新」后再停留一段，覆盖到视频帧真正渲染到新尺寸为止。
    // 布局刷新 ≠ 出帧，软解引擎(KSPlayer/DASH)重建首帧偏慢，故留足时间。
    // 快照是静止当前帧，多停留数百毫秒用户基本无感，远好于黑闪。
    static let enterMorphSurfaceSettleDelayNanoseconds: UInt64 = 90_000_000
    static let exitMorphSurfaceSettleDelayNanoseconds: UInt64 = 320_000_000
    static let exitMorphFallbackFadeDelayNanoseconds: UInt64 = 900_000_000

    var pendingRotationLandscapeOrientation: UIDeviceOrientation?
    var pendingFullscreenExitTask: Task<Void, Never>?
    var pendingSurfaceLayoutRefreshTask: Task<Void, Never>?
    var pendingRotationLayoutTransitionFinishTask: Task<Void, Never>?
    var pendingPortraitExitSurfaceSettleTask: Task<Void, Never>?
    var pendingMorphTransitionTask: Task<Void, Never>?
    var fullscreenTransitionGeneration = 0
    var surfaceLayoutRefreshGeneration = 0
    var rotationLayoutTransitionGeneration = 0
    var morphTransitionGeneration = 0
    var stateRevision = 0
    var latestPlayerSurfaceFrame: CGRect = .null
    var latestInlinePlayerSurfaceFrame: CGRect = .null
    var lastUsableMorphSnapshot: PlaybackTransitionSnapshot?
    var morphStartedAtNanoseconds: UInt64?

    var activeMode: PlayerFullscreenMode? {
        mode ?? exitingMode
    }

    var layoutMode: PlayerFullscreenMode? {
        // 退出过程中布局立即跟随目标方向（竖屏），不返回横屏的 exitingMode，
        // 避免与系统竖屏几何切换不同步产生“旋转缩小到中央”的错位帧。
        // 旋转期间由 window 级静态快照盖住过渡。
        mode
    }

    var shouldHideSystemChrome: Bool {
        activeMode != nil
            || isCompletingExit
            || isSystemRotationLayoutTransitioning
            || isMorphTransitionActive
    }

    var isMorphTransitionActive: Bool {
        morphState?.isActive == true
    }

    deinit {
        pendingFullscreenExitTask?.cancel()
        pendingSurfaceLayoutRefreshTask?.cancel()
        pendingRotationLayoutTransitionFinishTask?.cancel()
        pendingPortraitExitSurfaceSettleTask?.cancel()
        pendingMorphTransitionTask?.cancel()
    }
}
