import SwiftUI

struct VideoDetailFailureOverlay: View {
    @ObservedObject var placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let retry: () -> Void

    var body: some View {
        if let message = placeholderStore.failedMessage {
            ErrorStateView(
                title: "视频加载失败",
                message: message,
                retry: retry
            )
            .background(.background.opacity(0.95))
        }
    }
}
