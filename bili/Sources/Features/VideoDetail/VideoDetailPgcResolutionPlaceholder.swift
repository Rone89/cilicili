import SwiftUI

struct VideoDetailPgcResolutionPlaceholder: View {
    @ObservedObject var store: VideoDetailPlayerPlaceholderRenderStore
    let episodeID: Int
    let retry: () async -> Void
    @State private var retryRevision = 0
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Color.black
            if let message = store.failedMessage {
                VStack(spacing: 12) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    HStack {
                        Button("重试") {
                            isRetrying = true
                            retryRevision &+= 1
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRetrying || store.isDetailLoading)
                        .accessibilityIdentifier("pgc.detail.retry")
                        if let url = URL(string: "https://www.bilibili.com/bangumi/play/ep\(episodeID)") {
                            AppLinkButton(url: url) { Text("网页查看") }
                        }
                    }
                }
                .padding()
            }
        }
        .task(id: retryRevision) {
            guard retryRevision > 0 else { return }
            defer { isRetrying = false }
            await retry()
        }
    }
}
