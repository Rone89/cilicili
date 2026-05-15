import Foundation
import Combine
import AVFoundation
import AVKit
import OSLog
import UIKit

struct PlayerStreamSource: Equatable, Sendable {
    let metricsID: String
    let videoURL: URL?
    let audioURL: URL?
    let videoStream: DASHStream?
    let audioStream: DASHStream?
    let referer: String
    let httpHeaders: [String: String]
    let title: String
    let durationHint: TimeInterval?
    let resumeTime: TimeInterval
    let dynamicRange: BiliVideoDynamicRange
    let cdnPreference: PlaybackCDNPreference
}

struct PlayerPlaybackSnapshot: Equatable, Sendable {
    let currentTime: TimeInterval?
    let duration: TimeInterval?
    let isPlaying: Bool
    let isSeekable: Bool
}

enum PlayerEnginePlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case buffering
    case playing
    case paused
    case ended
    case failed(String?)
}

enum PlayerEngineError: LocalizedError {
    case missingVideoURL
    case unsupportedMedia

    var errorDescription: String? {
        switch self {
        case .missingVideoURL:
            return "没有可播放的视频地址"
        case .unsupportedMedia:
            return "当前视频流暂不支持播放"
        }
    }
}

@MainActor
protocol PlayerHostFullscreenExitTarget: AnyObject {
    func exitHostFullscreen()
}

@MainActor
protocol PlayerRenderingEngine: AnyObject {
    var hasMedia: Bool { get }
    var needsMediaRecovery: Bool { get }
    var playbackErrorMessage: String? { get }
    var supportsPictureInPicture: Bool { get }
    var isPictureInPictureActive: Bool { get }
    var usesNativePlaybackControls: Bool { get }
    var volume: Float { get }
    var isMuted: Bool { get }
    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)? { get set }
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)? { get set }
    var onLoadingProgressChange: (@MainActor (Double) -> Void)? { get set }
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)? { get set }

    func attachSurface(_ surface: UIView)
    func detachSurface(_ surface: UIView)
    func refreshSurfaceLayout()
    func recoverSurface()
    func setViewModel(_ viewModel: PlayerStateViewModel?)
    func setVideoGravity(_ gravity: AVLayerVideoGravity)
    func attachNativePlaybackController(_ controller: AVPlayerViewController)
    func detachNativePlaybackController(_ controller: AVPlayerViewController)
    func setHostFullscreenActive(_ isActive: Bool, exitTarget: PlayerHostFullscreenExitTarget?)
    func prepare(source: PlayerStreamSource) async throws
    func play()
    func pause()
    func stop()
    func setPlaybackRate(_ rate: Double)
    func setVolume(_ volume: Float)
    func setMuted(_ isMuted: Bool)
    func seek(toTime time: TimeInterval) -> TimeInterval?
    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval?
    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval?
    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval?
    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot
    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource?
    func togglePictureInPicture()
    func invalidatePictureInPicturePlaybackState()
}

enum PlayerMetricsLog {
    nonisolated static let logger = Logger(subsystem: "cc.bili", category: "PlayerMetrics")

    @MainActor
    static func record(_ event: PlayerPerformanceEvent.Kind, metricsID: String, title: String? = nil, message: String? = nil) {
        PlayerPerformanceStore.shared.record(event, metricsID: metricsID, title: title, message: message)
    }

    nonisolated static func elapsedMilliseconds(since start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) * 1000
    }

    nonisolated static func shortTitle(_ title: String) -> String {
        let trimmed = title.replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= 36 {
            return trimmed
        }
        return "\(trimmed.prefix(36))..."
    }
}

struct PlayerPerformanceEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case routeOpen
        case detailLoadStart
        case detailLoaded
        case playURLStart
        case playURLLoaded
        case playerCreated
        case prepareRequested
        case mediaPrepared
        case prepareReturned
        case playRequested
        case firstFrame
        case buffering
        case failed
        case network
        case mediaCache
        case manifestStage
        case qualitySupplement

        var title: String {
            switch self {
            case .manifestStage: return "Manifest"
            case .qualitySupplement: return "Supplement"
            case .routeOpen: return "打开视频"
            case .detailLoadStart: return "详情开始"
            case .detailLoaded: return "详情完成"
            case .playURLStart: return "播放地址开始"
            case .playURLLoaded: return "播放地址完成"
            case .playerCreated: return "播放器创建"
            case .prepareRequested: return "Prepare 开始"
            case .mediaPrepared: return "媒体准备完成"
            case .prepareReturned: return "Prepare 返回"
            case .playRequested: return "播放请求"
            case .firstFrame: return "首帧"
            case .buffering: return "缓冲"
            case .failed: return "失败"
            case .network: return "网络"
            case .mediaCache: return "媒体缓存"
            }
        }
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let metricsID: String
    let title: String?
    let message: String?
}

