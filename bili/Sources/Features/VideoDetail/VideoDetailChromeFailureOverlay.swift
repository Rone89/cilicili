import SwiftUI

struct VideoDetailChromeFailureOverlay: View {
    @ObservedObject var placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let retry: () -> Void

    var body: some View {
        VideoDetailFailureOverlay(
            placeholderStore: placeholderStore,
            retry: retry
        )
    }
}
