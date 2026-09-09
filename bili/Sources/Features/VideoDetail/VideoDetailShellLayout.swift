import CoreGraphics
import Foundation

/// 详情页播放器和内容区共享的几何模型。
///
/// 该类型不持有 View，也不触发状态写回。SwiftUI 内容区只消费
/// `contentTopInset`，UIKit surface 只消费 `playerFrame`，从而避免滚动时
/// 通过重建内容树反馈播放器高度。
@MainActor
struct VideoDetailShellLayout: Equatable {
    static let collapsedToolbarHeight: CGFloat = 54

    let playerFrame: CGRect
    let contentFrame: CGRect
    let contentTopInset: CGFloat?
    let usesFullscreenLayout: Bool

    static func standardPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        (max(width, 0) * 9 / 16).rounded()
    }

    static func expandedPlayerHeight(
        bounds: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGFloat {
        let standard = standardPlayerHeight(forWidth: bounds.width)
        guard videoAspectRatio < 0.9 else { return standard }
        let proposed = max(bounds.height * 0.65, bounds.width)
        let maximum = max(standard, bounds.height * 0.72)
        return max(standard, min(proposed, maximum))
    }

    static func minimumPlayerHeight(
        forWidth width: CGFloat,
        isPlaybackActive: Bool
    ) -> CGFloat {
        isPlaybackActive ? standardPlayerHeight(forWidth: width) : collapsedToolbarHeight
    }

    static func resolvedPlayerHeight(
        bounds: CGSize,
        videoAspectRatio: CGFloat,
        currentPlayerHeight: CGFloat?,
        isPlaybackActive: Bool
    ) -> CGFloat {
        let expanded = expandedPlayerHeight(
            bounds: bounds,
            videoAspectRatio: videoAspectRatio
        )
        let minimum = minimumPlayerHeight(
            forWidth: bounds.width,
            isPlaybackActive: isPlaybackActive
        )
        return max(minimum, min(currentPlayerHeight ?? expanded, expanded))
    }

    static func resolve(
        bounds: CGRect,
        safeAreaTop: CGFloat,
        videoAspectRatio: CGFloat,
        currentPlayerHeight: CGFloat?,
        isPlaybackActive: Bool,
        isPortraitFullscreen: Bool
    ) -> Self {
        let isLandscape = bounds.width > bounds.height
        let usesFullscreenLayout = isLandscape || isPortraitFullscreen
        let expanded = expandedPlayerHeight(
            bounds: bounds.size,
            videoAspectRatio: videoAspectRatio
        )
        let playerHeight =
            usesFullscreenLayout
            ? bounds.height
            : resolvedPlayerHeight(
                bounds: bounds.size,
                videoAspectRatio: videoAspectRatio,
                currentPlayerHeight: currentPlayerHeight,
                isPlaybackActive: isPlaybackActive
            )
        let topInset = min(max(safeAreaTop, 0), bounds.height)

        if usesFullscreenLayout {
            return Self(
                playerFrame: bounds,
                contentFrame: CGRect(
                    x: bounds.minX,
                    y: bounds.maxY,
                    width: bounds.width,
                    height: max(bounds.height, 1)
                ),
                contentTopInset: nil,
                usesFullscreenLayout: true
            )
        }

        return Self(
            playerFrame: CGRect(
                x: bounds.minX,
                y: bounds.minY + topInset,
                width: bounds.width,
                height: max(playerHeight, 0)
            ),
            contentFrame: CGRect(
                x: bounds.minX,
                y: bounds.minY + topInset,
                width: bounds.width,
                height: max(bounds.height - topInset, 0)
            ),
            contentTopInset: max(expanded, 0),
            usesFullscreenLayout: false
        )
    }
}