struct PlayerPerformanceSession: Identifiable, Equatable {
    let id: String
    var metricsID: String { id }
    var title: String?
    var openedAt: Date?
    var detailStartedAt: Date?
    var playURLStartedAt: Date?
    var prepareStartedAt: Date?
    var lastUpdatedAt = Date()
    var eventCount = 0
    var detailLoadMilliseconds: Int?
    var playURLMilliseconds: Int?
    var mediaPreparedMilliseconds: Int?
    var prepareMilliseconds: Int?
    var firstFrameTotalMilliseconds: Int?
    var firstFramePlayerMilliseconds: Int?
    var bufferCount = 0
    var lastBufferMessage: String?
    var networkMessage: String?
    var mediaCacheMessage: String?
    var manifestStageMessage: String?
    var qualitySupplementMessage: String?
    var cdnHostMessage: String?
    var selectedQualityMessage: String?
    var detailSourceMessage: String?
    var prepareStageMessage: String?
    var failureMessage: String?
}

struct PlayerPlaybackAdaptationProfile: Equatable, Sendable {
    enum Level: Int, Sendable {
        case normal = 0
        case fallback = 1
        case cautious = 2
        case slow = 3

        var startupQualityCeiling: Int? {
            switch self {
            case .normal, .fallback:
                return nil
            case .cautious:
                return 80
            case .slow:
                return 64
            }
        }

        var shouldAllowStartupCacheFallback: Bool {
            self != .normal
        }

        var shouldWarmSupplementalVariants: Bool {
            self == .normal
        }

        var shouldRefreshPlaybackCDNProbe: Bool {
            self.rawValue >= Level.cautious.rawValue
        }

        var danmakuLoadFactor: Double {
            switch self {
            case .normal:
                return 1.0
            case .fallback:
                return 0.86
            case .cautious:
                return 0.68
            case .slow:
                return 0.5
            }
        }
    }

    let level: Level
    let isEnabled: Bool

    init(level: Level, isEnabled: Bool = true) {
        self.level = isEnabled ? level : .normal
        self.isEnabled = isEnabled
    }

    var startupQualityCeiling: Int? {
        isEnabled ? level.startupQualityCeiling : nil
    }

    var shouldAllowStartupCacheFallback: Bool {
        isEnabled && level.shouldAllowStartupCacheFallback
    }

    var shouldWarmSupplementalVariants: Bool {
        !isEnabled || level.shouldWarmSupplementalVariants
    }

    var shouldRefreshPlaybackCDNProbe: Bool {
        isEnabled && level.shouldRefreshPlaybackCDNProbe
    }

    var danmakuLoadFactor: Double {
        isEnabled ? level.danmakuLoadFactor : 1.0
    }

    var shouldThrottleBackgroundPreload: Bool {
        isEnabled && level.rawValue >= Level.cautious.rawValue
    }

    var backgroundPreloadLimit: Int {
        guard isEnabled else { return 3 }
        switch level {
        case .normal:
            return 3
        case .fallback:
            return 2
        case .cautious:
            return 1
        case .slow:
            return 0
        }
    }
}

@MainActor
final class PlayerPerformanceStore: ObservableObject {
    static let shared = PlayerPerformanceStore()

    @Published private(set) var events: [PlayerPerformanceEvent] = []
    @Published private(set) var sessions: [PlayerPerformanceSession] = []
    private let maxEventCount = 160
    private let maxSessionCount = 24
    private var sessionsByID: [String: PlayerPerformanceSession] = [:]

    private init() {}

