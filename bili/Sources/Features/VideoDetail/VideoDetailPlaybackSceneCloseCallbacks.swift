import Foundation

@MainActor
struct VideoDetailPlaybackSceneCloseCallbacks {
    let isClosingDetail: () -> Bool
    let markClosingDetail: () -> Void
    let onNavigateBack: () -> Void
}
