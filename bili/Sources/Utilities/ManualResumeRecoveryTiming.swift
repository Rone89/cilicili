import Foundation

nonisolated struct ManualResumeRecoveryTiming: Sendable {
    struct TransportTiming: Equatable, Sendable {
        let pauseToPlayMilliseconds: Double
        let playToTransportMilliseconds: Double
    }

    struct FrameTiming: Equatable, Sendable {
        let pauseToFrameMilliseconds: Double
        let playToFrameMilliseconds: Double
    }

    private let pausedAt: Double
    private let baselineRenderedVideoTime: Double?
    private(set) var playRequestedAt: Double?
    private(set) var transportPlayingAt: Double?

    var canObserveAdvancingFrame: Bool { baselineRenderedVideoTime != nil }

    init?(pausedAt: Double, baselineRenderedVideoTime: Double?) {
        guard pausedAt.isFinite,
              baselineRenderedVideoTime.map({ $0.isFinite && $0 >= 0 }) ?? true
        else { return nil }
        self.pausedAt = pausedAt
        self.baselineRenderedVideoTime = baselineRenderedVideoTime
    }

    mutating func beginPlay(at now: Double) -> Double? {
        guard playRequestedAt == nil, now.isFinite, now >= pausedAt else { return nil }
        playRequestedAt = now
        return (now - pausedAt) * 1_000
    }

    mutating func observeTransportPlaying(at now: Double) -> TransportTiming? {
        guard transportPlayingAt == nil,
              now.isFinite,
              let playRequestedAt,
              now >= playRequestedAt
        else { return nil }
        transportPlayingAt = now
        return TransportTiming(
            pauseToPlayMilliseconds: (playRequestedAt - pausedAt) * 1_000,
            playToTransportMilliseconds: (now - playRequestedAt) * 1_000
        )
    }

    func observeFreshFrame(_ frameTime: Double?, at now: Double) -> FrameTiming? {
        guard let baselineRenderedVideoTime,
              let playRequestedAt,
              let transportPlayingAt,
              now.isFinite,
              now >= transportPlayingAt,
              let frameTime,
              frameTime.isFinite,
              frameTime > baselineRenderedVideoTime + 0.008
        else { return nil }
        return FrameTiming(
            pauseToFrameMilliseconds: (now - pausedAt) * 1_000,
            playToFrameMilliseconds: (now - playRequestedAt) * 1_000
        )
    }
}