    func record(
        _ kind: PlayerPerformanceEvent.Kind,
        metricsID: String,
        title: String? = nil,
        message: String? = nil
    ) {
        let event = PlayerPerformanceEvent(kind: kind, metricsID: metricsID, title: title, message: message)
        events.append(event)
        if events.count > maxEventCount {
            events.removeFirst(events.count - maxEventCount)
        }
        updateSession(with: event)
    }

    func session(for metricsID: String) -> PlayerPerformanceSession? {
        sessionsByID[metricsID]
    }

    func mostRecentSession() -> PlayerPerformanceSession? {
        sessions.first
    }

    func adaptivePreferredQuality(for preferredQuality: Int?, metricsID: String? = nil) -> Int? {
        let ceiling = playbackAdaptationProfile(for: metricsID).startupQualityCeiling
        guard let ceiling else { return preferredQuality }
        guard let preferredQuality else { return ceiling }
        return min(preferredQuality, ceiling)
    }

    func adaptivePreferredQuality(
        for preferredQuality: Int?,
        metricsID: String? = nil,
        isEnabled: Bool
    ) -> Int? {
        guard isEnabled else { return preferredQuality }
        return adaptivePreferredQuality(for: preferredQuality, metricsID: metricsID)
    }

    func playbackAdaptationProfile(for metricsID: String? = nil) -> PlayerPlaybackAdaptationProfile {
        playbackAdaptationProfile(for: metricsID, isEnabled: true)
    }

    func playbackAdaptationProfile(
        for metricsID: String? = nil,
        isEnabled: Bool
    ) -> PlayerPlaybackAdaptationProfile {
        guard isEnabled else {
            return PlayerPlaybackAdaptationProfile(level: .normal, isEnabled: false)
        }
        let relevantSessions = relevantPlaybackSessions(for: metricsID)
        let worstLevel = relevantSessions
            .map(Self.adaptationLevel(for:))
            .max { $0.rawValue < $1.rawValue } ?? .normal
        return PlayerPlaybackAdaptationProfile(level: worstLevel, isEnabled: true)
    }

    func shouldRefreshPlaybackCDNProbe(for metricsID: String? = nil) -> Bool {
        playbackAdaptationProfile(for: metricsID).shouldRefreshPlaybackCDNProbe
    }

    func shouldRefreshPlaybackCDNProbe(metricsID: String? = nil, isEnabled: Bool) -> Bool {
        playbackAdaptationProfile(for: metricsID, isEnabled: isEnabled).shouldRefreshPlaybackCDNProbe
    }

    func clear() {
        events.removeAll()
        sessions.removeAll()
        sessionsByID.removeAll()
    }

    private func relevantPlaybackSessions(for metricsID: String?) -> [PlayerPerformanceSession] {
        var candidates = Array(sessions.prefix(3))
        if let metricsID,
           let session = sessionsByID[metricsID],
           !candidates.contains(session) {
            candidates.insert(session, at: 0)
        }
        return candidates
    }

    private nonisolated static func adaptationLevel(for session: PlayerPerformanceSession) -> PlayerPlaybackAdaptationProfile.Level {
        let startupMilliseconds = session.firstFrameTotalMilliseconds
            ?? session.prepareMilliseconds
            ?? session.playURLMilliseconds
            ?? session.detailLoadMilliseconds
            ?? 0
        let playerMilliseconds = session.firstFramePlayerMilliseconds ?? 0

        if startupMilliseconds >= 2_600 || playerMilliseconds >= 2_000 || session.bufferCount >= 2 {
            return .slow
        }
        if startupMilliseconds >= 1_600
            || playerMilliseconds >= 1_400
            || session.bufferCount >= 1
            || session.playURLMilliseconds.map({ $0 >= 1_000 }) == true
            || session.prepareMilliseconds.map({ $0 >= 1_400 }) == true
        {
            return .cautious
        }
        if startupMilliseconds >= 1_100
            || session.playURLMilliseconds.map({ $0 >= 700 }) == true
            || session.prepareMilliseconds.map({ $0 >= 1_000 }) == true
            || session.detailLoadMilliseconds.map({ $0 >= 1_200 }) == true
        {
            return .fallback
        }
        return .normal
    }

