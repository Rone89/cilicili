import SwiftUI

extension LiveRoomContentView {
    func liveInlineControlStrip(_ viewModel: LiveRoomViewModel) -> some View {
        LiveInlineControlStrip(
            viewModel: viewModel,
            showDescription: toggleDescriptionSheet
        )
    }

    func liveActionStrip(_ viewModel: LiveRoomViewModel, contentWidth: CGFloat) -> some View {
        LiveActionStrip(viewModel: viewModel, contentWidth: contentWidth)
    }

    @ViewBuilder
    func liveOwnerAvatar(_ viewModel: LiveRoomViewModel) -> some View {
        let owner = viewModel.anchorOwner
        if owner.mid > 0 {
            NavigationLink(value: owner) {
                liveOwnerAvatarContent(urlString: owner.face?.normalizedBiliURL())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("打开 \(owner.name) 的主页")
        } else {
            liveOwnerAvatarContent(urlString: viewModel.anchorFace)
                .opacity(0.58)
                .accessibilityHidden(true)
        }
    }

    func liveOwnerAvatarContent(urlString: String?) -> some View {
        AvatarRemoteImage(urlString: urlString, pixelSize: 112) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2.2)
        .shadow(color: .black.opacity(0.10), radius: 1.2, x: 0, y: 0.6)
        .frame(width: 32, height: 32)
        .contentShape(Circle())
    }

    @ViewBuilder
    func liveFollowButton(_ viewModel: LiveRoomViewModel) -> some View {
        if viewModel.isFollowingAnchor {
            liveFollowButtonContent(viewModel, isFollowing: true)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .buttonStyle(.glass)
        } else {
            liveFollowButtonContent(viewModel, isFollowing: false)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .buttonStyle(.glassProminent)
        }
    }

    func liveFollowButtonContent(_ viewModel: LiveRoomViewModel, isFollowing: Bool) -> some View {
        Button {
            Haptics.light()
            Task {
                await viewModel.toggleFollowAnchor()
                Haptics.success()
            }
        } label: {
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

    func liveActionContent(title: String, systemImage: String, foregroundStyle: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 25)
        .padding(.horizontal, 7)
        .foregroundStyle(foregroundStyle)
        .background(VideoDetailTheme.secondarySurface.opacity(0.92), in: Capsule())
    }

    @ViewBuilder
    func liveStatusNotice(_ viewModel: LiveRoomViewModel) -> some View {
        LiveStatusNotice(viewModel: viewModel)
    }
}
