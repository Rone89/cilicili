import SwiftUI

extension HomeVisiblePreloadRegistry {
    mutating func register(_ video: VideoItem, index: Int) {
        if var candidate = visiblePreloadCandidates[video.bvid] {
            candidate.video = video
            candidate.index = index
            visiblePreloadCandidates[video.bvid] = candidate
        } else {
            visiblePreloadSequence += 1
            visiblePreloadCandidates[video.bvid] = HomeVisiblePreloadCandidate(
                video: video,
                index: index,
                frame: latestVisibleFrames[video.bvid],
                sequence: visiblePreloadSequence
            )
        }
        trimCandidatesIfNeeded()
    }

    mutating func updateFrames(_ frames: [HomeVisibleVideoFrame]) -> Bool {
        var didUpdate = false
        for frame in frames {
            latestVisibleFrames[frame.bvid] = frame
            guard var candidate = visiblePreloadCandidates[frame.bvid] else { continue }
            if candidate.frame != frame || candidate.index != frame.index {
                candidate.frame = frame
                candidate.index = frame.index
                visiblePreloadCandidates[frame.bvid] = candidate
                didUpdate = true
            }
        }
        guard didUpdate else { return false }
        trimCandidatesIfNeeded()
        return true
    }
}
