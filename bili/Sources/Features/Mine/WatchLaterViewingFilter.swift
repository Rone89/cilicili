import Foundation

nonisolated enum WatchLaterViewingFilter: String, CaseIterable, Identifiable {
    case all
    case resumable
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .resumable: "可继续观看"
        case .completed: "已看完"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "已加载的稍后再看中没有匹配结果"
        case .resumable: "已加载的内容中没有可继续观看的视频"
        case .completed: "已加载的内容中没有已看完的视频"
        }
    }

    func includes(_ entry: AccountVideoEntry) -> Bool {
        switch self {
        case .all: true
        case .resumable: entry.resumeTime != nil
        case .completed: entry.playbackProgress.map { $0 >= 1 } ?? false
        }
    }
}
