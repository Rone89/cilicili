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
            VideoDetailActionStripOwnerAvatar(
                owner: model.owner,
                side: layout.avatarImageSide
            )
            .frame(width: layout.avatarColumnWidth, height: layout.rowHeight)

            VideoDetailActionStripFollowControl(
                isFollowing: model.isFollowing,
                canFollow: (model.owner?.mid ?? 0) > 0,
                isMutating: model.isMutatingFollow,
                action: onFollow,
                usesPlainStyle: usesPlainStyle,
                height: layout.followHeight
            )
            .frame(width: layout.followColumnWidth, height: layout.rowHeight)

            VideoDetailActionStripIconButton(
                accessibilityTitle: "点赞",
                systemImage: "hand.thumbsup",
                foregroundStyle: iconForegroundStyle(isSelected: model.isLiked),
                isDisabled: model.isMutatingLike,
                action: onLike,
                usesPlainStyle: usesPlainStyle
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)

            VideoDetailActionStripIconButton(
                accessibilityTitle: "投币",
                systemImage: "bitcoinsign.circle",
                foregroundStyle: iconForegroundStyle(isSelected: model.isCoined),
                isDisabled: model.isMutatingCoin || model.coinCount >= 2,
                action: onCoin,
                usesPlainStyle: usesPlainStyle
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)

            VideoDetailActionStripIconButton(
                accessibilityTitle: model.isFavorited ? "已收藏" : "收藏",
                systemImage: "star",
                foregroundStyle: iconForegroundStyle(isSelected: model.isFavorited),
                isDisabled: model.isMutatingFavorite || !model.canFavorite,
                action: onFavorite,
                usesPlainStyle: usesPlainStyle
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)

            VideoDetailActionStripShareButton(
                shareURL: model.shareURL,
                shareSubject: model.shareSubject,
                shareMessage: model.shareMessage,
                onShareTap: onShareTap,
                usesPlainStyle: usesPlainStyle
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)
        }
    }

    private func iconForegroundStyle(isSelected: Bool) -> Color {
        guard usesPlainStyle else { return isSelected ? appTintColor : .primary }
        return isSelected ? appTintColor : .secondary
    }
}
