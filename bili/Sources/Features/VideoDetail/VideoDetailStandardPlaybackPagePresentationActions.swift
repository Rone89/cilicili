import SwiftUI

struct VideoDetailStandardPlaybackPagePresentationActions {
    let state: Binding<VideoDetailStandardPlaybackPagePresentationState>

    func updateScrollOffset(_ tab: VideoDetailContentTab, _ offset: CGFloat) {
        state.wrappedValue.scroll.update(tab: tab, offset: offset)
    }
}
