import SwiftUI

struct VideoDetailPlaybackSceneHostState {
    let chrome: VideoDetailChromeState
    let sheets: VideoDetailSheetState

    init(
        layout: VideoDetailPlaybackSceneLayout,
        showsPerformanceOverlay: Bool,
        sheetState: VideoDetailSheetState
    ) {
        chrome = VideoDetailChromeState(
            hidesSystemChrome: layout.shouldHideSystemChrome,
            showsPerformanceOverlay: showsPerformanceOverlay
        )
        sheets = sheetState
    }
}
