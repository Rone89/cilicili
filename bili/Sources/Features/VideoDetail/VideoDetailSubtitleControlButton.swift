import SwiftUI
import UIKit

/// 控制条字幕（CC）按钮：仅有字幕轨时显示，挂在 accessory 槽位。
///
/// 触摸必须由 UIKit 承担——玻璃修饰的 SwiftUI Button 在 UIHostingController
/// 嵌 UIKit 的播放器 overlay 里会吞掉点击（同 SurfaceOnlyUIKitMoreControlsButton）。
struct VideoDetailSubtitleControlButton: UIViewRepresentable {
    @ObservedObject var store: VideoDetailSubtitleStore
    let metrics: PlayerNativeControlMetrics
    let onSelect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(
            configuration: Self.configuration,
            primaryAction: context.coordinator.primaryAction
        )
        button.accessibilityLabel = "字幕"
        button.accessibilityIdentifier = "ui.player.subtitle.toggle"
        button.tintColor = .white
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onSelect = onSelect
        let imageName = store.selectedLan == nil ? "captions.bbox" : "captions.bbox.fill"
        if button.viewWithTag(Self.iconViewTag) == nil {
            let iconView = UIImageView()
            iconView.tag = Self.iconViewTag
            iconView.contentMode = .center
            iconView.tintColor = .white
            iconView.isUserInteractionEnabled = false
            iconView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
        }
        (button.viewWithTag(Self.iconViewTag) as? UIImageView)?.image = UIImage(
            systemName: imageName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: metrics.iconSize + 2,
                weight: .semibold
            )
        )
    }

    static let iconViewTag = 0x51C

    private static let configuration: UIButton.Configuration = {
        // 玻璃由宿主 SwiftUI 视图提供；这里只负责触摸投递。
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero
        return configuration
    }()

    @MainActor
    final class Coordinator {
        var onSelect: () -> Void
        lazy var primaryAction = UIAction { [weak self] _ in
            self?.onSelect()
        }

        init(onSelect: @escaping () -> Void) {
            self.onSelect = onSelect
        }
    }
}

/// 字幕轨选择浮层：overlay 内呈现（对齐横屏播放设置面板模式），
/// 不用系统 sheet——UIHostingController 嵌 UIKit 层时系统 sheet 弹不出来。
struct VideoDetailSubtitleSelectionPanel: View {
    @ObservedObject var store: VideoDetailSubtitleStore
    let onSelect: (String?) -> Void
    let close: () -> Void

    var body: some View {
        Color.black.opacity(0.01)
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .overlay(alignment: .bottom) {
                panel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 132)
            }
            .transition(.opacity)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            ForEach(store.tracks) { track in
                row(
                    title: track.lanDoc,
                    badge: track.isAI ? "AI" : nil,
                    isSelected: store.selectedLan == track.lan,
                    accessibilityIdentifier: "ui.player.subtitle.track.\(track.lan)"
                ) {
                    onSelect(track.lan)
                    close()
                }
                if track.id != store.tracks.last?.id {
                    Divider().overlay(Color.white.opacity(0.12))
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            row(
                title: "关闭字幕",
                badge: nil,
                isSelected: store.selectedLan == nil,
                accessibilityIdentifier: "ui.player.subtitle.track.off"
            ) {
                onSelect(nil)
                close()
            }
        }
        .frame(maxWidth: 300)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    private func row(
        title: String,
        badge: String?,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
