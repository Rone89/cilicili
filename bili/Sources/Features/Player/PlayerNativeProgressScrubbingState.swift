import SwiftUI

struct PlayerNativeProgressScrubbingState {
    var editingProgress = 0.0
    var isEditing = false
    var hasReportedScrubStart = false

    mutating func beginScrub(
        at progress: Double,
        canSeek: Bool,
        onScrubStart: (Double) -> Void
    ) {
        guard canSeek else { return }
        let clampedProgress = min(max(progress, 0), 1)
        if !hasReportedScrubStart {
            hasReportedScrubStart = true
            isEditing = true
            editingProgress = clampedProgress
            onScrubStart(clampedProgress)
        } else {
            isEditing = true
            editingProgress = clampedProgress
        }
    }

    mutating func finishScrub(
        at progress: Double,
        canSeek: Bool,
        onScrubEnded: (Double) -> Void
    ) {
        guard canSeek else { return }
        let clampedProgress = min(max(progress, 0), 1)
        editingProgress = clampedProgress
        hasReportedScrubStart = false
        isEditing = false
        onScrubEnded(clampedProgress)
    }

    mutating func reset() {
        hasReportedScrubStart = false
        isEditing = false
    }
}