    private func updateSession(with event: PlayerPerformanceEvent) {
        var session = sessionsByID[event.metricsID] ?? PlayerPerformanceSession(id: event.metricsID)
        if let title = event.title, !title.isEmpty {
            session.title = title
        }
        session.lastUpdatedAt = event.date
        session.eventCount += 1

        switch event.kind {
        case .routeOpen:
            session.openedAt = session.openedAt ?? event.date
        case .detailLoadStart:
            session.openedAt = session.openedAt ?? event.date
            session.detailStartedAt = event.date
        case .detailLoaded:
            if let start = session.detailStartedAt {
                session.detailLoadMilliseconds = Self.milliseconds(from: start, to: event.date)
            }
            session.detailSourceMessage = event.message ?? session.detailSourceMessage
        case .playURLStart:
            session.playURLStartedAt = event.date
        case .playURLLoaded:
            if let start = session.playURLStartedAt {
                session.playURLMilliseconds = Self.milliseconds(from: start, to: event.date)
            }
            session.selectedQualityMessage = event.message ?? session.selectedQualityMessage
        case .playerCreated:
            if let message = event.message, !message.isEmpty {
                session.selectedQualityMessage = message
            }
        case .prepareRequested:
            session.prepareStartedAt = event.date
        case .mediaPrepared:
            session.mediaPreparedMilliseconds = Self.firstMilliseconds(in: event.message)
            session.prepareStageMessage = event.message ?? session.prepareStageMessage
        case .prepareReturned:
            if let start = session.prepareStartedAt {
                session.prepareMilliseconds = Self.milliseconds(from: start, to: event.date)
            } else {
                session.prepareMilliseconds = Self.firstMilliseconds(in: event.message)
            }
        case .playRequested:
            break
        case .firstFrame:
            let openedAt = session.openedAt ?? session.detailStartedAt ?? session.prepareStartedAt
            if let openedAt {
                let total = Self.milliseconds(from: openedAt, to: event.date)
                if session.firstFrameTotalMilliseconds.map({ total < $0 }) ?? true {
                    session.firstFrameTotalMilliseconds = total
                }
            }
            if let playerMilliseconds = Self.firstMilliseconds(in: event.message),
               session.firstFramePlayerMilliseconds.map({ playerMilliseconds < $0 }) ?? true {
                session.firstFramePlayerMilliseconds = playerMilliseconds
            }
        case .buffering:
            session.bufferCount += 1
            session.lastBufferMessage = event.message ?? session.lastBufferMessage
        case .network:
            session.networkMessage = event.message ?? session.networkMessage
            if let message = event.message, let host = Self.host(in: message) {
                session.cdnHostMessage = host
            }
        case .mediaCache:
            session.mediaCacheMessage = event.message ?? session.mediaCacheMessage
        case .manifestStage:
            session.manifestStageMessage = Self.appendDiagnosticMessage(
                session.manifestStageMessage,
                event.message,
                maxParts: 6
            )
        case .qualitySupplement:
            session.qualitySupplementMessage = event.message ?? session.qualitySupplementMessage
        case .failed:
            session.failureMessage = event.message
        }

        sessionsByID[event.metricsID] = session
        sessions = sessionsByID.values
            .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
            .prefix(maxSessionCount)
            .map { $0 }
        let keptIDs = Set(sessions.map(\.id))
        sessionsByID = sessionsByID.filter { keptIDs.contains($0.key) }
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) * 1000).rounded())
    }

    private static func firstMilliseconds(in message: String?) -> Int? {
        guard let message else { return nil }
        let pattern = #"(\d+(?:\.\d+)?)ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: message,
                range: NSRange(message.startIndex..., in: message)
              ),
              let range = Range(match.range(at: 1), in: message),
              let value = Double(message[range])
        else { return nil }
        return Int(value.rounded())
    }

    private static func host(in message: String) -> String? {
        let pattern = #"host=([^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: message,
                range: NSRange(message.startIndex..., in: message)
              ),
              let range = Range(match.range(at: 1), in: message)
        else { return nil }
        return String(message[range])
    }

    private static func appendDiagnosticMessage(_ current: String?, _ next: String?, maxParts: Int) -> String? {
        guard let next, !next.isEmpty else { return current }
        var parts = current?.components(separatedBy: " | ") ?? []
        parts.removeAll { $0 == next }
        parts.append(next)
        if parts.count > maxParts {
            parts.removeFirst(parts.count - maxParts)
        }
        return parts.joined(separator: " | ")
    }
}
