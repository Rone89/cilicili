import SwiftUI
import UIKit

struct VideoDetailToolbarFollowControl: View {
    @ObservedObject var store: VideoDetailInteractionRenderStore
    let canFollow: Bool
    let action: () -> Void

    var body: some View {
        DetailToolbarFollowButton(
            isFollowing: store.interactionState.isFollowing,
            isLoading: store.isMutatingFollow,
            canFollow: canFollow,
            action: action
        )
    }
}

struct VideoDetailActionStripModel: Equatable {
    let owner: VideoOwner?
    let canFavorite: Bool
    let shareURL: URL?
    let shareSubject: String
    let shareMessage: String
    let contentWidth: CGFloat
    let isFollowing: Bool
    let isLiked: Bool
    let isCoined: Bool
    let isFavorited: Bool
    let coinCount: Int
    let isMutatingLike: Bool
    let isMutatingCoin: Bool
    let isMutatingFavorite: Bool
    let isMutatingFollow: Bool
}

struct VideoDetailActionStripContainer: View {
    @ObservedObject var descriptionStore: VideoDetailDescriptionRenderStore
    @ObservedObject var store: VideoDetailInteractionRenderStore
    let contentWidth: CGFloat
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void

    var body: some View {
        VideoDetailActionStrip(
            model: model,
            onFollow: onFollow,
            onLike: onLike,
            onCoin: onCoin,
            onFavorite: onFavorite,
            onShareTap: onShareTap
        )
        .equatable()
    }

    private var model: VideoDetailActionStripModel {
        let interaction = store.interactionState
        return VideoDetailActionStripModel(
            owner: ownerForDisplay,
            canFavorite: descriptionStore.canFavorite,
            shareURL: descriptionStore.shareURL,
            shareSubject: descriptionStore.shareSubject,
            shareMessage: descriptionStore.shareMessage,
            contentWidth: contentWidth,
            isFollowing: interaction.isFollowing,
            isLiked: interaction.isLiked,
            isCoined: interaction.isCoined,
            isFavorited: interaction.isFavorited,
            coinCount: interaction.coinCount,
            isMutatingLike: store.isMutatingLike,
            isMutatingCoin: store.isMutatingCoin,
            isMutatingFavorite: store.isMutatingFavorite,
            isMutatingFollow: store.isMutatingFollow
        )
    }

    private var ownerForDisplay: VideoOwner? {
        guard let owner = descriptionStore.owner, owner.mid > 0 else { return nil }
        return owner
    }
}

struct VideoDetailActionStrip: View, Equatable {
    private enum Metrics {
        static let columnSpacing: CGFloat = 4
        static let rowHeight: CGFloat = 25
        static let actionLabelSide: CGFloat = 25
        static let avatarImageSide: CGFloat = 32
        static let avatarSide: CGFloat = avatarImageSide
        static let followHeight: CGFloat = actionLabelSide
        static let iconSize: CGFloat = 12
        static let avatarPixelSize = 112
    }

    let model: VideoDetailActionStripModel
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void

    static func == (lhs: VideoDetailActionStrip, rhs: VideoDetailActionStrip) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        let columnSpacing = Metrics.columnSpacing
        let columnWidth = max((model.contentWidth - columnSpacing * 5) / 6, 1)
        let inactiveForeground = Color.primary

