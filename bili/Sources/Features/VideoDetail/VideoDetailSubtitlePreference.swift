import Foundation

/// 字幕自动选轨偏好，严格对齐 PiliPlus 的 `SubtitlePrefType`：
/// `off` / `on` / `withoutAi` / `auto`。
///
/// 选轨都以排序后的第一条为准（中文优先，同语言真人先于 AI），
/// 与 PiliPlus `subtitle.subtitles` 的排序 + `switch` 保持一致。
enum VideoSubtitlePreference: String, CaseIterable, Identifiable, Sendable {
    /// 默认不显示字幕。
    case off
    /// PiliPlus `on`：优先选择非自动生成（AI）字幕——直接取首选轨。
    case preferNonAI
    /// PiliPlus `withoutAi`：首选轨是 AI 时关闭字幕，否则取首选轨。
    case withoutAI
    /// PiliPlus `auto`：静音时等同 `on`，非静音时等同 `withoutAi`。
    case autoWhenMuted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "关闭"
        case .preferNonAI:
            return "优先非AI字幕"
        case .withoutAI:
            return "跳过AI字幕"
        case .autoWhenMuted:
            return "静音时自动"
        }
    }

    var subtitle: String {
        switch self {
        case .off:
            return "默认不显示字幕，可在播放器字幕按钮中手动开启"
        case .preferNonAI:
            return "优先选择非自动生成（AI）字幕"
        case .withoutAI:
            return "跳过自动生成（AI）字幕；首选轨是 AI 时不显示字幕"
        case .autoWhenMuted:
            return "静音时等同「优先非AI」，非静音时等同「跳过AI」"
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            return "captions.bubble"
        case .preferNonAI:
            return "captions.bubble.fill"
        case .withoutAI:
            return "captions.bubble"
        case .autoWhenMuted:
            return "speaker.slash.fill"
        }
    }

    /// 在已排序的字幕轨中按偏好选出默认轨（排列顺序与 PiliPlus 相同）。
    func preferredTrack(in tracks: [VideoSubtitleTrack], isMuted: Bool) -> VideoSubtitleTrack? {
        guard let first = tracks.first else { return nil }
        switch self {
        case .off:
            return nil
        case .preferNonAI:
            return first
        case .withoutAI:
            return first.isAI ? nil : first
        case .autoWhenMuted:
            return (!first.isAI || isMuted) ? first : nil
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
