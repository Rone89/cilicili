import Foundation

struct VideoDetailCoreTaskState {
    var backgroundTasks = [UUID: Task<Void, Never>]()
    var pageLoadingTask: Task<Void, Never>?
    var pageLoadingToken: UUID?
    var detailLoadingTask: Task<Void, Never>?
    var detailLoadingToken: UUID?
    var playURLSupplementTask: Task<Void, Never>?
    var playURLSupplementGeneration = 0
    var playVariantSwitchTask: Task<Void, Never>?
    var commentsLoadingTask: Task<Void, Never>?
    var commentsLoadingToken: UUID?
    var startupPlayURLTask: Task<PlayURLData, Error>?
    var startupPlayURLTaskKey: String?
    var startupPlayURLGeneration = 0
}

extension VideoDetailViewModel {
    var backgroundTasks: [UUID: Task<Void, Never>] {
        get { coreTaskState.backgroundTasks }
        set { coreTaskState.backgroundTasks = newValue }
    }

    var pageLoadingTask: Task<Void, Never>? {
        get { coreTaskState.pageLoadingTask }
        set { coreTaskState.pageLoadingTask = newValue }
    }

    var pageLoadingToken: UUID? {
        get { coreTaskState.pageLoadingToken }
        set { coreTaskState.pageLoadingToken = newValue }
    }

    var detailLoadingTask: Task<Void, Never>? {
        get { coreTaskState.detailLoadingTask }
        set { coreTaskState.detailLoadingTask = newValue }
    }

    var detailLoadingToken: UUID? {
        get { coreTaskState.detailLoadingToken }
        set { coreTaskState.detailLoadingToken = newValue }
    }

    var playURLSupplementTask: Task<Void, Never>? {
        get { coreTaskState.playURLSupplementTask }
        set { coreTaskState.playURLSupplementTask = newValue }
    }

    var playURLSupplementGeneration: Int {
        get { coreTaskState.playURLSupplementGeneration }
        set { coreTaskState.playURLSupplementGeneration = newValue }
    }

    var playVariantSwitchTask: Task<Void, Never>? {
        get { coreTaskState.playVariantSwitchTask }
        set { coreTaskState.playVariantSwitchTask = newValue }
    }

    var commentsLoadingTask: Task<Void, Never>? {
        get { coreTaskState.commentsLoadingTask }
        set { coreTaskState.commentsLoadingTask = newValue }
    }

    var commentsLoadingToken: UUID? {
        get { coreTaskState.commentsLoadingToken }
        set { coreTaskState.commentsLoadingToken = newValue }
    }

    var startupPlayURLTask: Task<PlayURLData, Error>? {
        get { coreTaskState.startupPlayURLTask }
        set { coreTaskState.startupPlayURLTask = newValue }
    }

    var startupPlayURLTaskKey: String? {
        get { coreTaskState.startupPlayURLTaskKey }
        set { coreTaskState.startupPlayURLTaskKey = newValue }
    }

    var startupPlayURLGeneration: Int {
        get { coreTaskState.startupPlayURLGeneration }
        set { coreTaskState.startupPlayURLGeneration = newValue }
    }
}
