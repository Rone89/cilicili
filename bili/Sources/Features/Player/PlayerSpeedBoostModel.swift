import Combine
import QuartzCore
import SwiftUI
import UIKit

enum PlayerSpeedBoostPhase: Equatable {
    case idle
    case boosting
    case locked
    case restoring
}

enum PlayerSpeedBoostEndReason: String {
    case gestureEnded
    case lockTapped
    case supersededBySeek
    case systemInterrupted
    case background
    case disappear
    case playerChanged
    case terminated

    var isInterruption: Bool {
        self != .gestureEnded && self != .lockTapped
    }

    var shouldShowPlaybackControls: Bool {
        false
    }
}

nonisolated enum PlayerSpeedBoostPolicy {
    enum RejectionReason: String, Equatable {
        case terminated
        case live
        case paused
        case alreadyAtMaximumRate
    }

    static let defaultBoostRate: Double = 1.5
    static let stepHorizontalDistance: CGFloat = 48
    static let hysteresisMargin: CGFloat = 8
    static let lockTriggerVerticalOffset: CGFloat = -52
    static let lockReleaseVerticalOffset: CGFloat = -36

    static func defaultBoostRate(for baselineRate: BiliPlaybackRate) -> Double {
        baselineRate == .x15 ? 2.0 : 1.5
    }

    static func rejectionReason(
        isTerminated: Bool,
        isLiveStream: Bool,
        isPlaying: Bool,
        currentRate: BiliPlaybackRate
    ) -> RejectionReason? {
        if isTerminated { return .terminated }
        if isLiveStream { return .live }
        if !isPlaying { return .paused }
        if currentRate == .x20 { return .alreadyAtMaximumRate }
        return nil
    }

    static func allowsGestureStart(at locationX: CGFloat, containerWidth: CGFloat) -> Bool {
        guard containerWidth > 0 else { return true }
        let edgeGuard = min(max(containerWidth * 0.05, 14), 24)
        return locationX >= edgeGuard && locationX <= containerWidth - edgeGuard
    }

    static func availableBoostRates(for baselineRate: BiliPlaybackRate) -> [Double] {
        switch baselineRate {
        case .x075, .x10:
            return [1.25, 1.5, 2.0]
        case .x125:
            return [1.5, 2.0]
        case .x15, .x20:
            return [2.0]
        }
    }

    static func resolvedBoostRate(
        forHorizontalOffset deltaX: CGFloat,
        baselineRate: BiliPlaybackRate,
        currentRate: Double
    ) -> Double {
        let tiers = availableBoostRates(for: baselineRate)
        let startRate = defaultBoostRate(for: baselineRate)
        guard let defaultIndex = tiers.firstIndex(of: startRate) else {
            return startRate
        }
        let currentIndex = tiers.firstIndex(of: currentRate) ?? defaultIndex
        let rawStep = Int((deltaX / stepHorizontalDistance).rounded(.towardZero))
        let unclampedTarget = defaultIndex + rawStep
        let targetIndex = min(max(unclampedTarget, 0), tiers.count - 1)

        if targetIndex == currentIndex {
            return currentRate
        }

        // Apply deadband hysteresis around tier boundaries to avoid jitter.
        if targetIndex > currentIndex {
            let threshold: CGFloat = currentIndex < defaultIndex
                ? CGFloat(currentIndex - defaultIndex) * stepHorizontalDistance + hysteresisMargin
                : CGFloat(currentIndex + 1 - defaultIndex) * stepHorizontalDistance
            if deltaX < threshold {
                return currentRate
            }
        } else {
            let threshold: CGFloat = currentIndex > defaultIndex
                ? CGFloat(currentIndex - defaultIndex) * stepHorizontalDistance - hysteresisMargin
                : CGFloat(currentIndex - 1 - defaultIndex) * stepHorizontalDistance
            if deltaX > threshold {
                return currentRate
            }
        }

        return tiers[targetIndex]
    }

    static func isLockTargetHighlighted(
        forVerticalOffset deltaY: CGFloat,
        currentlyHighlighted: Bool
    ) -> Bool {
        if currentlyHighlighted {
            return deltaY <= lockReleaseVerticalOffset
        }
        return deltaY <= lockTriggerVerticalOffset
    }

    static func formattedRateTitle(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...2))))x"
    }
}

