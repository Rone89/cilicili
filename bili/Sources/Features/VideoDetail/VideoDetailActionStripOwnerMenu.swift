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
            .overlay {
                if isFollowing {
                    Circle()
                        .inset(by: -1)
                        .stroke(appTintColor, lineWidth: 2)
                }
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
}
