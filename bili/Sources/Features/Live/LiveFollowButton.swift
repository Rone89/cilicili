import SwiftUI

struct LiveFollowButton: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        if viewModel.isFollowingAnchor {
            LiveFollowButtonContent(viewModel: viewModel, isFollowing: true)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .buttonStyle(.glass)
        } else {
            LiveFollowButtonContent(viewModel: viewModel, isFollowing: false)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .buttonStyle(.glassProminent)
        }
    }
}

private struct LiveFollowButtonContent: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    let isFollowing: Bool

    var body: some View {
        Button(action: toggleFollow) {
            Text(isFollowing ? "已关注" : "关注")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: 25)
        }
        .disabled(viewModel.anchorUIDForFollow == nil || viewModel.isMutatingAnchorFollow)
        .opacity((viewModel.anchorUIDForFollow != nil && !viewModel.isMutatingAnchorFollow) ? 1 : 0.58)
        .accessibilityLabel(isFollowing ? "已关注主播" : "关注主播")
    }

    private func toggleFollow() {
        Haptics.light()
        Task {
            await viewModel.toggleFollowAnchor()
            Haptics.success()
        }
    }
}