@MainActor
final class PlayerSpeedBoostModel: ObservableObject {
    @Published private(set) var phase: PlayerSpeedBoostPhase = .idle
    @Published private(set) var displayedRate: BiliPlaybackRate = .x20
    @Published private(set) var displayedRateValue: Double = PlayerSpeedBoostPolicy.defaultBoostRate
    @Published private(set) var isLockTargetHighlighted = false

    var displayedRateTitle: String {
        PlayerSpeedBoostPolicy.formattedRateTitle(displayedRateValue)
    }

    private var state: PlayerSpeedBoostState?
    private weak var boostedPlayerViewModel: PlayerStateViewModel?
    private var restoreTransitionTask: Task<Void, Never>?
    private var restoreTransitionGeneration = 0
    private let transitionDurationNanoseconds: UInt64 = 140_000_000

    var isIndicatorVisible: Bool {
        phase != .idle
    }

    @discardableResult
    func beginIfNeeded(
        playerViewModel: PlayerStateViewModel,
        isSurfacePlaying: Bool,
        hidePlaybackControls: () -> Void
    ) -> Bool {
        if let existingState = state {
            guard phase == .locked else { return phase == .boosting }
            restoreTransitionTask?.cancel()
            restoreTransitionTask = nil
            restoreTransitionGeneration &+= 1
            let isPlaying = isSurfacePlaying || playerViewModel.isPlaying
            if let rejection = PlayerSpeedBoostPolicy.rejectionReason(
                isTerminated: playerViewModel.isTerminated,
                isLiveStream: playerViewModel.isLiveStream,
                isPlaying: isPlaying,
                currentRate: existingState.restoredRate
            ) {
                playerViewModel.recordSpeedBoostMetric("event=ignored reason=\(rejection.rawValue)")
                return false
            }
            let beganAt = CACurrentMediaTime()
            let initialBoostRate = PlayerSpeedBoostPolicy.defaultBoostRate(for: existingState.restoredRate)
            state = PlayerSpeedBoostState(
                restoredRate: existingState.restoredRate,
                beganAt: beganAt,
                activeBoostRate: initialBoostRate
            )
            boostedPlayerViewModel = playerViewModel
            displayedRate = BiliPlaybackRate(rawValue: initialBoostRate) ?? .x15
            displayedRateValue = initialBoostRate
            isLockTargetHighlighted = false
            setPhase(.boosting)
            Haptics.medium()
            hidePlaybackControls()
            playerViewModel.setTemporaryPlaybackRate(initialBoostRate)
            return true
        }

        let isPlaying = isSurfacePlaying || playerViewModel.isPlaying
        if let rejection = PlayerSpeedBoostPolicy.rejectionReason(
            isTerminated: playerViewModel.isTerminated,
            isLiveStream: playerViewModel.isLiveStream,
            isPlaying: isPlaying,
            currentRate: playerViewModel.playbackRate
        ) {
            playerViewModel.recordSpeedBoostMetric("event=ignored reason=\(rejection.rawValue)")
            return false
        }

        restoreTransitionTask?.cancel()
        restoreTransitionTask = nil
        restoreTransitionGeneration &+= 1
        let previousRate = playerViewModel.playbackRate
        let beganAt = CACurrentMediaTime()
        let initialBoostRate = PlayerSpeedBoostPolicy.defaultBoostRate(for: previousRate)
        state = PlayerSpeedBoostState(
            restoredRate: previousRate,
            beganAt: beganAt,
            activeBoostRate: initialBoostRate
        )
        boostedPlayerViewModel = playerViewModel
        displayedRate = BiliPlaybackRate(rawValue: initialBoostRate) ?? .x15
        displayedRateValue = initialBoostRate
        isLockTargetHighlighted = false
        setPhase(.boosting)
        Haptics.medium()
        hidePlaybackControls()
        playerViewModel.setTemporaryPlaybackRate(initialBoostRate)
        let rateElapsed = PlayerMetricsLog.elapsedMilliseconds(since: beganAt)
        playerViewModel.recordSpeedBoostMetric(
            "event=begin phase=boosting restore=\(previousRate.title) beginToRate=\(String(format: "%.0fms", rateElapsed))"
        )
        return true
    }

