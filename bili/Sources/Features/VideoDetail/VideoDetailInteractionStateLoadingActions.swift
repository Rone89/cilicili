import Foundation

extension VideoDetailViewModel {
    func loadInteractionState(aid capturedAID: Int? = nil, bvid capturedBVID: String? = nil) async {
        let bvid = capturedBVID ?? detail.bvid
        guard let aid = capturedAID ?? detail.aid else { return }
        do {
            var state = try await api.fetchVideoInteractionState(aid: aid)
            guard !Task.isCancelled,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { return }
            state.isFollowing = uploaderProfile?.following == true
            interactionState = state
            if state.isFavorited {
                let favoriteFolderTask = Task { @MainActor [weak self, aid, bvid = detail.bvid] in
                    guard let self,
                          !self.isPlaybackInvalidatedForNavigation,
                          self.isCurrentVideoContext(aid: aid, bvid: bvid)
                    else { return }
                    await self.loadFavoriteFoldersForCurrentVideo()
                }
                trackBackgroundTask(favoriteFolderTask)
            }
            interactionMessage = nil
        } catch BiliAPIError.missingSESSDATA {
            guard !Task.isCancelled,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { return }
            interactionState.isFollowing = uploaderProfile?.following == true
        } catch {
            guard !Task.isCancelled,
                  isCurrentVideoContext(aid: aid, bvid: bvid)
            else { return }
            interactionMessage = "互动状态同步失败：\(error.localizedDescription)"
        }
    }
}
