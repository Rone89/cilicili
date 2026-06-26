import SwiftUI

struct HomeVisiblePreloadRegistry {
    var visiblePreloadVideos = Set<String>()
    var recentVisiblePreloadVideos = Set<String>()
    var recentVisiblePreloadOrder: [String] = []
    var visiblePreloadCandidates = [String: HomeVisiblePreloadCandidate]()
    var latestVisibleFrames = [String: HomeVisibleVideoFrame]()
    var visiblePreloadSequence = 0
    var viewportHeight: CGFloat = 1
    let recentVisiblePreloadLimit = 18
    let visibleCandidateLimit = 8

    mutating func unregister(_ video: VideoItem) -> Bool {
        visiblePreloadCandidates.removeValue(forKey: video.bvid)
        latestVisibleFrames.removeValue(forKey: video.bvid)
        visiblePreloadVideos.remove(video.bvid)
        return visiblePreloadCandidates.isEmpty
    }

    mutating func updateViewportHeight(_ height: CGFloat) {
        viewportHeight = max(height, 1)
    }

    mutating func markPreloadStarted(for bvid: String) {
        visiblePreloadVideos.insert(bvid)
        rememberVisiblePreload(bvid)
    }

    func score(_ candidate: HomeVisiblePreloadCandidate) -> CGFloat {
        HomeVisiblePreloadScorer.score(candidate, screenHeight: viewportHeight)
    }
}