        GlassEffectContainer(spacing: columnSpacing) {
            HStack(spacing: columnSpacing) {
                ownerAvatar
                    .frame(width: columnWidth, height: Metrics.rowHeight)

                followButton
                .frame(width: columnWidth, height: Metrics.rowHeight)

                iconAction(
                    accessibilityTitle: "点赞",
                    systemImage: "hand.thumbsup.fill",
                    foregroundStyle: model.isLiked ? .pink : inactiveForeground,
                    isDisabled: model.isMutatingLike,
                    action: onLike
                )
                .frame(width: columnWidth, height: Metrics.rowHeight)

                iconAction(
                    accessibilityTitle: "投币",
                    systemImage: "bitcoinsign.circle.fill",
                    foregroundStyle: model.isCoined ? .pink : inactiveForeground,
                    isDisabled: model.isMutatingCoin || model.coinCount >= 2,
                    action: onCoin
                )
                .frame(width: columnWidth, height: Metrics.rowHeight)

                iconAction(
                    accessibilityTitle: model.isFavorited ? "已收藏" : "收藏",
                    systemImage: "star.fill",
                    foregroundStyle: model.isFavorited ? .pink : inactiveForeground,
                    isDisabled: model.isMutatingFavorite || !model.canFavorite,
                    action: onFavorite
                )
                .frame(width: columnWidth, height: Metrics.rowHeight)

                shareButton
                    .frame(width: columnWidth, height: Metrics.rowHeight)
            }
        }
        .frame(width: model.contentWidth, height: Metrics.rowHeight, alignment: .center)
    }

    @ViewBuilder
    private var ownerAvatar: some View {
        if let owner = model.owner {
            NavigationLink(value: owner) {
                avatarContent(urlString: owner.face?.normalizedBiliURL())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("打开 \(owner.name) 的主页")
        } else {
            avatarContent(urlString: nil)
                .opacity(0.58)
                .accessibilityHidden(true)
        }
    }

    private func avatarContent(urlString: String?) -> some View {
        AvatarRemoteImage(urlString: urlString, pixelSize: Metrics.avatarPixelSize) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: Metrics.avatarImageSide, height: Metrics.avatarImageSide)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2.2)
        .shadow(color: .black.opacity(0.10), radius: 1.2, x: 0, y: 0.6)
        .frame(width: Metrics.avatarSide, height: Metrics.avatarSide)
        .contentShape(Circle())
    }

    private var followButton: some View {
        let isFollowing = model.isFollowing
        let canFollow = (model.owner?.mid ?? 0) > 0

        return Group {
            if isFollowing {
                followButtonContent(isFollowing: true, canFollow: canFollow)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .buttonStyle(.glass)
            } else {
                followButtonContent(isFollowing: false, canFollow: canFollow)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private func followButtonContent(isFollowing: Bool, canFollow: Bool) -> some View {
        Button(action: onFollow) {
            Text(isFollowing ? "已关注" : "关注")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.followHeight)
        }
        .disabled(!canFollow || model.isMutatingFollow)
        .opacity((canFollow && !model.isMutatingFollow) ? 1 : 0.58)
        .accessibilityLabel(isFollowing ? "已关注" : "关注")
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareURL = model.shareURL {
            ShareLink(
                item: shareURL,
                subject: Text(model.shareSubject),
                message: Text(model.shareMessage)
            ) {
                iconContent(
                    systemImage: "square.and.arrow.up",
                    foregroundStyle: .primary
                )
            }
            .buttonBorderShape(.circle)
            .controlSize(.mini)
            .buttonStyle(.glass)
            .contentShape(Circle())
            .simultaneousGesture(TapGesture().onEnded { _ in onShareTap() })
            .accessibilityLabel("分享视频")
        } else {
            iconAction(
                accessibilityTitle: "分享视频",
                systemImage: "square.and.arrow.up",
                foregroundStyle: .secondary,
                isDisabled: true,
                action: {}
            )
        }
    }

    private func iconAction(
        accessibilityTitle: String,
        systemImage: String,
        foregroundStyle: Color,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconContent(
                systemImage: systemImage,
                foregroundStyle: foregroundStyle
            )
        }
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .buttonStyle(.glass)
        .contentShape(Circle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.52 : 1)
        .accessibilityLabel(accessibilityTitle)
    }

    private func iconContent(
        systemImage: String,
        foregroundStyle: Color
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: Metrics.iconSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .frame(width: Metrics.actionLabelSide, height: Metrics.actionLabelSide)
            .foregroundStyle(foregroundStyle)
            .contentShape(Circle())
    }
}

struct VideoDetailInteractionNotice: View {
    @ObservedObject var store: VideoDetailInteractionRenderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = store.playbackFallbackMessage, !message.isEmpty {
                notice(message, systemImage: "sparkles.tv")
            }
            if let message = store.interactionMessage, !message.isEmpty {
                notice(message, systemImage: "exclamationmark.circle")
            }
        }
    }

    private func notice(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VideoDetailPlayURLNotice: View {
    @ObservedObject var placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let retry: () -> Void

    var body: some View {
        if placeholderStore.selectedPlayVariant == nil {
            switch placeholderStore.playURLState {
            case .failed(let message):
                failedNotice(message)
            case .idle where placeholderStore.isDetailLoaded:
                retryButton(title: "加载播放地址", systemImage: "play.rectangle")
            default:
                EmptyView()
            }
        } else if placeholderStore.selectedPlayVariant?.isPlayable == false {
            Label("当前档位暂不可播放", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func failedNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            retryButton(title: "播放地址加载失败，点击重试", systemImage: "arrow.clockwise")

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func retryButton(title: String, systemImage: String) -> some View {
        Button(action: retry) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

struct VideoDetailQualityInlineButton: View {
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void

    var body: some View {
        if store.hasQualityMenu {
            Menu {
                if store.isSwitchingPlayQuality {
                    Button {} label: {
                        Label("正在切换清晰度", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(true)
                }

                ForEach(store.qualityMenuItems) { item in
                    Button {
                        selectPlayVariant(item.variant)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .disabled(item.isDisabled)
                }
            } label: {
                InlineMetadataButtonLabel(
                    title: store.qualityInlineButtonTitle,
                    systemImage: store.qualityButtonSystemImage
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            InlineMetadataButtonLabel(title: "清晰度", systemImage: "slider.horizontal.3")
                .opacity(0.45)
        }
    }
}

struct InlineMetadataButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
        }
        .frame(height: 28)
        .padding(.horizontal, 8)
        .foregroundStyle(.primary)
    }
}
