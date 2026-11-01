import Foundation

nonisolated enum PlaybackRecoveryTestScenario: String, Codable, CaseIterable, Sendable {
    case pause5, pause30, pause120, nearbySeek, distantSeek, pausedSeek, continuousSeek

    var title: String {
        switch self {
        case .pause5: "暂停5秒后恢复"
        case .pause30: "暂停30秒后恢复"
        case .pause120: "暂停120秒后恢复"
        case .nearbySeek: "近距离跳转"
        case .distantSeek: "远距离跳转"
        case .pausedSeek: "暂停中跳转"
        case .continuousSeek: "连续跳转"
        }
    }

    var pauseSeconds: Double? {
        switch self {
        case .pause5: 5
        case .pause30: 30
        case .pause120: 120
        default: nil
        }
    }
}

nonisolated struct PlaybackRecoveryTestMetric: Codable, Equatable, Sendable {
    let kind: String
    let receivedMilliseconds: Double
    let fields: [String: String]

    static func parse(kind: String, message: String, receivedMilliseconds: Double) -> Self? {
        guard receivedMilliseconds.isFinite, receivedMilliseconds >= 0 else { return nil }
        guard ["manualResume", "seek", "seekRecovery", "failure"].contains(kind) else { return nil }
        if kind == "seek", message.hasPrefix("scrub ") || message.contains("bufferReady") { return nil }
        let keys: Set<String> = [
            "stage", "sampleID", "sampleBuild", "mode", "networkClass", "targetLoadedRange",
            "loadedAheadSeconds", "requestedTargetSeconds", "pauseToPlay", "playToTransport",
            "playToFrame", "pauseToFrame", "total", "engine", "source", "recovered", "frameTime",
            "sampleInterval", "sampleGap", "maxSampleGap", "target", "progress", "budget", "baselineFrame",
        ]
        let numericKeys: Set<String> = [
            "loadedAheadSeconds", "requestedTargetSeconds", "pauseToPlay", "playToTransport",
            "playToFrame", "pauseToFrame", "total", "engine", "frameTime", "sampleInterval",
            "sampleGap", "maxSampleGap", "target", "progress", "budget", "baselineFrame",
        ]
        var fields: [String: String] = [:]
        for token in message.split(whereSeparator: \.isWhitespace) {
            let pair = token.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, keys.contains(String(pair[0])) else { continue }
            let value = String(pair[1])
            guard value.count <= 96,
                  value.allSatisfy({ $0.asciiValue != nil && ($0.isLetter || $0.isNumber || "._-:".contains($0)) }),
                  !value.contains("://")
            else { continue }
            let key = String(pair[0])
            if numericKeys.contains(key), value != "-" {
                let numberText = value.hasSuffix("ms") ? String(value.dropLast(2))
                    : value.hasSuffix("s") ? String(value.dropLast()) : value
                guard let number = Double(numberText), number.isFinite, number >= 0 else { continue }
            }
            fields[key] = value
        }
        if kind == "failure" { fields = ["reason": "playerReportedFailure"] }
        guard !fields.isEmpty else { return nil }
        return Self(kind: kind, receivedMilliseconds: receivedMilliseconds, fields: fields)
    }
}

nonisolated struct PlaybackRecoveryTestTrial: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let scenario: PlaybackRecoveryTestScenario
    let repetition: Int
    var outcome = "running"
    var requestedPauseSeconds: Double?
    var actualPauseMilliseconds: Double?
    var targetProgresses: [Double] = []
    var metrics: [PlaybackRecoveryTestMetric] = []
    var checks: [String: Bool] = [:]
    var reason: String?
}

nonisolated struct PlaybackRecoveryTestReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let runID: UUID
    let startedAt: Date
    var endedAt: Date?
    var status: String
    let context: [String: String]
    let plannedTrialCount: Int
    var trials: [PlaybackRecoveryTestTrial]
    var reason: String?
    let limits: [String]

    init(context: [String: String], plannedTrialCount: Int) {
        schemaVersion = 1
        runID = UUID()
        startedAt = Date()
        status = "running"
        self.context = context
        self.plannedTrialCount = plannedTrialCount
        trials = []
        limits = [
            "Semantic pause/play/native-progress commands; not synthetic touch gestures.",
            "Existing sampled video-output/seek-state evidence; not display presentation or audible-output measurement.",
            "Loaded ranges do not establish disk-cache hits or CDN availability.",
            "receivedMilliseconds is recorder receipt time, not a recovery latency; use the named timing fields.",
            "Superseded continuous-seek metrics are retained; only the last requested target determines completion.",
            "Automatic preparation seeks warm buffers; classify actual evidence, never assume a cold-cache trial.",
            "Observed means required evidence was collected, not that latency or visual/audio quality passed.",
            "Retry/rebuild total timings are attempt-relative and may not include the original seek command.",
        ]
    }

    var exportText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct PlaybackRecoveryTestObservation {
    var available = false
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var wantsPlayback = false
    var isSeeking = false
    var isBuffering = false
    var issue: String?
    // In-memory only. May contain source identity; never copied to reports.
    var sourceIdentity = ""
    var networkClass = "unknown"
}

@MainActor
protocol PlaybackRecoveryTestDriving: AnyObject {
    var observation: PlaybackRecoveryTestObservation { get }
    var reportContext: [String: String] { get }
    var onMetric: (@MainActor (String, String) -> Void)? { get set }
    var onInterrupt: (@MainActor (String) -> Void)? { get set }
    func setTestingActive(_ active: Bool)
    func pause()
    func play()
    func seek(to progress: Double)
}

@MainActor
struct PlaybackRecoveryTestTiming {
    var repetitions = 3
    var settleSeconds = 2.0
    var pausedSeekHoldSeconds = 2.0
    var continuousSeekSpacing = 0.15
    var recoveryTimeout = 10.0
    var preparationTimeout = 20.0
    var pollSeconds = 0.1
    var now: @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }
    var sleep: @MainActor (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
}
