import Foundation

extension VideoDetailViewModel {
    /// - Parameter timeout: 首屏用 15s 兜底（对齐 gRPC 的 `grpc-timeout: 15S`）；
    ///   分页传 nil 不设硬超时——硬超时会取消正在重试的 gRPC 请求，把“慢”变成
    ///   “失败”，而 PiliPlus/PiliPod 的分页都没有硬超时。
    func fetchCommentsWithTimeout(
        target: VideoDetailCommentTarget,
        cursor: String,
        sort: CommentSort,
        timeout: TimeInterval?
    ) async throws -> CommentPage {
        guard let timeout else {
            return try await api.fetchComments(
                oid: target.oid,
                type: target.type,
                cursor: cursor,
                sort: sort
            )
        }
        return try await withThrowingTaskGroup(of: CommentPage.self) { group in
            group.addTask(priority: .userInitiated) {
                try await self.api.fetchComments(
                    oid: target.oid,
                    type: target.type,
                    cursor: cursor,
                    sort: sort
                )
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw BiliAPIError.api(code: -1, message: "评论加载超时，请稍后重试")
            }
            guard let page = try await group.next() else {
                group.cancelAll()
                throw BiliAPIError.emptyData
            }
            group.cancelAll()
            return page
        }
    }
}
