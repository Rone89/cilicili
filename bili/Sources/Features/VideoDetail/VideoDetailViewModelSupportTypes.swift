import Foundation

enum VideoDetailInteractionMutationKind: Equatable {
    case like
    case coin
    case favorite
    case follow
}

enum VideoDetailPlaybackStartupRelease {
    case firstFrame
    case failed
}

struct VideoDetailPlaybackStartupWaiter {
    let acceptsFailure: Bool
    let continuation: CheckedContinuation<VideoDetailPlaybackStartupRelease?, Never>
}

struct VideoDetailSeekWarmupPlan {
    let variants: [PlayVariant]
    let variantLimit: Int
    let pressureReason: String
}
