import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func toggleLike() async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法点赞"
            return false
        }
        let bvid = detail.bvid
        let targetState = !interactionState.isLiked
        return await performInteractionMutation(
            .like,
            isCurrent: { isCurrentVideoContext(aid: aid, bvid: bvid) }
        ) {
            do {
                try await api.toggleVideoLike(aid: aid, liked: targetState)
                guard isCurrentVideoContext(aid: aid, bvid: bvid) else { throw CancellationError() }
                interactionState.isLiked = targetState
            } catch {
                guard isCurrentVideoContext(aid: aid, bvid: bvid) else { throw CancellationError() }
                guard recoverLikeStateMismatchIfNeeded(error, targetState: targetState) else {
                    throw error
                }
            }
        }
    }

}
