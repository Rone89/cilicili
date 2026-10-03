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
    private var isTransitioning = false
    private(set) var usesMetal = false
    var isLoadSheddingValue: Bool { renderer?.isLoadSheddingValue ?? false }
    #if DEBUG
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
        guard renderer == nil || requestedMetal != metalEnabled else { return }
        renderer?.stop()
        renderer?.removeFromSuperview()
        renderer = nil
        requestedMetal = metalEnabled
        if metalEnabled, let metal = MetalDanmakuView.make() {
            renderer = metal
            usesMetal = true
        } else {
            renderer = DanmakuKitOverlayView(frame: bounds)
            usesMetal = false
        }
        guard let renderer else { return }
        #if DEBUG
        (renderer as? MetalDanmakuView)?.debugMaximumActiveCount = debugMaximumActiveCount
        (renderer as? DanmakuKitOverlayView)?.debugMaximumActiveCount = debugMaximumActiveCount
        DanmakuRendererDiagnostics.shared.rendererType = usesMetal ? "Metal" : (metalEnabled ? "DanmakuKit (Metal unavailable)" : "DanmakuKit")
        #endif
        renderer.frame = bounds
        renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(renderer)
        renderer.setLayoutTransitioning(isTransitioning)
    }

    func apply(configuration: DanmakuOverlayConfiguration) { renderer?.apply(configuration: configuration) }
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
        requestedMetal = nil
    }
}
