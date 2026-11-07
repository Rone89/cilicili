import SwiftUI
import UIKit

/// 控制条字幕（CC）按钮：仅有字幕轨时显示，挂在 accessory 槽位。
///
/// 触摸必须由 UIKit 承担——玻璃修饰的 SwiftUI Button 在 UIHostingController
/// 嵌 UIKit 的播放器 overlay 里会吞掉点击（同 SurfaceOnlyUIKitMoreControlsButton）。
/// 选轨弹窗同样由 UIKit 呈现：该宿主结构下 SwiftUI `.sheet` 不会弹出。
struct VideoDetailSubtitleControlButton: UIViewRepresentable {
    @ObservedObject var store: VideoDetailSubtitleStore
    let metrics: PlayerNativeControlMetrics
    let onSelect: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(primaryAction: context.coordinator.primaryAction)
        button.accessibilityLabel = "字幕"
        button.accessibilityIdentifier = "ui.player.subtitle.toggle"
        button.tintColor = .white
        button.imageView?.contentMode = .center
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.store = store
        context.coordinator.button = button
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero
        configuration.image = UIImage(
            systemName: store.selectedLan == nil ? "captions.bubble" : "captions.bubble.fill",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: metrics.iconSize + 2,
                weight: .semibold
            )
        )
        button.configuration = configuration
    }

    @MainActor
    final class Coordinator {
        var onSelect: (String?) -> Void
        var store: VideoDetailSubtitleStore?
        weak var button: UIButton?
        lazy var primaryAction = UIAction { [weak self] _ in
            self?.presentSelection()
        }

        init(onSelect: @escaping (String?) -> Void) {
            self.onSelect = onSelect
        }

        /// 用系统 action sheet 选轨（原生弹窗，UIKit 直接呈现）。
        func presentSelection() {
            guard let store, let button else { return }
            guard let presenter = Self.topMostViewController(from: button) else { return }

            let alert = UIAlertController(title: "字幕", message: nil, preferredStyle: .actionSheet)

            for track in store.tracks {
                let title = track.isAI ? "\(track.lanDoc)（AI）" : track.lanDoc
                let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                    self?.onSelect(track.lan)
                }
                if store.selectedLan == track.lan {
                    action.setValue(true, forKey: "checked")
                }
                alert.addAction(action)
            }

            let offAction = UIAlertAction(title: "关闭字幕", style: .default) { [weak self] _ in
                self?.onSelect(nil)
            }
            if store.selectedLan == nil {
                offAction.setValue(true, forKey: "checked")
            }
            alert.addAction(offAction)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))

            // iPad / 横屏需要锚点，否则呈现会抛异常。
            if let popover = alert.popoverPresentationController {
                popover.sourceView = button
                popover.sourceRect = button.bounds
                popover.permittedArrowDirections = [.down, .up]
            }
            presenter.present(alert, animated: true)
        }

        private static func topMostViewController(from view: UIView) -> UIViewController? {
            var root = view.window?.rootViewController
            if root == nil {
                root = UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                    .first?.rootViewController
            }
            var candidate = root
            while let presented = candidate?.presentedViewController {
                candidate = presented
            }
            return candidate
        }
    }
}
