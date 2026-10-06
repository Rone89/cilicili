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
}

struct MetalDanmakuRenderStage {
    let transform: DanmakuStageTransform
    /// The actual aspect-fit video rectangle in the MTKView's point coordinates.
    let videoViewport: CGRect
}
