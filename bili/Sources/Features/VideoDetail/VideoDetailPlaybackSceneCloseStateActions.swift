import Foundation

@MainActor
struct VideoDetailPlaybackSceneCloseStateActions {
    let isClosingDetail: () -> Bool
    let markClosingDetail: () -> Void
}
