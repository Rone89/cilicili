import SwiftUI
import Combine

nonisolated enum LibraryVideoManagementAction: Equatable {
    case remove
    case copy(Int)
    case move(Int)
}

nonisolated struct LibraryBatchResult: Equatable {
    var completed = 0
    var copiedButNotRemoved = 0
    var failure: String?
    var message: String {
        var lines = ["已完成 \(completed) 项"]
        if copiedButNotRemoved > 0 { lines.append("\(copiedButNotRemoved) 项已加入目标收藏夹，但未能从来源移除") }
        if let failure { lines.append("其余操作未完成：\(failure)") }
        return lines.joined(separator: "\n")
    }
}

nonisolated struct LibraryBatchProgress {
    let completed: Int
    let total: Int
    let stage: String
}

@MainActor
final class AccountLibraryManagementController: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var batchProgress: LibraryBatchProgress?
    @Published var message: String?
    private(set) var displayedContexts: [BiliAccountPurpose: LibraryManagementContext] = [:]
    let api: BiliAPIClient

    init(api: BiliAPIClient) { self.api = api }

    func setDisplayedContext(_ snapshot: BiliAPIClient.RequestSnapshot, purpose: BiliAccountPurpose) {
        displayedContexts[purpose] = LibraryManagementContext(purpose: purpose, snapshot: snapshot)
    }
    func clearDisplayedContext(purpose: BiliAccountPurpose) { displayedContexts[purpose] = nil }

    func perform(entries: [AccountVideoEntry], source: FavoriteFolder?, action: LibraryVideoManagementAction) async {
        guard !isBusy, !entries.isEmpty else { return }
        isBusy = true
        defer { isBusy = false; batchProgress = nil }
        var result = LibraryBatchResult()
        do {
            guard let context = displayedContexts[source == nil ? .historyRead : .interaction],
                  await api.isCurrentLibraryContext(context) else { throw CancellationError() }
            if let source, !source.canManage(accountMID: context.snapshot.currentUserMID) {
                throw BiliAPIError.api(code: -400, message: "没有管理该收藏夹的权限")
            }
            let aids = Array(Set(entries.compactMap(\.aid).filter { $0 > 0 })).sorted()
            guard aids.count == entries.count else { throw BiliAPIError.api(code: -400, message: "选择包含无法管理的视频，请重新选择") }
            for start in stride(from: 0, to: aids.count, by: 20) {
                try Task.checkCancellation()
                let batch = Array(aids[start..<min(start + 20, aids.count)])
                let stage: String
                switch action {
                case .remove: stage = "正在移除"
                case .copy: stage = "正在复制到目标收藏夹"
                case .move: stage = "正在加入目标收藏夹"
                }
                batchProgress = LibraryBatchProgress(completed: result.completed, total: aids.count, stage: stage)
                switch action {
                case .remove:
                    if let source {
                        try await api.changeFavoriteResources(aids: batch, removeFolderID: source.id, context: context)
                    } else {
                        try await api.removeWatchLater(aids: batch, context: context)
                    }
                case .copy(let target), .move(let target):
                    guard let source, target != source.id else { throw BiliAPIError.missingPayload }
                    try await api.changeFavoriteResources(aids: batch, addFolderID: target, context: context)
                    if case .move = action {
                        do {
                            try Task.checkCancellation()
                            batchProgress = LibraryBatchProgress(
                                completed: result.completed, total: aids.count, stage: "正在从来源收藏夹移除"
                            )
                            try await api.changeFavoriteResources(aids: batch, removeFolderID: source.id, context: context)
                        } catch {
                            result.copiedButNotRemoved += batch.count
                            throw error
                        }
                    }
                }
                result.completed += batch.count
                batchProgress = LibraryBatchProgress(completed: result.completed, total: aids.count, stage: stage)
            }
        } catch {
            result.failure = error is CancellationError ? "操作已停止或账号已切换，请检查列表状态" : error.localizedDescription
        }
        message = result.message
    }

    func mutate(purpose: BiliAccountPurpose, operation: (LibraryManagementContext) async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let context = try await api.libraryManagementContext(purpose: purpose)
            try await operation(context)
            message = "操作完成"
            return true
        } catch {
            message = error is CancellationError ? "账号已切换，已停止操作" : error.localizedDescription
            return false
        }
    }
}
