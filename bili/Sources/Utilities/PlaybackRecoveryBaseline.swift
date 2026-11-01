import Foundation

/// Diagnostic evidence only. A loaded player range does not establish disk-cache
/// reuse, CDN availability, or that a target frame has reached the display.
nonisolated struct PlaybackRecoveryBaseline: Equatable, Sendable {
    enum BufferState: String, Sendable {
        case covered, uncovered, unknown
    }

    let sampleID: String
    let build: String
    let requestedTargetTime: Double?
    let mode: String
    let networkClass: String
    let bufferState: BufferState
    let bufferAheadSeconds: Double?

    init(
        sampleID: String = UUID().uuidString,
        build: String = "-",
        mode: String,
        networkClass: String,
        targetTime: Double?,
        ranges: [PlayerBufferedRange]?
    ) {
        self.sampleID = sampleID
        self.build = build
        requestedTargetTime = targetTime.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.mode = mode
        self.networkClass = networkClass
        guard let targetTime, targetTime.isFinite, targetTime >= 0, let ranges else {
            bufferState = .unknown
            bufferAheadSeconds = nil
            return
        }
        let valid = ranges.filter {
            $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start
        }.sorted { $0.start < $1.start }
        // An empty observed list means no loaded range; malformed evidence is unknown.
        guard valid.count == ranges.count else {
            bufferState = .unknown
            bufferAheadSeconds = nil
            return
        }
        guard let index = valid.firstIndex(where: { $0.start <= targetTime && targetTime < $0.end }) else {
            bufferState = .uncovered
            bufferAheadSeconds = 0
            return
        }
        var end = valid[index].end
        for range in valid.dropFirst(index + 1) {
            guard range.start <= end else { break }
            end = max(end, range.end)
        }
        bufferState = .covered
        bufferAheadSeconds = end - targetTime
    }

    var diagnosticText: String {
        let ahead = bufferAheadSeconds.map {
            String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0)
        } ?? "-"
        let target = requestedTargetTime.map {
            String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0)
        } ?? "-"
        return "sampleID=\(sampleID) sampleBuild=\(build) mode=\(mode) networkClass=\(networkClass)"
            + " requestedTargetSeconds=\(target) targetLoadedRange=\(bufferState.rawValue) loadedAheadSeconds=\(ahead)"
            + " bufferEvidence=avPlayerLoadedTimeRanges mediaCacheState=unknown"
    }
}
