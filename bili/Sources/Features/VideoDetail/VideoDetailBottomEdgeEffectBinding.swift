import SwiftUI
import UIKit

/// Own only our interaction; leave the system toolbar and scroll geometry intact.
@MainActor
final class VideoDetailBottomEdgeEffectBinding {
    private var interaction: UIScrollEdgeElementContainerInteraction?
    private weak var scrollView: UIScrollView?
    private var originalStyle: UIScrollEdgeEffect.Style?
    private var originalHidden = false

    func update(scrollView: UIScrollView, container: UIView?, enabled: Bool) {
        guard enabled, let container else {
            detach()
            return
        }
        if self.scrollView === scrollView, interaction?.view === container { return }
        detach()
        self.scrollView = scrollView
        originalStyle = scrollView.bottomEdgeEffect.style
        originalHidden = scrollView.bottomEdgeEffect.isHidden
        scrollView.bottomEdgeEffect.style = .soft
        scrollView.bottomEdgeEffect.isHidden = false
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.scrollView = scrollView
        interaction.edge = .bottom
        container.addInteraction(interaction)
        self.interaction = interaction
    }

    func detach() {
        if let interaction {
            interaction.view?.removeInteraction(interaction)
            interaction.scrollView = nil
        }
        interaction = nil
        if let scrollView, let originalStyle {
            scrollView.bottomEdgeEffect.style = originalStyle
            scrollView.bottomEdgeEffect.isHidden = originalHidden
        }
        scrollView = nil
        originalStyle = nil
    }
}

@MainActor
final class VideoDetailEdgeEffectScrollView: UIScrollView {
    private let edgeBinding = VideoDetailBottomEdgeEffectBinding()
    weak var pageBottomEdgeContainer: UIView? {
        didSet { updateBottomEdgeBinding() }
    }
    var bottomEdgeBlurEnabled = false {
        didSet { updateBottomEdgeBinding() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBottomEdgeBinding()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBottomEdgeBinding()
    }

    private func updateBottomEdgeBinding() {
        guard bottomEdgeBlurEnabled, window != nil else {
            edgeBinding.detach()
            return
        }
        if let pageBottomEdgeContainer, pageBottomEdgeContainer.window === window {
            edgeBinding.update(scrollView: self, container: pageBottomEdgeContainer, enabled: true)
            return
        }
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController,
               let navigation = controller.navigationController {
                let toolbar = navigation.toolbar
                edgeBinding.update(scrollView: self, container: toolbar,
                                   enabled: !navigation.isToolbarHidden && toolbar?.isHidden == false)
                return
            }
            responder = current.next
        }
        edgeBinding.detach()
    }
}

/// Register the page-owned bottom controls with Apple's scroll edge interaction.
/// This transparent view draws no blur or background itself.
struct VideoDetailFixedBottomEdgeContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> VideoDetailFixedBottomEdgeContainerView {
        VideoDetailFixedBottomEdgeContainerView()
    }

    func updateUIView(_ view: VideoDetailFixedBottomEdgeContainerView, context: Context) {
        view.scheduleBinding()
    }

    static func dismantleUIView(_ view: VideoDetailFixedBottomEdgeContainerView, coordinator: ()) {
        view.detach()
    }
}

final class VideoDetailFixedBottomEdgeContainerView: UIView {
    private let boundScrollViews = NSHashTable<VideoDetailEdgeEffectScrollView>.weakObjects()
    private var bindingScheduled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { detach() } else { scheduleBinding() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleBinding()
    }

    func scheduleBinding() {
        guard !bindingScheduled, window != nil else { return }
        bindingScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bindingScheduled = false
            guard self.window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController {
                    self.bind(in: controller.view)
                    return
                }
                responder = current.next
            }
        }
    }

    private func bind(in view: UIView) {
        if let scroll = view as? VideoDetailEdgeEffectScrollView {
            if scroll.pageBottomEdgeContainer !== self {
                scroll.pageBottomEdgeContainer = self
            }
            boundScrollViews.add(scroll)
        }
        for child in view.subviews { bind(in: child) }
    }

    func detach() {
        for scroll in boundScrollViews.allObjects where scroll.pageBottomEdgeContainer === self {
            scroll.pageBottomEdgeContainer = nil
        }
        boundScrollViews.removeAllObjects()
    }
}
