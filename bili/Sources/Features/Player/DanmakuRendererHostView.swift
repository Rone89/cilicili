import UIKit

struct DanmakuOverlayConfiguration {
    let items: [DanmakuItem]
    let itemsRevision: Int
    var currentTime: TimeInterval
    let isPlaying: Bool
    let playbackRate: Double
    let isEnabled: Bool
    let hasPresentedPlayback: Bool
    let isLoadShedding: Bool
    let settings: DanmakuSettings
    let topInset: CGFloat
    let bottomInset: CGFloat
    var videoAspectRatio: CGFloat? = nil
}

@MainActor
protocol DanmakuOverlayRendering: AnyObject {
    var isLoadSheddingValue: Bool { get }
    func apply(configuration: DanmakuOverlayConfiguration)
    func synchronizePlaybackTime(_ time: TimeInterval, force: Bool)
    func setLayoutTransitioning(_ transitioning: Bool)
    func stop()
}

extension DanmakuKitOverlayView: DanmakuOverlayRendering {
    func apply(configuration c: DanmakuOverlayConfiguration) {
        apply(items: c.items, itemsRevision: c.itemsRevision, currentTime: c.currentTime,
              isPlaying: c.isPlaying, playbackRate: c.playbackRate, isEnabled: c.isEnabled,
              hasPresentedPlayback: c.hasPresentedPlayback, isLoadShedding: c.isLoadShedding,
              settings: c.settings, topInset: c.topInset, bottomInset: c.bottomInset)
    }
}

/// One UIKit host and one clock subscription. Switching only replaces its child;
/// it never loads data or touches AVPlayer / PlayerItem.
final class DanmakuRendererHostView: UIView {
    private var renderer: (UIView & DanmakuOverlayRendering)?
    private var requestedMetal: Bool?
    private var logicalCanvasSize: CGSize?
    private var videoAspectRatio: CGFloat?
    private var isTransitioning = false
    private var danmakuKitStageTransitionActive = false
    private var danmakuKitStageSourceSize: CGSize?
    private(set) var usesMetal = false
    var isLoadSheddingValue: Bool { renderer?.isLoadSheddingValue ?? false }
    #if DEBUG
    var debugDiagnostics: DanmakuRendererDiagnostics? { didSet { configureDebugRenderer() } }
    var debugPreferredFramesPerSecond: Int? { didSet { configureDebugRenderer() } }
    private func configureDebugRenderer() {
        (renderer as? MetalDanmakuView)?.debugDiagnostics = debugDiagnostics
        (renderer as? DanmakuKitOverlayView)?.debugDiagnostics = debugDiagnostics
        (renderer as? MetalDanmakuView)?.debugPreferredFramesPerSecond = debugPreferredFramesPerSecond
        (renderer as? DanmakuKitOverlayView)?.debugPreferredFramesPerSecond = debugPreferredFramesPerSecond
    }
    var debugMaximumActiveCount: Int? {
        didSet {
            (renderer as? MetalDanmakuView)?.debugMaximumActiveCount = debugMaximumActiveCount
            (renderer as? DanmakuKitOverlayView)?.debugMaximumActiveCount = debugMaximumActiveCount
        }
    }
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { renderer?.stop() }

    func selectRenderer(metalEnabled: Bool) {
        let rendererChanged = renderer == nil || requestedMetal != metalEnabled
        if rendererChanged {
            renderer?.stop()
            renderer?.removeFromSuperview()
            renderer = nil
            requestedMetal = metalEnabled
            danmakuKitStageTransitionActive = false
            danmakuKitStageSourceSize = nil
            if metalEnabled, let metal = MetalDanmakuView.make() {
                renderer = metal
                usesMetal = true
            } else {
                renderer = DanmakuKitOverlayView(frame: bounds)
                usesMetal = false
            }
        }
        guard let renderer else { return }
        guard rendererChanged else { return }
        #if DEBUG
        (renderer as? MetalDanmakuView)?.debugMaximumActiveCount = debugMaximumActiveCount
        (renderer as? DanmakuKitOverlayView)?.debugMaximumActiveCount = debugMaximumActiveCount
        configureDebugRenderer()
        (debugDiagnostics ?? .shared).rendererType = usesMetal ? "Metal" : (metalEnabled ? "DanmakuKit (Metal unavailable)" : "DanmakuKit")
        #endif
        addSubview(renderer)
        layoutRenderer()
        renderer.setLayoutTransitioning(isTransitioning)
    }

    /// Only the host follows the visible window. The child keeps its track coordinates.
    func setLogicalCanvasSize(_ size: CGSize?) {
        let valid = size.flatMap { size -> CGSize? in
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
            return size
        }
        guard logicalCanvasSize != valid else { return }
        logicalCanvasSize = valid
        guard !danmakuKitStageTransitionActive else { return }
        setNeedsLayout()
        layoutRenderer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutRenderer()
    }

    private func layoutRenderer() {
        guard let renderer else { return }
        if !usesMetal,
           danmakuKitStageTransitionActive,
           let sourceSize = danmakuKitStageSourceSize {
            let viewport = DanmakuVideoViewport.aspectFit(in: bounds, aspectRatio: videoAspectRatio)
            let transform = DanmakuStageTransform.aspectFit(from: sourceSize, into: viewport.size)
            renderer.bounds = CGRect(origin: .zero, size: sourceSize)
            renderer.transform = CGAffineTransform(scaleX: transform.scale, y: transform.scale)
            renderer.center = CGPoint(
                x: viewport.minX + transform.translation.x + sourceSize.width * transform.scale / 2,
                y: viewport.minY + transform.translation.y + sourceSize.height * transform.scale / 2
            )
            return
        }
        renderer.transform = .identity
        let frame = CGRect(origin: .zero, size: logicalCanvasSize ?? bounds.size)
        if renderer.frame != frame { renderer.frame = frame }
    }

    func apply(configuration: DanmakuOverlayConfiguration) {
        videoAspectRatio = configuration.videoAspectRatio
        layoutRenderer()
        renderer?.apply(configuration: configuration)
    }
    func synchronizePlaybackTime(_ time: TimeInterval, force: Bool = false) {
        renderer?.synchronizePlaybackTime(time, force: force)
    }
    func setLayoutTransitioning(_ transitioning: Bool) {
        if !usesMetal, let renderer {
            if transitioning, !danmakuKitStageTransitionActive {
                let size = renderer.bounds.size
                danmakuKitStageSourceSize = size.width > 0 && size.height > 0
                    ? size
                    : (logicalCanvasSize ?? bounds.size)
                danmakuKitStageTransitionActive = true
            }

            isTransitioning = transitioning
            if !transitioning, danmakuKitStageTransitionActive {
                // Restore the final logical canvas before the renderer applies
                // its single end-of-transition synchronization.
                danmakuKitStageTransitionActive = false
                danmakuKitStageSourceSize = nil
                renderer.transform = .identity
                layoutRenderer()
            } else if transitioning {
                layoutRenderer()
            }
            renderer.setLayoutTransitioning(transitioning)
            return
        }
        isTransitioning = transitioning
        renderer?.setLayoutTransitioning(transitioning)
    }
    func stop() {
        renderer?.stop()
        renderer?.removeFromSuperview()
        renderer = nil
        requestedMetal = nil
        danmakuKitStageTransitionActive = false
        danmakuKitStageSourceSize = nil
    }
}
