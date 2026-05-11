import Foundation
import Combine
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
    let title: String
    let durationHint: TimeInterval?
    let resumeTime: TimeInterval
    let dynamicRange: BiliVideoDynamicRange
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

        var title: String {
            switch self {
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
    var cdnHostMessage: String?
    var selectedQualityMessage: String?
    var failureMessage: String?
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

    func clear() {
        events.removeAll()
        sessions.removeAll()
        sessionsByID.removeAll()
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
}
