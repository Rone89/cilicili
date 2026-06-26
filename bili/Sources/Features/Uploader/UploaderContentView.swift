import SwiftUI

struct UploaderContentView: View {
    let owner: VideoOwner
    @ObservedObject var viewModel: UploaderViewModel

    @State private var contentWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            UploaderContentWidthReader()

            VStack(alignment: .leading, spacing: 18) {
                UploaderHeaderView(owner: owner, viewModel: viewModel)

                Text("投稿")
                    .font(.headline)
                    .padding(.horizontal)

                videoContent
            }
            .padding(.vertical, 12)
        }
        .onPreferenceChange(UploaderContentWidthPreferenceKey.self, perform: updateContentWidth)
        .overlay {
            if case .failed(let message) = viewModel.state, viewModel.videos.isEmpty {
                ErrorStateView(title: "UP 主加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
                .background(.background.opacity(0.95))
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadInitial()
        }
    }

    private var videoContent: some View {
        UploaderVideosSection(viewModel: viewModel, gridCoverSize: gridCoverSize)
    }

    private var gridCoverSize: CGSize? {
        let gridHorizontalPadding: CGFloat = 24
        let columnSpacing: CGFloat = 12
        let width = (contentWidth - gridHorizontalPadding - columnSpacing) / 2
        guard width > 0 else { return nil }
        return CGSize(width: width, height: width * 9 / 16)
    }

    private func updateContentWidth(_ width: CGFloat) {
        let roundedWidth = width.rounded(.down)
        guard abs(roundedWidth - contentWidth) > 0.5 else { return }
        contentWidth = roundedWidth
    }
}
