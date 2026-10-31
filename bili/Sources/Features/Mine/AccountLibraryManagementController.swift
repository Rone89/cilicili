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
    @Published private var pendingRetry: PendingRetry?
    private(set) var displayedContexts: [BiliAccountPurpose: LibraryManagementContext] = [:]
    let api: BiliAPIClient

    private struct Step {
        let aids: [Int]
        var action: LibraryVideoManagementAction
        // A removal-only retry can still represent an incomplete move.
        var copiedToTarget = false
    }

    private struct PendingRetry {
        let source: FavoriteFolder?
        let context: LibraryManagementContext
        let steps: [Step]
    }

    init(api: BiliAPIClient) { self.api = api }

    func setDisplayedContext(_ snapshot: BiliAPIClient.RequestSnapshot, purpose: BiliAccountPurpose) {
        if let retry = pendingRetry, retry.context.purpose == purpose,
           (retry.context.snapshot.currentUserMID != snapshot.currentUserMID
            || retry.context.snapshot.cookieHeader != snapshot.cookieHeader
            || retry.context.snapshot.playbackCredentialVersion != snapshot.playbackCredentialVersion) {
            pendingRetry = nil
        }
        displayedContexts[purpose] = LibraryManagementContext(purpose: purpose, snapshot: snapshot)
    }

    func clearDisplayedContext(purpose: BiliAccountPurpose) {
        displayedContexts[purpose] = nil
        if pendingRetry?.context.purpose == purpose { pendingRetry = nil }
    }

    func retryItemCount(source: FavoriteFolder?) -> Int {
        guard let retry = pendingRetry, retry.source?.id == source?.id else { return 0 }
        return retry.steps.reduce(0) { $0 + $1.aids.count }
    }

    func retryUnfinished(source: FavoriteFolder?) async {
        guard !isBusy, let retry = pendingRetry, retry.source?.id == source?.id else { return }
        pendingRetry = nil
        await execute(steps: retry.steps, source: retry.source, context: retry.context)
    }

    func perform(entries: [AccountVideoEntry], source: FavoriteFolder?, action: LibraryVideoManagementAction) async {
        guard !isBusy, !entries.isEmpty else { return }
        pendingRetry = nil
        guard let context = displayedContexts[source == nil ? .historyRead : .interaction] else {
            message = "操作已停止或账号已切换，请检查列表状态"
            return
        }
        let aids = Array(Set(entries.compactMap(\.aid).filter { $0 > 0 })).sorted()
        guard aids.count == entries.count else {
            message = "选择包含无法管理的视频，请重新选择"
            return
        }
        let steps = stride(from: 0, to: aids.count, by: 20).map { start in
            Step(aids: Array(aids[start..<min(start + 20, aids.count)]), action: action)
        }
        await execute(steps: steps, source: source, context: context)
    }

    private func execute(steps: [Step], source: FavoriteFolder?, context: LibraryManagementContext) async {
        isBusy = true
        message = nil
        defer { isBusy = false; batchProgress = nil }
        var remaining = steps
        let total = steps.reduce(0) { $0 + $1.aids.count }
        var result = LibraryBatchResult()
        do {
            guard await api.isCurrentLibraryContext(context) else { throw CancellationError() }
            if let source, !source.canManage(accountMID: context.snapshot.currentUserMID) {
                throw BiliAPIError.api(code: -400, message: "没有管理该收藏夹的权限")
            }
            while let step = remaining.first {
                try Task.checkCancellation()
                let stage: String
                switch step.action {
                case .remove: stage = step.copiedToTarget ? "正在从来源收藏夹移除" : "正在移除"
                case .copy: stage = "正在复制到目标收藏夹"
                case .move: stage = "正在加入目标收藏夹"
                }
                batchProgress = LibraryBatchProgress(completed: result.completed, total: total, stage: stage)
                switch step.action {
                case .remove:
                    if let source {
                        try await api.changeFavoriteResources(aids: step.aids, removeFolderID: source.id, context: context)
                    } else {
                        try await api.removeWatchLater(aids: step.aids, context: context)
                    }
                case .copy(let target), .move(let target):
                    guard let source, target != source.id else { throw BiliAPIError.missingPayload }
                    try await api.changeFavoriteResources(aids: step.aids, addFolderID: target, context: context)
                    if case .move = step.action {
                        // Record the confirmed addition before the next async boundary.
                        // A retry must not add these items to the target again.
                        remaining[0].action = .remove
                        remaining[0].copiedToTarget = true
                        try Task.checkCancellation()
                        batchProgress = LibraryBatchProgress(
                            completed: result.completed, total: total, stage: "正在从来源收藏夹移除"
                        )
                        try await api.changeFavoriteResources(aids: step.aids, removeFolderID: source.id, context: context)
                    }
                }
                result.completed += step.aids.count
                remaining.removeFirst()
                batchProgress = LibraryBatchProgress(completed: result.completed, total: total, stage: stage)
            }
        } catch {
            result.copiedButNotRemoved = remaining.filter(\.copiedToTarget).reduce(0) { $0 + $1.aids.count }
            let contextIsCurrent = await api.isCurrentLibraryContext(context)
            let stopped = error is CancellationError || Task.isCancelled || !contextIsCurrent
            result.failure = stopped ? "操作已停止或账号已切换，请检查列表状态" : error.localizedDescription
            if !stopped, !remaining.isEmpty {
                pendingRetry = PendingRetry(source: source, context: context, steps: remaining)
            }
        }
        message = result.message
    }

    func mutate(purpose: BiliAccountPurpose, operation: (LibraryManagementContext) async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        pendingRetry = nil
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
