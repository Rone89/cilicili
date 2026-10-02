import Foundation
import CryptoKit
import QuartzCore

#if DEBUG
import OSLog
#endif

private nonisolated let recoveryTraceMaximumEventCount = 160

private nonisolated func recoveryTraceSanitizedKey(_ key: String) -> String {
    let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = value.map { character in
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == "."
            ? String(character)
            : "_"
    }.joined()
    return String(safe.prefix(64)).isEmpty ? "-" : String(safe.prefix(64))
}

private nonisolated func recoveryTraceHash(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    let hex = digest.map { String(format: "%02x", Int($0)) }.joined()
    return "sha256:\(hex)"
}

private nonisolated func recoveryTraceSanitizedValue(_ value: String, key: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "-" }

    let loweredKey = key.lowercased()
    let loweredValue = trimmed.lowercased()
    let isSensitive = loweredKey == "resource"
        || loweredKey.contains("resourceid")
        || loweredKey.contains("url")
        || loweredKey.contains("cookie")
        || loweredKey.contains("token")
        || loweredKey.contains("authorization")
        || loweredKey.contains("referer")
        || loweredKey.contains("secret")
        || loweredKey.contains("password")
        || loweredValue.contains("http://")
        || loweredValue.contains("https://")
    if isSensitive {
        return recoveryTraceHash(trimmed)
    }

    let flattened = trimmed.map { character in
        character.isWhitespace || character == "=" || character == "|"
            ? "_"
            : String(character)
    }.joined()
    return String(flattened.prefix(256)).isEmpty ? "-" : String(flattened.prefix(256))
}

private nonisolated func recoveryTraceSanitizedFields(_ fields: [String: String]) -> [String: String] {
    var result: [String: String] = [:]
    for key in fields.keys.sorted() {
        let safeKey = recoveryTraceSanitizedKey(key)
        result[safeKey] = recoveryTraceSanitizedValue(fields[key] ?? "", key: safeKey)
    }
    return result
}

private nonisolated func recoveryTraceDouble(_ value: String?) -> Double? {
    guard let value, value != "-", let number = Double(value), number.isFinite else {
        return nil
    }
    return number
}

private nonisolated func recoveryTraceBoolean(_ value: String?) -> String? {
    guard let value else { return nil }
    switch value.lowercased() {
    case "true", "yes", "1":
        return "true"
    case "false", "no", "0":
        return "false"
    case "unknown", "-":
        return "unknown"
    default:
        return nil
    }
}

private nonisolated func recoveryTraceDuration(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "-" }
    return String(format: "%.1fms", locale: Locale(identifier: "en_US_POSIX"), seconds * 1_000)
}

private nonisolated func recoveryTraceMilliseconds(_ milliseconds: Double?) -> String {
    guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return "-" }
    return String(format: "%.1fms", locale: Locale(identifier: "en_US_POSIX"), milliseconds)
}

private nonisolated func recoveryTraceTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "-" }
    return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)
}

private nonisolated func recoveryTraceNormalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
    return normalized.isEmpty || normalized == "-" ? nil : normalized
}

