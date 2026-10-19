import Foundation
import SwiftUI

extension HomeViewModel {
    func loadInitial() async {
        guard videos.isEmpty else { return }
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        // Keep the first screen on its skeleton until fresh content arrives.
        // refresh() still restores the snapshot on failure or an empty response.
        state = .loading
        await refresh(resetCursor: true)
    }

    func switchMode(
        _ newMode: HomeFeedMode,
        using nativeRefreshAction: RefreshAction? = nil
    ) async {
        guard mode != newMode else { return }
        requestRevision += 1
        let revision = requestRevision
        cancelRecommendMetadataHydrationTasks()
        let previousMode = mode
        if previousMode == .recommend, !videos.isEmpty {
            retainedRecommendVideos = videos
            retainedRecommendLastSeenMarkerIndex = lastSeenMarkerIndex
        }
        mode = newMode
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        if newMode == .recommend, !retainedRecommendVideos.isEmpty {
            updateFeed(retainedRecommendVideos)
            updateLastSeenMarkerIndex(retainedRecommendLastSeenMarkerIndex)
            state = .loaded
        } else {
            state = .loading
            await restoreCachedVideosIfAvailable()
        }

        guard revision == requestRevision, mode == newMode, !Task.isCancelled else { return }
        guard newMode.requiresRefreshAfterSwitch(
            from: previousMode,
            restoredContent: !videos.isEmpty
        ) else {
            modeSwitchRefreshPending = false
            isRefreshing = false
            isUserRefreshing = false
            return
        }

        guard !Task.isCancelled else { return }
        if let nativeRefreshAction {
            modeSwitchRefreshPending = true
            defer { modeSwitchRefreshPending = false }
            await nativeRefreshAction()
            return
        }

        await refresh(resetCursor: true)
    }

    func reloadForRecommendContextChange() async {
        hiddenRecommendationIDs.removeAll()
        retainedRecommendVideos.removeAll()
        retainedRecommendLastSeenMarkerIndex = nil
        guard mode == .recommend else { return }
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        requestRevision += 1
        let revision = requestRevision
        cancelRecommendMetadataHydrationTasks()
        state = .loading
        await restoreCachedVideosIfAvailable()
        guard revision == requestRevision, !Task.isCancelled else { return }
        await refresh(resetCursor: true)
    }
}
