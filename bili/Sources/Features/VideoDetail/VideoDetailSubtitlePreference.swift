import Foundation

/// 字幕自动选轨偏好，四档语义对齐 PiliPlus 的 subtitlePreference。
enum VideoSubtitlePreference: String, CaseIterable, Identifiable, Sendable {
    /// 默认不显示字幕。
    case off
    /// 优先真人字幕，没有真人字幕时使用 AI 字幕。
    case preferHuman
    /// 仅真人字幕，跳过 AI 字幕。
    case humanOnly
    /// 有人声（真人）字幕时总是开启；仅有 AI 字幕时静音才开启。
    case autoWhenMuted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "关闭"
        case .preferHuman:
            return "优先真人字幕"
        case .humanOnly:
            return "仅真人字幕"
        case .autoWhenMuted:
            return "静音时自动开启"
        }
    }

    var subtitle: String {
        switch self {
        case .off:
            return "不自动显示字幕，可在播放器字幕按钮中手动开启"
        case .preferHuman:
            return "有真人字幕用真人，否则使用 AI 字幕"
        case .humanOnly:
            return "跳过 AI 字幕，只显示人工字幕"
        case .autoWhenMuted:
            return "真人字幕总是开启；仅有 AI 字幕时静音才开启"
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            return "captions.bbox.slash"
        case .preferHuman:
            return "captions.bbox.fill"
        case .humanOnly:
            return "captions.bbox"
        case .autoWhenMuted:
            return "speaker.slash.fill"
        }
    }

    /// 在已排序的字幕轨中按偏好选出默认轨。
    func preferredTrack(in tracks: [VideoSubtitleTrack], isMuted: Bool) -> VideoSubtitleTrack? {
        switch self {
        case .off:
            return nil
        case .preferHuman:
            return tracks.first(where: { !$0.isAI }) ?? tracks.first
        case .humanOnly:
            return tracks.first(where: { !$0.isAI })
        case .autoWhenMuted:
            if let human = tracks.first(where: { !$0.isAI }) {
                return human
            }
            return isMuted ? tracks.first : nil
        }
    }

    /// 轨列表排序（对齐 PiliPlus）：中文先于其他语言，同语言内真人先于 AI；同组内保持接口顺序。
    static func sortedTracks(_ tracks: [VideoSubtitleTrack]) -> [VideoSubtitleTrack] {
        tracks.enumerated().sorted { lhs, rhs in
            let leftIsChinese = lhs.element.lan.contains("zh")
            let rightIsChinese = rhs.element.lan.contains("zh")
            if leftIsChinese != rightIsChinese {
                return leftIsChinese
            }
            if lhs.element.isAI != rhs.element.isAI {
                return !lhs.element.isAI
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }
}
