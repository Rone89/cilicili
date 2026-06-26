import SwiftUI

struct VideoDetailInteractionNotice: View {
    @ObservedObject var store: VideoDetailInteractionRenderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = store.playbackFallbackMessage, !message.isEmpty {
                VideoDetailNoticeLabel(message: message, systemImage: "sparkles.tv")
            }
            if let message = store.interactionMessage, !message.isEmpty {
                VideoDetailNoticeLabel(message: message, systemImage: "exclamationmark.circle")
            }
        }
    }
}
