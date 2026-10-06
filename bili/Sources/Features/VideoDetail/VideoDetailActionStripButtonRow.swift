import SwiftUI

struct VideoDetailActionStripButtonRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let model: VideoDetailActionStripModel
    let layout: VideoDetailActionStripLayout
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void
    let usesPlainStyle: Bool

    var body: some View {
        HStack(spacing: layout.columnSpacing) {
            Group {
                if let owner = model.owner, owner.mid > 0 {
                    VideoDetailActionStripOwnerMenu(
                        owner: owner,
                        side: layout.avatarImageSide,
                        isFollowing: model.isFollowing,
                        isMutatingFollow: model.isMutatingFollow,
                        onFollow: onFollow
                    )
                } else {
                    PlaybackDetailOwnerAvatarImage(
                        urlString: nil,
                        side: layout.avatarImageSide,
                        pixelSize: VideoDetailActionStrip.Metrics.avatarPixelSize,
                        showsShadow: false,
                        showsBorder: false
                    )
                    .accessibilityHidden(true)
                }
            }
            .frame(width: layout.avatarColumnWidth, height: layout.rowHeight)

            VideoDetailActionStripIconButton(
                accessibilityTitle: "点赞",
                systemImage: "hand.thumbsup",
                foregroundStyle: iconForegroundStyle(isSelected: model.isLiked),
                isDisabled: model.isMutatingLike,
                action: onLike,
                usesPlainStyle: usesPlainStyle
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)
            .accessibilityIdentifier("video.detail.like")

            VideoDetailActionStripIconButton(
                accessibilityTitle: "投币",
                systemImage: "bitcoinsign.circle",
                foregroundStyle: iconForegroundStyle(isSelected: model.isCoined),
                isDisabled: model.isMutatingCoin || model.coinCount >= 2,
                action: onCoin,
                usesPlainStyle: usesPlainStyle
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)
            .accessibilityIdentifier("video.detail.coin")

            VideoDetailActionStripIconButton(
                accessibilityTitle: model.isFavorited ? "已收藏" : "收藏",
                systemImage: "star",
                foregroundStyle: iconForegroundStyle(isSelected: model.isFavorited),
                isDisabled: model.isMutatingFavorite || !model.canFavorite,
                action: onFavorite,
                usesPlainStyle: usesPlainStyle
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)
            .accessibilityIdentifier("video.detail.favorite")

            VideoDetailActionStripShareButton(
                shareURL: model.shareURL,
                shareSubject: model.shareSubject,
                shareMessage: model.shareMessage,
                onShareTap: onShareTap,
                usesPlainStyle: usesPlainStyle
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)
            .accessibilityIdentifier("video.detail.share")
        }
    }

    private func iconForegroundStyle(isSelected: Bool) -> Color {
        guard usesPlainStyle else { return isSelected ? appTintColor : .primary }
        return isSelected ? appTintColor : .secondary
    }
}
