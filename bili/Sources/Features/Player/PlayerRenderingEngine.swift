import Foundation
import AVKit
import UIKit

struct PlayerStreamSource: Equatable, Sendable {
    let videoURL: URL?
    let audioURL: URL?
    let videoStream: DASHStream?
    let audioStream: DASHStream?
    let referer: String
    let durationHint: TimeInterval?
    let resumeTime: TimeInterval
}

struct PlayerPlaybackSnapshot: Equatable, Sendable {
    let currentTime: TimeInterval?
    let duration: TimeInterval?
    let isPlaying: Bool
    let isSeekable: Bool
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
protocol PlayerRenderingEngine: AnyObject {
    var hasMedia: Bool { get }
    var needsMediaRecovery: Bool { get }

    func attachSurface(_ surface: UIView)
    func detachSurface(_ surface: UIView)
    func refreshSurfaceLayout()
    func recoverSurface()
    func prepare(source: PlayerStreamSource) async throws
    func play()
    func pause()
    func stop()
    func setPlaybackRate(_ rate: Double)
    func seek(toTime time: TimeInterval) -> TimeInterval?
    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval?
    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval?
    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval?
    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot
    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource?
}