    func updateGestureOffset(
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat,
        playerViewModel: PlayerStateViewModel
    ) {
        guard phase == .boosting, var currentState = state else { return }
        let targetPlayer = boostedPlayerViewModel ?? playerViewModel
        guard !targetPlayer.isTerminated else { return }

        let nextLockHighlighted = PlayerSpeedBoostPolicy.isLockTargetHighlighted(
            forVerticalOffset: verticalOffset,
            currentlyHighlighted: isLockTargetHighlighted
        )
        if nextLockHighlighted != isLockTargetHighlighted {
            isLockTargetHighlighted = nextLockHighlighted
            Haptics.light()
        }

        let nextRate = PlayerSpeedBoostPolicy.resolvedBoostRate(
            forHorizontalOffset: horizontalOffset,
            baselineRate: currentState.restoredRate,
            currentRate: currentState.activeBoostRate
        )
        if nextRate != currentState.activeBoostRate {
            currentState.activeBoostRate = nextRate
            state = currentState
            displayedRateValue = nextRate
            if let matched = BiliPlaybackRate(rawValue: nextRate) {
                displayedRate = matched
            }
            targetPlayer.setTemporaryPlaybackRate(nextRate)
            Haptics.light()
            targetPlayer.recordSpeedBoostMetric(
                "event=tierChange rate=\(PlayerSpeedBoostPolicy.formattedRateTitle(nextRate))"
            )
        }
    }

    func unlock(
        playerViewModel: PlayerStateViewModel,
        showPlaybackControls: () -> Void
    ) {
        guard phase == .locked else { return }
        end(
            reason: .lockTapped,
            playerViewModel: playerViewModel,
            showPlaybackControls: showPlaybackControls
        )
    }

    func end(
        reason: PlayerSpeedBoostEndReason,
        playerViewModel: PlayerStateViewModel,
        showPlaybackControls: () -> Void
    ) {
        guard let state else { return }

        if phase == .boosting,
           reason == .gestureEnded,
           isLockTargetHighlighted {
            isLockTargetHighlighted = false
            setPhase(.locked)
            Haptics.success()
            let targetPlayer = boostedPlayerViewModel ?? playerViewModel
            targetPlayer.recordSpeedBoostMetric(
                "event=lock phase=locked rate=\(PlayerSpeedBoostPolicy.formattedRateTitle(state.activeBoostRate))"
            )
            return
        }

        if phase == .locked, reason == .supersededBySeek {
            return
        }

        self.state = nil
        isLockTargetHighlighted = false
        let boostedPlayerViewModel = self.boostedPlayerViewModel ?? playerViewModel
        self.boostedPlayerViewModel = nil
        let releasedAt = CACurrentMediaTime()
        let holdElapsed = PlayerMetricsLog.elapsedMilliseconds(since: state.beganAt)
        displayedRate = state.restoredRate
        displayedRateValue = state.restoredRate.rawValue
        setPhase(.restoring)

        guard !boostedPlayerViewModel.isTerminated else {
            boostedPlayerViewModel.recordSpeedBoostMetric(
                "event=end phase=restoring reason=\(reason.rawValue) interrupted=true hold=\(String(format: "%.0fms", holdElapsed)) restoreSkipped=terminated"
            )
            scheduleIdleTransition()
            return
        }
        boostedPlayerViewModel.setTemporaryPlaybackRate(state.restoredRate)
        let restoreElapsed = PlayerMetricsLog.elapsedMilliseconds(since: releasedAt)
        boostedPlayerViewModel.recordSpeedBoostMetric(
            "event=end phase=restoring reason=\(reason.rawValue) interrupted=\(reason.isInterruption) hold=\(String(format: "%.0fms", holdElapsed)) releaseToRestore=\(String(format: "%.0fms", restoreElapsed)) restore=\(state.restoredRate.title)"
        )
        if reason.shouldShowPlaybackControls {
            showPlaybackControls()
        }
        scheduleIdleTransition()
    }

    private func scheduleIdleTransition() {
        restoreTransitionTask?.cancel()
        restoreTransitionGeneration &+= 1
        let generation = restoreTransitionGeneration
        restoreTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.transitionDurationNanoseconds ?? 0)
            guard let self,
                  !Task.isCancelled,
                  self.restoreTransitionGeneration == generation,
                  self.state == nil
            else { return }
            self.restoreTransitionTask = nil
            self.setPhase(.idle)
        }
    }

    private func setPhase(_ phase: PlayerSpeedBoostPhase) {
        let update = {
            self.phase = phase
        }
        if UIAccessibility.isReduceMotionEnabled {
            update()
        } else {
            withAnimation(.easeInOut(duration: 0.14), update)
        }
    }
}

private struct PlayerSpeedBoostState: Equatable {
    let restoredRate: BiliPlaybackRate
    let beganAt: CFTimeInterval
    var activeBoostRate: Double
}
