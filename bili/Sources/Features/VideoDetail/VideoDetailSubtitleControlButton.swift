import SwiftUI
import UIKit

/// 控制条字幕（CC）按钮：仅有字幕轨时显示，挂在 accessory 槽位。
///
/// 触摸必须由 UIKit 承担——玻璃修饰的 SwiftUI Button 在 UIHostingController
/// 嵌 UIKit 的播放器 overlay 里会吞掉点击（同 SurfaceOnlyUIKitMoreControlsButton）。
/// 选轨弹窗由详情页最外层 SwiftUI sheet 宿主呈现（与评论弹窗同款）。
struct VideoDetailSubtitleControlButton: UIViewRepresentable {
    @ObservedObject var store: VideoDetailSubtitleStore
    let metrics: PlayerNativeControlMetrics
    let onSelect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(primaryAction: context.coordinator.primaryAction)
        button.accessibilityLabel = "字幕"
        button.accessibilityIdentifier = "ui.player.subtitle.toggle"
        button.tintColor = .white
        button.imageView?.contentMode = .center
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onSelect = onSelect
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
        var onSelect: () -> Void
        lazy var primaryAction = UIAction { [weak self] _ in
            self?.onSelect()
        }

        init(onSelect: @escaping () -> Void) {
            self.onSelect = onSelect
        }
    }
}

/// 字幕轨选择弹层：与评论弹窗同款系统 sheet（外层 SwiftUI 呈现）。
struct VideoDetailSubtitleSelectionSheet: View {
    @ObservedObject var store: VideoDetailSubtitleStore
    let onSelect: (String?) -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.tracks) { track in
                        row(
                            title: track.lanDoc,
                            isAI: track.isAI,
                            isSelected: store.selectedLan == track.lan,
                            accessibilityIdentifier: "ui.player.subtitle.track.\(track.lan)"
                        ) {
                            onSelect(track.lan)
                            close()
                        }
                    }
                }

                Section {
                    row(
                        title: "关闭字幕",
                        isAI: false,
                        isSelected: store.selectedLan == nil,
                        accessibilityIdentifier: "ui.player.subtitle.track.off"
                    ) {
                        onSelect(nil)
                        close()
                    }
                }

                if let message = store.loadErrorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: close)
                }
            }
        }
    }

    private func row(
        title: String,
        isAI: Bool,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.primary)
                if isAI {
                    Text("AI")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
