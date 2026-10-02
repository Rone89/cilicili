import Foundation

/// Scoped to one committed seek. An absent output sample does not invalidate
/// advancing target frames already verified during this settle window.
nonisolated struct UserSeekRevealSettling {
    private(set) var readySince: TimeInterval?
    private var hasVerifiedRenderedFrame = false
    private var firstRenderedVideoTime: TimeInterval?
    private var firstRenderedAt: TimeInterval?
    private var lastRenderedVideoTime: TimeInterval?
    private(set) var hasAdvancingRenderedFrames = false

    mutating func reset() {
        readySince = nil
        hasVerifiedRenderedFrame = false
        firstRenderedVideoTime = nil
        firstRenderedAt = nil
        lastRenderedVideoTime = nil
        hasAdvancingRenderedFrames = false
    }

    /// Target-window validation is required first. During settling, normal forward
    /// playback may leave that window; keep the evidence only while the frame stays
    /// consistent with the playhead and elapsed time at the configured rate.
    func canContinueAdvancingFrame(
        renderedVideoTime: TimeInterval?,
        currentTime: TimeInterval?,
        isPlaying: Bool,
        playbackRate: Double,
        at now: TimeInterval
    ) -> Bool {
        guard readySince != nil, hasAdvancingRenderedFrames,
              isPlaying, playbackRate.isFinite, playbackRate > 0,
              now.isFinite, let firstRenderedAt, now >= firstRenderedAt,
              let firstRenderedVideoTime, let lastRenderedVideoTime,
              let frame = renderedVideoTime, frame.isFinite, frame >= 0,
              let playhead = currentTime, playhead.isFinite, playhead >= 0
        else { return false }
        return frame >= lastRenderedVideoTime
            && frame <= firstRenderedVideoTime + (now - firstRenderedAt) * playbackRate + 0.5
            && abs(playhead - frame) <= 0.5
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
                    firstRenderedAt = now
                }
            } else {
                firstRenderedVideoTime = time
                firstRenderedAt = now
            }
            lastRenderedVideoTime = time
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
