import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func addCoin() async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法投币"
            return false
        }
        guard interactionState.coinCount < 2 else {
            interactionMessage = "这个视频已经投过 2 枚币了"
            return false
        }
        let bvid = detail.bvid
        let shouldLike = interactionState.isLiked
        return await performInteractionMutation(
            .coin,
            isCurrent: { isCurrentVideoContext(aid: aid, bvid: bvid) }
        ) {
            try await api.addVideoCoin(aid: aid, selectLike: shouldLike)
            guard isCurrentVideoContext(aid: aid, bvid: bvid) else { throw CancellationError() }
            interactionState.coinCount += 1
        }
    }
}
