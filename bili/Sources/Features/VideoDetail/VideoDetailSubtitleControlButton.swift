import SwiftUI
import UIKit

/// 控制条字幕（CC）按钮：仅有字幕轨时显示，挂在 accessory 槽位。
///
/// 触摸必须由 UIKit 承担——玻璃修饰的 SwiftUI Button 在 UIHostingController
/// 嵌 UIKit 的播放器 overlay 里会吞掉点击（同 SurfaceOnlyUIKitMoreControlsButton）。
/// 图标字号与「更多播放设置」齿轮一致（metrics.iconSize + 3）。
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
        // 与 SurfaceOnlyUIKitMoreControlsButton 的齿轮图标同字号/同字重，
        // 保证控制条上两个图标视觉大小一致。
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: metrics.iconSize + 3,
            weight: .semibold
        )
        configuration.image = UIImage(
            systemName: store.selectedLan == nil ? "captions.bubble" : "captions.bubble.fill"
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

/// 字幕轨行：竖屏系统 sheet 与横屏玻璃面板共用。
struct VideoDetailSubtitleSelectionRow: View {
    let title: String
    let isAI: Bool
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// 字幕轨选择弹层（竖屏）：与评论弹窗同款系统 sheet，由外层 SwiftUI 呈现。
struct VideoDetailSubtitleSelectionSheet: View {
    @ObservedObject var store: VideoDetailSubtitleStore
    let onSelect: (String?) -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.tracks) { track in
                        VideoDetailSubtitleSelectionRow(
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
                    VideoDetailSubtitleSelectionRow(
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
}

/// 字幕轨选择面板（横屏）：复用播放设置同款玻璃卡片，不全屏。
struct VideoDetailSubtitleSelectionPanel: View {
    @ObservedObject var store: VideoDetailSubtitleStore
    let onSelect: (String?) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("字幕")
                    .font(.headline)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.tracks) { track in
                        VideoDetailSubtitleSelectionRow(
                            title: track.lanDoc,
                            isAI: track.isAI,
                            isSelected: store.selectedLan == track.lan,
                            accessibilityIdentifier: "ui.player.subtitle.track.\(track.lan)"
                        ) {
                            onSelect(track.lan)
                            close()
                        }
                        Divider().padding(.leading, 16)
                    }

                    VideoDetailSubtitleSelectionRow(
                        title: "关闭字幕",
                        isAI: false,
                        isSelected: store.selectedLan == nil,
                        accessibilityIdentifier: "ui.player.subtitle.track.off"
                    ) {
                        onSelect(nil)
                        close()
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
    }
}
