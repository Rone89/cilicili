import CoreGraphics

struct DanmakuStageTransform: Equatable {
    let scale: CGFloat
    let translation: CGPoint

    static let identity = DanmakuStageTransform(scale: 1, translation: .zero)

    static func aspectFit(from source: CGSize, into target: CGSize) -> Self {
        guard source.width.isFinite, source.height.isFinite,
              target.width.isFinite, target.height.isFinite,
              source.width > 0, source.height > 0,
              target.width > 0, target.height > 0 else { return .identity }

        let scale = min(target.width / source.width, target.height / source.height)
        return Self(
            scale: scale,
            translation: CGPoint(
                x: (target.width - source.width * scale) / 2,
                y: (target.height - source.height * scale) / 2
            )
        )
    }

    func map(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + translation.x, y: point.y * scale + translation.y)
    }

    func map(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + translation.x,
            y: rect.minY * scale + translation.y,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

enum DanmakuVideoViewport {
    /// Scrolling crosses the whole player window, including pillarboxes. Keep
    /// vertical track placement tied to the picture so letterbox/control insets
    /// and collapsed logical canvases retain their existing behavior.
    static func scrollingCanvas(in bounds: CGRect, aspectRatio: CGFloat?) -> CGRect {
        let picture = aspectFit(in: bounds, aspectRatio: aspectRatio)
        return CGRect(x: bounds.minX, y: picture.minY,
                      width: bounds.width, height: picture.height)
    }

    static func aspectFit(in bounds: CGRect, aspectRatio: CGFloat?) -> CGRect {
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              let aspectRatio, aspectRatio.isFinite, aspectRatio > 0.1 else { return bounds }

        let boundsAspect = bounds.width / bounds.height
        if aspectRatio > boundsAspect {
            let height = bounds.width / aspectRatio
            return CGRect(x: bounds.minX, y: bounds.minY + (bounds.height - height) / 2,
                          width: bounds.width, height: height)
        }

        let width = bounds.height * aspectRatio
        return CGRect(x: bounds.minX + (bounds.width - width) / 2, y: bounds.minY,
                      width: width, height: bounds.height)
    }

    static func insetContentFrame(
        in bounds: CGRect,
        aspectRatio: CGFloat?,
        topInset: CGFloat,
        bottomInset: CGFloat,
        settings: DanmakuKitRenderSettings
    ) -> CGRect {
        let canvas = scrollingCanvas(in: bounds, aspectRatio: aspectRatio)
        let clampedTop = min(max(topInset + CGFloat(settings.topPadding), 0), canvas.height)
        let clampedBottom = min(
            max(bottomInset + CGFloat(settings.bottomPadding), 0),
            max(0, canvas.height - clampedTop)
        )
        return CGRect(
            x: canvas.minX,
            y: canvas.minY + clampedTop,
            width: canvas.width,
            height: max(0, canvas.height - clampedTop - clampedBottom)
        )
    }

    /// 计算全屏态下播放器叠层与控件应遵循的可视区四周边距；竖屏视频全屏时
    /// 额外保证上下至少收拢至屏幕居中的 9:16（宽:高）区域内。
    static func fullscreenContentInsets(
        in size: CGSize,
        videoAspectRatio: CGFloat,
        isPortraitFullscreen: Bool
    ) -> (top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 1, size.height > 1,
              videoAspectRatio.isFinite, videoAspectRatio > 0.1
        else { return (0, 0, 0, 0) }

        let fitted = aspectFit(in: CGRect(origin: .zero, size: size), aspectRatio: videoAspectRatio)
        var verticalInset = max(0, (size.height - fitted.height) / 2)
        let horizontalInset = max(0, (size.width - fitted.width) / 2)
        if isPortraitFullscreen {
            let nineSixteenHeight = min(size.height, size.width * 16.0 / 9.0)
            let nineSixteenInset = max(0, (size.height - nineSixteenHeight) / 2)
            verticalInset = max(verticalInset, nineSixteenInset)
        }
        return (verticalInset, horizontalInset, verticalInset, horizontalInset)
    }
}

struct MetalDanmakuRenderStage {
    let transform: DanmakuStageTransform
    /// Full horizontal scrolling canvas in the MTKView's point coordinates.
    let canvasViewport: CGRect
}
