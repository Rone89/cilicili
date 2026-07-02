import AVFoundation
import SwiftUI
import UIKit

/// UIKit 详情页外壳使用的播放器 surface 宿主。
///
/// 把现有 SwiftUI `VideoSurfaceView` 通过 `UIHostingController` 嵌进 UIKit
/// 视图树，复用现有渲染管线；UIKit 外壳只负责布局 frame，surface 的 layer
/// 会随 `onBoundsChange` 自动 resize。
@MainActor
final class UIKitPlayerSurfaceHostView: UIView {
    private var viewModel: PlayerStateViewModel
    private let isPictureInPictureEnabled: Bool
    private let hostingController: UIHostingController<AnyView>

    init(viewModel: PlayerStateViewModel, isPictureInPictureEnabled: Bool = false) {
        self.viewModel = viewModel
        self.isPictureInPictureEnabled = isPictureInPictureEnabled
        // 必须忽略 safe area：否则横屏时 home indicator 的安全区会把
        // surface 往内缩，底部露出黑底（看起来像视频没铺满高度）。
        self.hostingController = UIHostingController(
            rootView: Self.makeSurfaceRoot(
                viewModel: viewModel,
                isPictureInPictureEnabled: isPictureInPictureEnabled
            )
        )
        super.init(frame: .zero)

        backgroundColor = .black
        hostingController.view.backgroundColor = .black
        // 双保险：让 hosting controller 自身也不参与 safe area 内缩。
        if #available(iOS 16.4, *) {
            hostingController.safeAreaRegions = []
        }
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 让父 VC 在 `addChild` 后调用，完成 hosting controller 的 containment。
    func attach(to parent: UIViewController) {
        parent.addChild(hostingController)
        hostingController.didMove(toParent: parent)
    }

    /// 切换画面填充模式。横屏全屏用 `.resizeAspectFill`（按高度铺满、左右裁切），
    /// 竖屏内联用 `.resizeAspect`（保持比例完整显示）。
    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        viewModel.setVideoGravity(gravity)
    }

    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel) {
        guard viewModel !== playerViewModel else { return }
        viewModel = playerViewModel
        hostingController.rootView = Self.makeSurfaceRoot(
            viewModel: playerViewModel,
            isPictureInPictureEnabled: isPictureInPictureEnabled
        )
    }

    func refreshLayoutImmediately() {
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            if let surfaceView = hostingController.view.firstVideoSurfaceContainerView {
                surfaceView.setNeedsLayout()
                surfaceView.layoutIfNeeded()
                surfaceView.invalidateVideoLayout()
            } else {
                viewModel.refreshSurfaceLayout()
            }
        }
    }

    private static func makeSurfaceRoot(
        viewModel: PlayerStateViewModel,
        isPictureInPictureEnabled: Bool
    ) -> AnyView {
        let surface = VideoSurfaceView(
            viewModel: viewModel,
            prefersNativePlaybackControls: false,
            isPictureInPictureEnabled: isPictureInPictureEnabled,
            // 原型阶段先用即时布局，不引入 SwiftUI 协调动画，
            // 让旋转时的 frame 变化直接驱动 layer，观察“裸”手感。
            disablesImplicitLayoutAnimations: true,
            usesLiveSurfaceDuringLayoutTransition: true
        )
        return AnyView(surface.ignoresSafeArea())
    }
}

private extension UIView {
    var firstVideoSurfaceContainerView: VideoSurfaceContainerView? {
        if let surfaceView = self as? VideoSurfaceContainerView {
            return surfaceView
        }
        for subview in subviews {
            if let surfaceView = subview.firstVideoSurfaceContainerView {
                return surfaceView
            }
        }
        return nil
    }
}
