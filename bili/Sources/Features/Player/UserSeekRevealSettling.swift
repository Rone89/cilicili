import Foundation

/// Scoped to one committed seek. An absent output sample does not invalidate
/// advancing target frames already verified during this settle window.
nonisolated struct UserSeekRevealSettling {
    private(set) var readySince: TimeInterval?
    private var hasVerifiedRenderedFrame = false
    private var firstRenderedVideoTime: TimeInterval?
    private(set) var hasAdvancingRenderedFrames = false

    mutating func reset() {
        readySince = nil
        hasVerifiedRenderedFrame = false
        firstRenderedVideoTime = nil
        hasAdvancingRenderedFrames = false
    }

    static func canContinueMissingSample(
        renderedVideoTime: TimeInterval?,
        requiresRenderedVideoTime: Bool,
        isPlaying: Bool,
        currentTime: TimeInterval?,
        playbackTimeNearTarget: Bool
    ) -> Bool {
        renderedVideoTime == nil
            && requiresRenderedVideoTime
            && isPlaying
            && currentTime.map { $0.isFinite && $0 >= 0 } == true
            && playbackTimeNearTarget
    }

    mutating func observe(
        frameReady: Bool,
        renderedVideoTime: TimeInterval?,
        missingSampleCanContinue: Bool,
        requiresAdvancingVideo: Bool = false,
        at now: TimeInterval,
        settleDelay: TimeInterval
    ) -> Bool {
        let preservingVerifiedFrame = !frameReady
            && renderedVideoTime == nil
            && missingSampleCanContinue
            && hasVerifiedRenderedFrame
        guard frameReady || preservingVerifiedFrame else {
            reset()
            return false
        }
        if frameReady, let time = renderedVideoTime, time.isFinite, time >= 0 {
            hasVerifiedRenderedFrame = true
            if let first = firstRenderedVideoTime {
                if time > first + 0.001 {
                    hasAdvancingRenderedFrames = true
                } else if time < first - 0.001 {
                    // A regressing sample cannot carry forward a prior settle window.
                    readySince = nil
                    hasAdvancingRenderedFrames = false
                    firstRenderedVideoTime = time
                }
            } else {
                firstRenderedVideoTime = time
            }
        }
        if requiresAdvancingVideo && !hasAdvancingRenderedFrames {
            readySince = nil
            return false
        }
        guard let readySince else {
            readySince = now
            return false
        }
        return now - readySince >= settleDelay
    }
}
