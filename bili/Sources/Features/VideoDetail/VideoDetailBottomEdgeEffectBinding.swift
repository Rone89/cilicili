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
        if self.scrollView === scrollView, interaction?.view === container {
            applySoftEffect(to: scrollView)
            return
        }
        detach()
        self.scrollView = scrollView
        originalStyle = scrollView.bottomEdgeEffect.style
        originalHidden = scrollView.bottomEdgeEffect.isHidden
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.scrollView = scrollView
        interaction.edge = .bottom
        container.addInteraction(interaction)
        self.interaction = interaction
        applySoftEffect(to: scrollView)
    }

    private func applySoftEffect(to scrollView: UIScrollView) {
        // Toolbar updates can restore the system default after the interaction is attached.
        if scrollView.bottomEdgeEffect.style != .soft {
            scrollView.bottomEdgeEffect.style = .soft
        }
        if scrollView.bottomEdgeEffect.isHidden {
            scrollView.bottomEdgeEffect.isHidden = false
        }
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
