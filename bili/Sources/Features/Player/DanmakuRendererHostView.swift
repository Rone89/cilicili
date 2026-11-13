import AVFoundation
import OSLog
import UIKit

/// 弹幕渲染后端选择。synchronizedLayer 需要 VM 暴露的 AVPlayer 才能挂
/// AVSynchronizedLayer；无播放器（直播间等）时上层负责回退到 kit/metal。
enum DanmakuRendererPreference: Equatable {
    case synchronizedLayer
    case danmakuKit
    case metal
}

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
    /// 必须是协议要求而非仅扩展方法：存在体（any DanmakuOverlayRendering）
    /// 调用时扩展方法会静态分发到默认空实现，具体类型的实现不会被执行。
    func attachPlaybackPlayer(_ player: AVPlayer?)
}

extension DanmakuOverlayRendering {
    /// 仅 AVSynchronizedLayer 后端有实际实现；DanmakuKit/Metal 保持空操作。
    func attachPlaybackPlayer(_ player: AVPlayer?) {}
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
    private var requestedPreference: DanmakuRendererPreference?
    private var playbackPlayer: AVPlayer?
    private var logicalCanvasSize: CGSize?
    private var videoAspectRatio: CGFloat?
    private var isTransitioning = false
    private var danmakuKitStageTransitionActive = false
    private var danmakuKitStageSourceSize: CGSize?
    private(set) var usesMetal = false
    private(set) var usesSynchronizedLayer = false
    var debugActiveRenderer: (UIView & DanmakuOverlayRendering)? { renderer }
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

    func selectRenderer(preference: DanmakuRendererPreference) {
        let rendererChanged = renderer == nil || requestedPreference != preference
        if rendererChanged {
            renderer?.stop()
            renderer?.removeFromSuperview()
            renderer = nil
            requestedPreference = preference
            danmakuKitStageTransitionActive = false
            danmakuKitStageSourceSize = nil
            usesMetal = false
            usesSynchronizedLayer = false
            switch preference {
            case .synchronizedLayer:
                renderer = DanmakuSynchronizedLayerView(frame: bounds)
                usesSynchronizedLayer = true
            case .metal:
                if let metal = MetalDanmakuView.make() {
                    renderer = metal
                    usesMetal = true
                } else {
                    renderer = DanmakuKitOverlayView(frame: bounds)
                }
            case .danmakuKit:
                renderer = DanmakuKitOverlayView(frame: bounds)
            }
            forwardPlaybackPlayerToRenderer()
            PlayerMetricsLog.logger.info(
                "danmakuSync host selected preference=\(String(describing: preference), privacy: .public) name=\(self.rendererName, privacy: .public) player=\(self.playbackPlayer != nil, privacy: .public)"
            )
        }
        guard let renderer, rendererChanged else { return }
        #if DEBUG
        (renderer as? MetalDanmakuView)?.debugMaximumActiveCount = debugMaximumActiveCount
        (renderer as? DanmakuKitOverlayView)?.debugMaximumActiveCount = debugMaximumActiveCount
        configureDebugRenderer()
        (debugDiagnostics ?? .shared).rendererType = rendererName
        #endif
        addSubview(renderer)
        layoutRenderer()
        renderer.setLayoutTransitioning(isTransitioning)
    }

    private var rendererName: String {
        if usesSynchronizedLayer { return "AVSynchronizedLayer" }
        if usesMetal { return "Metal" }
        return "DanmakuKit"
    }

    /// 同步层后端需要 AVPlayer 挂 AVSynchronizedLayer；其余后端忽略。
    func setPlaybackPlayer(_ player: AVPlayer?) {
        guard playbackPlayer !== player else { return }
        playbackPlayer = player
        forwardPlaybackPlayerToRenderer()
    }

    private func forwardPlaybackPlayerToRenderer() {
        renderer?.attachPlaybackPlayer(playbackPlayer)
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
        if renderer is DanmakuKitOverlayView,
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
        if let kitRenderer = renderer as? DanmakuKitOverlayView {
            if transitioning, !danmakuKitStageTransitionActive {
                let size = kitRenderer.bounds.size
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
                kitRenderer.transform = .identity
                layoutRenderer()
            } else if transitioning {
                layoutRenderer()
            }
            kitRenderer.setLayoutTransitioning(transitioning)
            return
        }
        isTransitioning = transitioning
        renderer?.setLayoutTransitioning(transitioning)
    }
    func stop() {
        renderer?.stop()
        renderer?.removeFromSuperview()
        renderer = nil
        requestedPreference = nil
        danmakuKitStageTransitionActive = false
        danmakuKitStageSourceSize = nil
    }
}
