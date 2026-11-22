import CoreGraphics
import Foundation
import SwiftUI

/// 详情页播放器和内容区共享的几何模型。
///
/// 该类型不持有 View，也不触发状态写回。SwiftUI 内容区只消费
/// `contentTopInset`，UIKit surface 只消费 `playerFrame`，从而避免滚动时
/// 通过重建内容树反馈播放器高度。
@MainActor
struct VideoDetailShellLayout: Equatable {
    static let collapsedToolbarHeight: CGFloat = 54

    let adaptiveMode: VideoDetailAdaptiveMode
    let playerStageFrame: CGRect
    let playerFrame: CGRect
    /// Scheduling canvas stays expanded while only the visible player window collapses.
    let danmakuCanvasSize: CGSize
    let contentFrame: CGRect
    let contentTopInset: CGFloat?
    let usesFullscreenLayout: Bool

    static func standardPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        (max(width, 0) * 9 / 16).rounded()
    }

    static func supportsInteractiveCollapse(
        videoAspectRatio: CGFloat,
        isPlaybackActive: Bool = false
    ) -> Bool {
        videoAspectRatio > 0 && (!isPlaybackActive || videoAspectRatio < 0.9
            || usesFullWidthAspectRatioVideo(videoAspectRatio: videoAspectRatio))
    }

    static func usesFullWidthAspectRatioVideo(videoAspectRatio: CGFloat) -> Bool {
        videoAspectRatio.isFinite && videoAspectRatio >= 1 && videoAspectRatio < 16.0 / 9
    }

    static func scrollContentMinimumHeight(
        viewportHeight: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) -> CGFloat {
        max(viewportHeight, 0)
            + max(expandedPlayerHeight - minimumPlayerHeight, 0)
    }

    static func interactiveScrollMetrics(
        scrollOffset: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) -> VideoDetailInteractiveScrollMetrics {
        VideoDetailInteractiveScrollMetrics(
            scrollOffset: scrollOffset,
            expandedPlayerHeight: expandedPlayerHeight,
            minimumPlayerHeight: minimumPlayerHeight
        )
    }

    static func expandedPlayerHeight(
        bounds: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGFloat {
        let standard = standardPlayerHeight(forWidth: bounds.width)
        if usesFullWidthAspectRatioVideo(videoAspectRatio: videoAspectRatio) {
            return max(bounds.width, 0) / videoAspectRatio
        }
        guard videoAspectRatio < 0.9 else { return standard }
        let proposed = max(bounds.height * 0.65, bounds.width)
        let maximum = max(standard, bounds.height * 0.72)
        return max(standard, min(proposed, maximum))
    }

    static func minimumPlayerHeight(
        forWidth width: CGFloat,
        isPlaybackActive: Bool,
        videoAspectRatio: CGFloat = 16.0 / 9
    ) -> CGFloat {
        isPlaybackActive || usesFullWidthAspectRatioVideo(videoAspectRatio: videoAspectRatio)
            ? standardPlayerHeight(forWidth: width)
            : collapsedToolbarHeight
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
            isPlaybackActive: isPlaybackActive,
            videoAspectRatio: videoAspectRatio
        )
        return max(minimum, min(currentPlayerHeight ?? expanded, expanded))
    }

    /// - Parameter fullscreenContentFrameSize: 全屏布局（横屏/竖屏全屏）时内容区
    ///   沿用的上一次嵌入布局尺寸。内容区在全屏下不可见（移到屏幕下方、透明），
    ///   尺寸冻结可以避免其中的 UIKit 评论表在旋转时经历宽度变化——宽度一变，
    ///   表格就会清空全部行高缓存并 `reloadData`，回到竖屏后只剩 96pt 估算几何，
    ///   偏移映射失真、出现大段空洞。`nil` 退回随转场缩放的旧行为。
    static func resolve(
        bounds: CGRect,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat = 0,
        videoAspectRatio: CGFloat,
        currentPlayerHeight: CGFloat?,
        isPlaybackActive: Bool,
        isLandscape: Bool,
        isPortraitFullscreen: Bool,
        fullscreenContentFrameSize: CGSize? = nil,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        adaptiveLargeScreenEnabled: Bool = false
    ) -> Self {
        let usesFullscreenLayout = isLandscape || isPortraitFullscreen
        let adaptiveMode = AdaptiveLayoutPolicy.videoDetailMode(
            containerSize: bounds.size,
            horizontalSizeClass: horizontalSizeClass,
            isFullscreenActive: usesFullscreenLayout,
            adaptiveEnabled: adaptiveLargeScreenEnabled
        )

        if usesFullscreenLayout {
            let frozenContentSize = fullscreenContentFrameSize ?? bounds.size
            return Self(
                adaptiveMode: .fullscreen,
                playerStageFrame: bounds,
                playerFrame: bounds,
                danmakuCanvasSize: bounds.size,
                contentFrame: CGRect(
                    x: bounds.minX,
                    y: bounds.maxY,
                    width: frozenContentSize.width,
                    height: max(frozenContentSize.height, 1)
                ),
                contentTopInset: nil,
                usesFullscreenLayout: true
            )
        }

        if adaptiveMode == .twoColumnSplit {
            let split = AdaptiveLayoutPolicy.videoDetailSplitColumnWidths(totalWidth: bounds.width)
            let availableStageHeight = max(bounds.height, 220)
            let clampedAspect = (videoAspectRatio.isFinite && videoAspectRatio > 0)
                ? min(max(videoAspectRatio, 0.72), 2.35)
                : (16.0 / 9.0)
            let idealPlayerHeight = (split.playerColumnWidth / clampedAspect).rounded()
            let playerHeight = min(availableStageHeight, max(idealPlayerHeight, 220))
            let playerY = bounds.minY + max((availableStageHeight - playerHeight) / 2, 0).rounded()
            let playerFrame = CGRect(
                x: bounds.minX,
                y: playerY,
                width: split.playerColumnWidth,
                height: playerHeight
            )
            let playerStageFrame = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: split.playerColumnWidth,
                height: bounds.height
            )
            let contentFrame = CGRect(
                x: bounds.minX + split.playerColumnWidth,
                y: bounds.minY,
                width: split.contentColumnWidth,
                height: max(bounds.height, 0)
            )
            return Self(
                adaptiveMode: .twoColumnSplit,
                playerStageFrame: playerStageFrame,
                playerFrame: playerFrame,
                danmakuCanvasSize: playerFrame.size,
                contentFrame: contentFrame,
                contentTopInset: 0,
                usesFullscreenLayout: false
            )
        }

        let canInteractivelyCollapse = supportsInteractiveCollapse(
            videoAspectRatio: videoAspectRatio,
            isPlaybackActive: isPlaybackActive
        )
        let playerHeight = resolvedPlayerHeight(
            bounds: bounds.size,
            videoAspectRatio: videoAspectRatio,
            currentPlayerHeight: currentPlayerHeight,
            isPlaybackActive: isPlaybackActive
        )
        let playerFrame = CGRect(
            x: bounds.minX,
            y: bounds.minY + max(0, safeAreaTop),
            width: bounds.width,
            height: max(playerHeight, 0)
        )
        return Self(
            adaptiveMode: .compactStacked,
            playerStageFrame: playerFrame,
            playerFrame: playerFrame,
            danmakuCanvasSize: CGSize(
                width: bounds.width,
                height: expandedPlayerHeight(bounds: bounds.size, videoAspectRatio: videoAspectRatio)
            ),
            contentFrame: CGRect(
                x: bounds.minX,
                y: bounds.minY + max(0, safeAreaTop),
                width: bounds.width,
                height: max(bounds.height - max(0, safeAreaTop), 0)
            ),
            contentTopInset: canInteractivelyCollapse
                ? expandedPlayerHeight(
                    bounds: bounds.size,
                    videoAspectRatio: videoAspectRatio
                )
                : max(playerHeight, 0),
            usesFullscreenLayout: false
        )
    }
}

@MainActor
struct VideoDetailInteractiveScrollMetrics: Equatable {
    let scrollOffset: CGFloat
    let collapseOffset: CGFloat
    let contentOffset: CGFloat
    let collapseDistance: CGFloat

    init(
        scrollOffset: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) {
        let normalizedScrollOffset = max(scrollOffset, 0)
        let expandedHeight = max(expandedPlayerHeight, 0)
        let minimumHeight = min(max(minimumPlayerHeight, 0), expandedHeight)
        let distance = max(expandedHeight - minimumHeight, 0)
        self.scrollOffset = normalizedScrollOffset
        collapseOffset = min(normalizedScrollOffset, distance)
        contentOffset = max(normalizedScrollOffset - distance, 0)
        collapseDistance = distance
    }

    var isPlayerCollapsed: Bool {
        collapseOffset >= collapseDistance - 0.5
    }
}