nonisolated enum RecoveryTraceDiagnostics {
    struct LoadedRange: Equatable, Sendable {
        let start: Double
        let duration: Double
    }

    static func bufferCoverage(
        currentTime: Double,
        ranges: [LoadedRange]
    ) -> (ahead: Double, covered: Bool) {
        guard currentTime.isFinite else { return (0, false) }

        var containingEnd: Double?
        for range in ranges {
            guard range.start.isFinite,
                  range.duration.isFinite,
                  range.duration > 0
            else { continue }
            let end = range.start + range.duration
            guard end.isFinite,
                  currentTime >= range.start,
                  currentTime <= end
            else { continue }
            if containingEnd == nil || end > containingEnd! {
                containingEnd = end
            }
        }

        guard let containingEnd else { return (0, false) }
        return (max(0, containingEnd - currentTime), true)
    }

    static func rangeFailureEvent(_ error: Error) -> String {
        error is CancellationError || (error as? URLError)?.code == .cancelled
            ? "rangeCancelled" : "rangeFailed"
    }

    static func rangeSource(_ raw: String?) -> String {
        guard let raw else { return "unknown" }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cache", "diskcache", "memorycache", "mediacache":
            return "cache"
        case "join", "streamjoin", "pending", "joined":
            return "joined"
        case "network", "stream", "fetch", "miss":
            return "network"
        default:
            return "unknown"
        }
    }

    static func sameRange(
        warmResource: String?,
        warmStart: Int64?,
        warmLength: Int64?,
        playerResource: String?,
        playerStart: Int64?,
        playerLength: Int64?
    ) -> Bool? {
        guard let warmResource = nonEmpty(warmResource),
              let playerResource = nonEmpty(playerResource),
              let warmStart,
              let warmLength,
              let playerStart,
              let playerLength,
              warmStart >= 0,
              playerStart >= 0,
              warmLength > 0,
              playerLength > 0
        else { return nil }

        return warmResource == playerResource
            && warmStart == playerStart
            && warmLength == playerLength
    }

    static func isRecoveryFrame(
        type: String,
        frameTime: Double,
        baseline: Double,
        target: Double?,
        seekCompleted: Bool,
        playCalled: Bool
    ) -> Bool {
        guard frameTime.isFinite,
              baseline.isFinite,
              target.map(\.isFinite) ?? true
        else { return false }

        switch type {
        case "manualResume":
            return playCalled && frameTime > baseline + 0.001
        case "userSeek":
            guard seekCompleted, let target else { return false }
            return abs(frameTime - target) <= 0.75
        default:
            return false
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Timestamp evidence from existing reads only; never used to authorize playback or reveal.
nonisolated struct RecoveryVideoObservation {
    enum Origin: String, CaseIterable, Sendable {
        case snapshot, renderedTime, frameImage, debugPoll
    }

    struct Sample: Equatable, Sendable {
        let at: Double
        let mediaTime: Double
        let origin: Origin
    }

    private struct Counts {
        var reads = 0
        var missing = 0
        var rejected = 0
        var repeated = 0
        var lastAt: Double?
        var lastMediaTime: Double?
        var maxGap: Double?
    }

    private var counts: [Origin: Counts] = [:]
    private var comparisonSample: Sample?
    private var lastAt: Double?
    private(set) var firstAvailable: Sample?
    private(set) var firstAdvancing: Sample?

    /// Returns at most two milestone names per trace. Repeated/missing samples only update counters.
    mutating func observe(frameTime: Double?, qualifies: Bool, origin: Origin, at: Double) -> String? {
        guard at.isFinite, lastAt.map({ at >= $0 }) ?? true else { return nil }
        lastAt = at
        var values = counts[origin] ?? Counts()
        values.reads += 1
        if let previousAt = values.lastAt {
            values.maxGap = max(values.maxGap ?? 0, at - previousAt)
        }
        values.lastAt = at
        defer { counts[origin] = values }
        guard let frameTime else {
            values.missing += 1
            return nil
        }
        guard qualifies, frameTime.isFinite, frameTime >= 0 else {
            values.rejected += 1
            return nil
        }
        if let previousTime = values.lastMediaTime, abs(frameTime - previousTime) <= 0.001 {
            values.repeated += 1
        }
        values.lastMediaTime = frameTime
        let sample = Sample(at: at, mediaTime: frameTime, origin: origin)
        guard let previous = comparisonSample else {
            comparisonSample = sample
            firstAvailable = sample
            return "targetVideoAvailable"
        }
        guard firstAdvancing == nil else { return nil }
        if frameTime < previous.mediaTime - 0.001 {
            comparisonSample = sample
        } else if frameTime > previous.mediaTime + 0.001 {
            firstAdvancing = sample
            return "targetVideoAdvanceObserved"
        }
        return nil
    }

    var fields: [String: String] {
        var fields = [
            "availableAt": firstAvailable.map { String($0.at) } ?? "-",
            "availableOrigin": firstAvailable?.origin.rawValue ?? "-",
            "advancingAt": firstAdvancing.map { String($0.at) } ?? "-",
            "advancingOrigin": firstAdvancing?.origin.rawValue ?? "-",
            "observation": "videoOutputTimestampNotDisplayPresentation",
        ]
        for origin in Origin.allCases {
            let prefix = origin.rawValue
            guard let value = counts[origin] else {
                for suffix in ["Reads", "Missing", "Rejected", "Repeated", "MaxGapMs"] {
                    fields["\(prefix)\(suffix)"] = "-"
                }
                continue
            }
            fields["\(prefix)Reads"] = String(value.reads)
            fields["\(prefix)Missing"] = String(value.missing)
            fields["\(prefix)Rejected"] = String(value.rejected)
            fields["\(prefix)Repeated"] = String(value.repeated)
            fields["\(prefix)MaxGapMs"] = value.maxGap.map { String($0 * 1_000) } ?? "-"
        }
        return fields
    }
}

nonisolated struct RecoveryTraceRecord: Equatable, Sendable {
    struct Event: Equatable, Sendable {
        let name: String
        let at: Double
        let fields: [String: String]

        init(name: String, at: Double, fields: [String: String] = [:]) {
            self.name = recoveryTraceSanitizedKey(name)
            self.at = at
            self.fields = recoveryTraceSanitizedFields(fields)
        }
    }

    let id: String
    let type: String
    let metricsID: String?
    let startedAt: Double
    let fields: [String: String]
    private(set) var events: [Event]

    init(
        id: String,
        type: String,
        metricsID: String?,
        startedAt: Double,
        fields: [String: String] = [:],
        events: [Event] = []
    ) {
        self.id = recoveryTraceSanitizedValue(id, key: "id")
        self.type = recoveryTraceSanitizedValue(type, key: "type")
        self.metricsID = metricsID.map { recoveryTraceSanitizedValue($0, key: "metricsID") }
        self.startedAt = startedAt
        self.fields = recoveryTraceSanitizedFields(fields)
        self.events = Array(events.filter { $0.at.isFinite }.suffix(recoveryTraceMaximumEventCount))
    }

    mutating func record(name: String, at: Double, fields: [String: String] = [:]) {
        guard at.isFinite else { return }
        let event = Event(name: name, at: at, fields: fields)
        if ["waiting", "waitingReason", "playing"].contains(event.name),
           let last = events.last, last.name == event.name, last.fields == event.fields { return }
        events.append(event)
        events.sort { $0.at < $1.at }
        if events.count > recoveryTraceMaximumEventCount {
            events.removeSubrange(1...events.count - recoveryTraceMaximumEventCount)
        }
    }

    var summary: String {
        let resumeEvent = firstEvent(named: ["resumeRequested", "resumeStart", "start"])
        let seekRequested = firstEvent(named: ["seekRequested", "seekStart"])
        let seekAligned = firstEvent(named: ["seekAligned"])
        let seekCall = firstEvent(named: ["seekCall"])
        let seekCompletion = firstEvent(named: ["seekCompletion"], after: seekCall?.at)
        let recoverSurfaceStart = firstEvent(named: ["recoverSurfaceStart"])
        let recoverSurfaceComplete = firstEvent(
            named: ["recoverSurfaceComplete"],
            after: recoverSurfaceStart?.at
        )
        let playCalled = firstEvent(named: ["playCalled"], after: resumeEvent?.at)
        let playing = firstEvent(named: ["playing"], after: playCalled?.at)
        let firstNewFrame = firstEvent(named: ["firstNewFrame"], after: resumeEvent?.at)
        let firstTargetFrame = firstEvent(
            named: ["firstTargetFrame"],
            after: seekRequested?.at
        )
        let firstFrame = type == "userSeek" ? (firstTargetFrame ?? firstNewFrame) : (firstNewFrame ?? firstTargetFrame)
        let uiReveal = firstEvent(named: ["uiReveal"], after: seekRequested?.at)
        let videoObservation = events.last { $0.name == "videoObservationSummary" }?.fields
        let revealTiming = events.last { $0.name == "uiRevealTiming" }?.fields
        let videoAvailableAt = recoveryTraceDouble(videoObservation?["availableAt"])
        let videoAdvancingAt = recoveryTraceDouble(videoObservation?["advancingAt"])
        let uiAdvanceConfirmation = events.first {
            $0.name == "uiRevealDecision" && $0.fields["hasAdvancingRenderedFrames"] == "true"
        }

        let resumeAnchor = resumeEvent?.at ?? (startedAt.isFinite ? startedAt : nil)
        let pauseDuration = resumeEvent.flatMap { event -> Double? in
            guard let pauseStartedAt = recoveryTraceDouble(event.fields["pauseStartedAt"]),
                  pauseStartedAt.isFinite,
                  event.at >= pauseStartedAt
            else { return nil }
            return event.at - pauseStartedAt
        }
        let resumeToPlayCalled = duration(from: resumeAnchor, to: playCalled?.at)
        let playCalledToPlaying = duration(from: playCalled?.at, to: playing?.at)
        let playCalledToFirstFrame = duration(from: playCalled?.at, to: firstFrame?.at)
        let resumeToFirstFrame = duration(from: resumeAnchor, to: firstFrame?.at)
        let seekCallToCompletion: Double? = {
            guard let seekCompletion,
                  recoveryTraceBoolean(seekCompletion.fields["finished"]) == "true"
            else { return nil }
            return duration(from: seekCall?.at, to: seekCompletion.at)
        }()
        let recoverSurfaceDuration = duration(from: recoverSurfaceStart?.at, to: recoverSurfaceComplete?.at)
        let seekRequestedToFirstTargetFrame = duration(from: seekRequested?.at, to: firstTargetFrame?.at)
        let firstTargetFrameToUIReveal = duration(from: firstTargetFrame?.at, to: uiReveal?.at)
        let seekRequestedToUIReveal = duration(from: seekRequested?.at, to: uiReveal?.at)

        let videoRange = targetRangeMetric(track: "video")
        let audioRange = targetRangeMetric(track: "audio")
        let audioConfigDurations = orderedAudioActivationDurations()
        let warmSource = seekWarmSource()
        let sameRange = warmAndPlayerSameRange()
        let oldRangeStillActive = oldRangeStillActiveValue()
        let waitingReason = waitingReasonValue()
        let terminal = events.reversed().first { event in
            ["cancel", "cancelled", "canceled", "superseded", "sessionEnded"].contains(event.name)
        }?.name ?? "-"
        let eventTimes = events.map { "\($0.name)@\(recoveryTraceTime($0.at))" }.joined(separator: ",")
        let eventNames = eventTimes.isEmpty
            ? "-"
            : eventTimes

        var parts = [
            "[RecoveryTraceSummary]",
            "type=\(type)",
            "id=\(id)",
            "metricsID=\(metricsID ?? "-")",
            "fields=\(summaryFields(fields))",
            "pauseDuration=\(recoveryTraceDuration(pauseDuration))",
            "audioActivationPlay=\(recoveryTraceDuration(audioActivationDuration(phase: "play")))",
            "audioActivationRecoverSurface=\(recoveryTraceDuration(audioActivationDuration(phase: "recoverSurface")))",
            "audioActivationOther=\(recoveryTraceDuration(audioActivationDuration(phase: "other")))",
            "audioConfig1=\(recoveryTraceDuration(audioConfigDurations.count > 0 ? audioConfigDurations[0] : nil))",
            "audioConfig2=\(recoveryTraceDuration(audioConfigDurations.count > 1 ? audioConfigDurations[1] : nil))",
            "resumeToPlayCalled=\(recoveryTraceDuration(resumeToPlayCalled))",
            "playCalledToPlaying=\(recoveryTraceDuration(playCalledToPlaying))",
            "playCalledToFirstFrame=\(recoveryTraceDuration(playCalledToFirstFrame))",
            "resumeToFirstFrame=\(recoveryTraceDuration(resumeToFirstFrame))",
            "seekCallToCompletion=\(recoveryTraceDuration(seekCallToCompletion))",
            "recoverSurfaceMs=\(recoveryTraceDuration(recoverSurfaceDuration))",
            "seekRequestedToFirstTargetFrame=\(recoveryTraceDuration(seekRequestedToFirstTargetFrame))",
            "firstTargetFrameToUIReveal=\(recoveryTraceDuration(firstTargetFrameToUIReveal))",
            "seekRequestedToUIReveal=\(recoveryTraceDuration(seekRequestedToUIReveal))",
            "targetVideoAvailableToAdvance=\(recoveryTraceDuration(duration(from: videoAvailableAt, to: videoAdvancingAt)))",
            "playToVideoAdvanceObserved=\(recoveryTraceDuration(duration(from: playCalled?.at, to: videoAdvancingAt)))",
            "playingToVideoAdvanceObserved=\(recoveryTraceDuration(duration(from: playing?.at, to: videoAdvancingAt)))",
            "videoAdvanceToUIConfirmation=\(recoveryTraceDuration(duration(from: videoAdvancingAt, to: uiAdvanceConfirmation?.at)))",
            "videoAdvanceToUIReveal=\(recoveryTraceDuration(duration(from: videoAdvancingAt, to: uiReveal?.at)))",
            "videoAvailableOrigin=\(videoObservation?["availableOrigin"] ?? "-")",
            "videoAdvancingOrigin=\(videoObservation?["advancingOrigin"] ?? "-")",
            "targetVideoRangeSource=\(videoRange.source)",
            "targetVideoRangeTTFB=\(videoRange.ttfb)",
            "targetAudioRangeSource=\(audioRange.source)",
            "targetAudioRangeTTFB=\(audioRange.ttfb)",
            "seekWarmSource=\(warmSource)",
            "warmAndPlayerSameRange=\(sameRange)",
            "oldRangeStillActive=\(oldRangeStillActive)",
            "waitingReason=\(waitingReason)",
            "uiRevealLastDecision=\(events.last(where: { $0.name == "uiRevealDecision" })?.fields["decision"] ?? "-")",
            "uiRevealLastReason=\(events.last(where: { $0.name == "uiRevealDecision" })?.fields["reason"] ?? "-")",
            "uiRevealResetCount=\(events.last(where: { $0.name == "uiRevealDecision" })?.fields["resetCount"] ?? "-")",
            "uiRevealTimeoutFallback=\(events.contains(where: { $0.name == "uiRevealDecision" }) ? String(events.contains(where: { $0.name == "uiRevealDecision" && $0.fields["decision"] == "timeoutFallback" })) : "-")",
            "terminal=\(terminal)",
            "events=\(eventNames)",
        ]

        parts.append(contentsOf: [
            "pauseStartedAt=\(resumeEvent?.fields["pauseStartedAt"] ?? "-")",
            "currentTime=\(resumeEvent?.fields["currentTime"] ?? "-")",
            "bufferAheadAtResume=\(resumeEvent?.fields["bufferAheadAtResume"] ?? "-")",
            "bufferCoveredAtResume=\(resumeEvent?.fields["bufferCoveredAtResume"] ?? "-")",
            "rawTarget=\(seekRequested?.fields["rawTarget"] ?? "-")",
            "wasPlayingBeforeSeek=\(seekRequested?.fields["wasPlayingBeforeSeek"] ?? "-")",
            "alignedTarget=\(seekAligned?.fields["alignedTarget"] ?? "-")",
            "toleranceBefore=\(seekAligned?.fields["toleranceBefore"] ?? "-")",
            "toleranceAfter=\(seekAligned?.fields["toleranceAfter"] ?? "-")",
        ])
        // Work totals are observational and can overlap UI evaluation time; do not add them.
        for prefix in ["snapshotCopy", "renderedTimeCopy", "frameImageCopy", "debugPollCopy", "frameImageConvert", "blackFrameCheck", "surfaceSnapshot"] {
            for suffix in ["Count", "TotalMs", "MeanMs", "MaxMs"] {
                let key = prefix + suffix
                parts.append("\(key)=\(videoObservation?[key] ?? "-")")
            }
        }
        for key in ["uiEvaluationCount", "uiEvaluationTotalMs", "uiEvaluationMeanMs", "uiEvaluationMaxMs",
                    "uiEvaluationMaxGapMs", "settleDeadlineOvershootMs"] {
            parts.append("\(key)=\(revealTiming?[key] ?? "-")")
        }
        let deadlineToReveal = duration(from: recoveryTraceDouble(revealTiming?["settleDeadlineAt"]), to: uiReveal?.at)
        parts.append("settleDeadlineToUIReveal=\(recoveryTraceDuration(deadlineToReveal))")
        parts.append("uiRevealObservation=\(uiReveal?.fields["observation"] ?? "-")")
        return parts.joined(separator: " ")
    }

    private func summaryFields(_ values: [String: String]) -> String {
        guard !values.isEmpty else { return "-" }
        return values.keys.sorted().compactMap { key in
            guard let value = values[key] else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: ",")
    }

    private func firstEvent(named names: [String], after: Double? = nil) -> Event? {
        events.first { event in
            names.contains(event.name)
                && (after == nil || event.at >= after!)
        }
    }

    private func duration(from start: Double?, to end: Double?) -> Double? {
        guard let start, let end, start.isFinite, end.isFinite, end >= start else { return nil }
        return end - start
    }

    private func normalizedPhase(_ value: String?) -> String? {
        guard let normalized = recoveryTraceNormalized(value) else { return nil }
        switch normalized {
        case "play":
            return "play"
        case "recoversurface":
            return "recoverSurface"
        case "other":
            return "other"
        default:
            return nil
        }
    }

    private func audioActivationDuration(phase: String) -> Double? {
        let starts = events.filter {
            $0.name == "audioSessionActivationStart" && normalizedPhase($0.fields["phase"]) == phase
        }
        let completes = events.filter {
            $0.name == "audioSessionActivationComplete" && normalizedPhase($0.fields["phase"]) == phase
        }
        var completionIndex = 0
        for start in starts {
            while completionIndex < completes.count, completes[completionIndex].at < start.at {
                completionIndex += 1
            }
            guard completionIndex < completes.count else { continue }
            if let result = duration(from: start.at, to: completes[completionIndex].at) {
                return result
            }
            completionIndex += 1
        }
        return nil
    }

    private func orderedAudioActivationDurations() -> [Double] {
        let starts = events.filter { $0.name == "audioSessionActivationStart" }
        let completes = events.filter { $0.name == "audioSessionActivationComplete" }
        var usedCompletions: Set<Int> = []
        var durations: [Double] = []

        for start in starts {
            guard let phase = normalizedPhase(start.fields["phase"]) else { continue }
            guard let completionIndex = completes.indices.first(where: { index in
                !usedCompletions.contains(index)
                    && completes[index].at >= start.at
                    && normalizedPhase(completes[index].fields["phase"]) == phase
            }) else { continue }
            usedCompletions.insert(completionIndex)
            if let result = duration(from: start.at, to: completes[completionIndex].at) {
                durations.append(result)
            }
        }
        return durations
    }

    private func rangeRequest(for event: Event) -> Event? {
        guard let requestID = event.fields["requestID"], requestID != "-" else { return nil }
        return events.first {
            $0.name == "rangeRequested" && $0.fields["requestID"] == requestID
        }
    }

    private func targetPlayerRangeEvents(name: String, track: String) -> [Event] {
        events.filter { event in
            guard event.name == name,
                  recoveryTraceNormalized(event.fields["track"]) == track
            else { return false }
            let request = rangeRequest(for: event)
            let origin = recoveryTraceNormalized(event.fields["origin"])
                ?? recoveryTraceNormalized(request?.fields["origin"])
            guard origin == "player" else { return false }
            if recoveryTraceBoolean(event.fields["target"]) == "true" { return true }
            return recoveryTraceBoolean(request?.fields["target"]) == "true"
        }
    }

    private func rangeSource(for event: Event) -> String {
        RecoveryTraceDiagnostics.rangeSource(event.fields["source"])
    }

    private func targetRangeMetric(track: String) -> (source: String, ttfb: String) {
        guard let request = targetPlayerRangeEvents(name: "rangeRequested", track: track).first,
              let requestID = request.fields["requestID"] else { return ("-", "-") }
        let results = events.filter {
            $0.fields["requestID"] == requestID && ["rangeFirstByte", "rangeComplete", "rangeSource"].contains($0.name)
        }
        let selected = results.first { rangeSource(for: $0) != "unknown" }
        let source = selected.map { rangeSource(for: $0) } ?? "unknown"
        // Never substitute a later request or completion for this request's first byte.
        guard source == "network", let firstByte = results.first(where: {
            $0.name == "rangeFirstByte" && rangeSource(for: $0) == "network"
        }) else { return (source, "-") }
        return (source, recoveryTraceDuration(duration(from: request.at, to: firstByte.at)))
    }

    private func seekWarmSource() -> String {
        let ranges = events.filter { event in
            ["rangeFirstByte", "rangeComplete"].contains(event.name)
                && recoveryTraceNormalized(event.fields["origin"]) == "warm"
        }
        let candidates = ranges.filter { isTargetRange($0) }
        for event in candidates {
            if let raw = event.fields["source"], raw != "-" {
                return RecoveryTraceDiagnostics.rangeSource(raw)
            }
        }
        return "-"
    }

    private func isTargetRange(_ event: Event) -> Bool {
        recoveryTraceBoolean(event.fields["target"]) == "true"
            || recoveryTraceBoolean(rangeRequest(for: event)?.fields["target"]) == "true"
    }

    private func warmAndPlayerSameRange() -> String {
        for event in events.reversed() where isTargetRange(event) && event.fields["origin"] == "player" {
            if let value = recoveryTraceBoolean(event.fields["warmAndPlayerSameRange"]) {
                return value
            }
        }

        let warm = events.filter {
            $0.name == "rangeRequested" && recoveryTraceNormalized($0.fields["origin"]) == "warm"
        }
        let player = events.filter {
            $0.name == "rangeRequested" && recoveryTraceNormalized($0.fields["origin"]) == "player" && isTargetRange($0)
        }
        guard !warm.isEmpty, !player.isEmpty else { return "-" }

        var sawUnknown = false
        for warmEvent in warm {
            for playerEvent in player where warmEvent.fields["track"] == playerEvent.fields["track"] {
                let result = RecoveryTraceDiagnostics.sameRange(
                    warmResource: warmEvent.fields["resource"],
                    warmStart: Int64(warmEvent.fields["start"] ?? ""),
                    warmLength: Int64(warmEvent.fields["length"] ?? ""),
                    playerResource: playerEvent.fields["resource"],
                    playerStart: Int64(playerEvent.fields["start"] ?? ""),
                    playerLength: Int64(playerEvent.fields["length"] ?? "")
                )
                if result == true { return "true" }
                if result == nil { sawUnknown = true }
            }
        }
        return sawUnknown ? "unknown" : "false"
    }

    private func oldRangeStillActiveValue() -> String {
        if let value = recoveryTraceBoolean(fields["oldRangeStillActive"]) {
            return value
        }
        for event in events.reversed() {
            if let value = recoveryTraceBoolean(event.fields["oldRangeStillActive"])
                ?? recoveryTraceBoolean(event.fields["active"])
            {
                return value
            }
            if event.name == "oldRangeStillActive",
               let value = recoveryTraceBoolean(event.fields["value"])
            {
                return value
            }
        }
        return "-"
    }

    private func waitingReasonValue() -> String {
        for event in events.reversed() where event.name == "waiting" || event.name == "waitingReason" {
            if let reason = event.fields["reason"], reason != "-" {
                return reason
            }
        }
        return "-"
    }

    var exportText: String {
        (events.map { recoveryTraceEventLine(id: id, type: type, event: $0) } + [summary])
            .joined(separator: "\n")
    }
}

private nonisolated func recoveryTraceEventLine(
    id: String,
    type: String,
    event: RecoveryTraceRecord.Event
) -> String {
    let fieldText = event.fields.keys.sorted().compactMap { key in
        guard let value = event.fields[key] else { return nil }
        return "\(key)=\(value)"
    }.joined(separator: ",")
    return "[RecoveryTrace] id=\(id) type=\(type) at=\(recoveryTraceTime(event.at)) event=\(event.name) fields=\(fieldText.isEmpty ? "-" : fieldText)"
}

#if DEBUG
nonisolated final class RecoveryTraceStore: @unchecked Sendable {
    static let shared = RecoveryTraceStore()

    private let lock = NSLock()
    private var records: [String: RecoveryTraceRecord] = [:]
    private var order: [String] = []
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "bili",
        category: "RecoveryTrace"
    )

    init() {}

    func start(
        type: String,
        metricsID: String?,
        at: Double = CACurrentMediaTime(),
        fields: [String: String] = [:]
    ) -> String {
        let id = UUID().uuidString
        var record = RecoveryTraceRecord(
            id: id,
            type: type,
            metricsID: metricsID,
            startedAt: at,
            fields: fields
        )
        let initialEventName: String
        switch type {
        case "manualResume":
            initialEventName = "resumeRequested"
        case "userSeek":
            initialEventName = "seekRequested"
        default:
            initialEventName = "start"
        }
        record.record(name: initialEventName, at: at, fields: fields)
        let initialEventLine = record.events.last.map {
            recoveryTraceEventLine(id: record.id, type: record.type, event: $0)
        }

        lock.lock()
        records[id] = record
        order.append(id)
        if order.count > 80 {
            let removeCount = order.count - 80
            let removedIDs = Array(order.prefix(removeCount))
            order.removeFirst(removeCount)
            for removedID in removedIDs {
                records[removedID] = nil
            }
        }
        lock.unlock()
        if let initialEventLine {
            logger.debug("\(initialEventLine, privacy: .public)")
        }
        return id
    }

    func event(
        _ id: String?,
        _ name: String,
        at: Double = CACurrentMediaTime(),
        fields: [String: String] = [:]
    ) {
        guard let id else { return }

        var eventLine: String?
        var summaryLine: String?
        lock.lock()
        if var record = records[id] {
            record.record(name: name, at: at, fields: fields)
            records[id] = record
            eventLine = recoveryTraceEventLine(id: record.id, type: record.type,
                event: .init(name: name, at: at, fields: fields))
            if shouldLogSummary(for: record, eventName: name) {
                summaryLine = record.summary
            }
        }
        lock.unlock()

        if let eventLine {
            logger.debug("\(eventLine, privacy: .public)")
        }
        if let summaryLine {
            logger.info("\(summaryLine, privacy: .public)")
        }
    }

    func summary(_ id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return records[id]?.summary
    }

    func exportText() -> String {
        lock.lock()
        let exports = order.compactMap { records[$0]?.exportText }
        lock.unlock()
        return exports.joined(separator: "\n")
    }

    private func shouldLogSummary(for record: RecoveryTraceRecord, eventName: String) -> Bool {
        if eventName == "firstNewFrame" && record.type == "manualResume" {
            return true
        }
        if eventName == "uiReveal" && record.type == "userSeek" {
            return true
        }
        if eventName == "firstTargetFrame" && record.type == "userSeek" {
            return true
        }
        return ["cancel", "cancelled", "canceled", "superseded", "sessionEnded"].contains(eventName)
    }
}
#endif
