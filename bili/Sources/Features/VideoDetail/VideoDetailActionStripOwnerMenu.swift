import SwiftUI

/// Uses the system's iOS 26 Liquid Glass menu without a second navigation or follow state.
struct VideoDetailActionStripOwnerMenu: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let owner: VideoOwner
    let side: CGFloat
    let isFollowing: Bool
    let isMutatingFollow: Bool
    let onFollow: () -> Void

    var body: some View {
        Menu {
            VideoOwnerRouteLink(owner: owner) {
                Label("个人空间", systemImage: "person.crop.rectangle")
            }
            .accessibilityIdentifier("video.detail.ownerMenu.space")

            Button(action: onFollow) {
                Label(isFollowing ? "已关注" : "关注",
                      systemImage: isFollowing ? "checkmark" : "person.badge.plus")
            }
            .disabled(isMutatingFollow)
            .accessibilityHint(isFollowing ? "取消关注这位 UP 主" : "关注这位 UP 主")
            .accessibilityIdentifier("video.detail.ownerMenu.follow")
        } label: {
            PlaybackDetailOwnerAvatarImage(
                urlString: owner.face?.normalizedBiliURL(),
                side: side,
                pixelSize: VideoDetailActionStrip.Metrics.avatarPixelSize,
                showsShadow: false,
                showsBorder: false
            )
            .overlay(alignment: .bottomTrailing) {
                followStatusBadge
                    .offset(x: 2, y: 2)
            }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .contentShape(Circle())
        .accessibilityLabel("\(owner.name)，UP 主菜单")
        .accessibilityValue(isFollowing ? "已关注" : "未关注")
        .accessibilityHint("查看个人空间或更改关注状态")
        .accessibilityIdentifier("video.detail.ownerMenu")
    }

    private var followStatusBadge: some View {
        ZStack {
            Circle()
                .fill(VideoDetailTheme.background)
            Circle()
                .fill(isFollowing ? Color.primary.opacity(0.16) : appTintColor)
            Image(systemName: isFollowing ? "checkmark" : "plus")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(isFollowing ? Color.primary.opacity(0.82) : Color.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 16, height: 16)
        .overlay {
            Circle()
                .stroke(VideoDetailTheme.background, lineWidth: 2)
        }
        .animation(.smooth(duration: 0.2), value: isFollowing)
        .accessibilityHidden(true)
    }
}
