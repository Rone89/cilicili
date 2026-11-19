import AVFoundation
import OSLog
import UIKit

/// 弹幕渲染后端选择。点播使用 `synchronizedLayer`（绑定 `AVPlayer`），
/// 无 `AVPlayer` 场景（如直播间）默认使用 `metal`。
enum DanmakuRendererPreference: Equatable {
    case synchronizedLayer
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
    /// 仅 AVSynchronizedLayer 后端有实际实现；Metal 保持空操作。
    func attachPlaybackPlayer(_ player: AVPlayer?) {}
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
    private(set) var usesMetal = false
    private(set) var usesSynchronizedLayer = false
    var debugActiveRenderer: (UIView & DanmakuOverlayRendering)? { renderer }
    var isLoadSheddingValue: Bool { renderer?.isLoadSheddingValue ?? false }
    #if DEBUG
    var debugDiagnostics: DanmakuRendererDiagnostics? { didSet { configureDebugRenderer() } }
    var debugPreferredFramesPerSecond: Int? { didSet { configureDebugRenderer() } }
    private func configureDebugRenderer() {
        (renderer as? MetalDanmakuView)?.debugDiagnostics = debugDiagnostics
        (renderer as? MetalDanmakuView)?.debugPreferredFramesPerSecond = debugPreferredFramesPerSecond
    }
    var debugMaximumActiveCount: Int? {
        didSet {
            (renderer as? MetalDanmakuView)?.debugMaximumActiveCount = debugMaximumActiveCount
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
                    renderer = DanmakuSynchronizedLayerView(frame: bounds)
                    usesSynchronizedLayer = true
                }
            }
            forwardPlaybackPlayerToRenderer()
            PlayerMetricsLog.logger.info(
                "danmakuSync host selected preference=\(String(describing: preference), privacy: .public) name=\(self.rendererName, privacy: .public) player=\(self.playbackPlayer != nil, privacy: .public)"
            )
        }
        guard let renderer, rendererChanged else { return }
        #if DEBUG
        (renderer as? MetalDanmakuView)?.debugMaximumActiveCount = debugMaximumActiveCount
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
        setNeedsLayout()
        layoutRenderer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutRenderer()
    }

    private func layoutRenderer() {
        guard let renderer else { return }
        let frame = CGRect(origin: .zero, size: logicalCanvasSize ?? bounds.size)
        guard renderer.transform != .identity || renderer.frame != frame else { return }
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            renderer.transform = .identity
            renderer.frame = frame
            CATransaction.commit()
        }
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
        isTransitioning = transitioning
        renderer?.setLayoutTransitioning(transitioning)
    }
    func stop() {
        renderer?.stop()
        renderer?.removeFromSuperview()
        renderer = nil
        requestedPreference = nil
    }
}
