@MainActor
struct VideoDetailPlaybackSceneCloseActions {
    let state: VideoDetailPlaybackSceneCloseStateActions
    let navigation: VideoDetailPlaybackSceneCloseNavigationActions

    func dismissVideoDetail() {
        navigation.dismissVideoDetail(using: state)
    }
}
