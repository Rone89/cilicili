import Foundation

/// Scoped to one committed seek. An absent output sample does not invalidate
/// a target frame that was already verified during this settle window.
nonisolated struct UserSeekRevealSettling {
    private(set) var readySince: TimeInterval?
    private var hasVerifiedRenderedFrame = false

    mutating func reset() {
        readySince = nil
        hasVerifiedRenderedFrame = false
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
        at now: TimeInterval,
        settleDelay: TimeInterval
    ) -> Bool {
        let preservingVerifiedFrame = !frameReady
            && renderedVideoTime == nil
            && missingSampleCanContinue
            && hasVerifiedRenderedFrame
            && readySince != nil
        guard frameReady || preservingVerifiedFrame else {
            reset()
            return false
        }
        if frameReady, let time = renderedVideoTime, time.isFinite, time >= 0 {
            hasVerifiedRenderedFrame = true
        }
        guard let readySince else {
            readySince = now
            return false
        }
        return now - readySince >= settleDelay
    }
}
