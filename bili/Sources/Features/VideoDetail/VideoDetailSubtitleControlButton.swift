import SwiftUI
import UIKit

/// 控制条字幕（CC）按钮：仅有字幕轨时显示，挂在 accessory 槽位。
///
/// 触摸必须由 UIKit 承担——玻璃修饰的 SwiftUI Button 在 UIHostingController
/// 嵌 UIKit 的播放器 overlay 里会吞掉点击（同 SurfaceOnlyUIKitMoreControlsButton）。
/// 图标字号按视觉对齐控制条其它图标（气泡字形本身更饱满，故不使用 +3）。
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
        button.configuration = Self.configuration(
            symbolName: store.selectedLan == nil ? "captions.bubble" : "captions.bubble.fill",
            metrics: metrics
        )
    }

    static func configuration(
        symbolName: String,
        metrics: PlayerNativeControlMetrics
    ) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero
        // 气泡字形比齿轮/全屏更饱满，同字号会显得更大；用 iconSize 使其视觉等高。
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: metrics.iconSize,
            weight: .semibold
        )
        configuration.image = UIImage(systemName: symbolName)
        return configuration
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

/// 横屏字幕按钮：点按直接展开系统菜单（UIMenu），由按钮位置原生展开，
/// 不再是覆盖画面的弹窗。
struct VideoDetailSubtitleMenuButton: UIViewRepresentable {
    @ObservedObject var store: VideoDetailSubtitleStore
    let metrics: PlayerNativeControlMetrics
    let onSelect: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(primaryAction: nil)
        button.accessibilityLabel = "字幕"
        button.accessibilityIdentifier = "ui.player.subtitle.toggle"
        button.tintColor = .white
        button.showsMenuAsPrimaryAction = true
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onSelect = onSelect
        button.configuration = VideoDetailSubtitleControlButton.configuration(
            symbolName: store.selectedLan == nil ? "captions.bubble" : "captions.bubble.fill",
            metrics: metrics
        )
        button.menu = context.coordinator.makeMenu(store: store)
    }

    @MainActor
    final class Coordinator {
        var onSelect: (String?) -> Void

        init(onSelect: @escaping (String?) -> Void) {
            self.onSelect = onSelect
        }

        func makeMenu(store: VideoDetailSubtitleStore) -> UIMenu {
            var actions: [UIMenuElement] = store.tracks.map { track in
                UIAction(
                    title: track.isAI ? "\(track.lanDoc)（AI）" : track.lanDoc,
                    state: store.selectedLan == track.lan ? .on : .off
                ) { [weak self] _ in
                    self?.onSelect(track.lan)
                }
            }
            actions.append(
                UIAction(
                    title: "关闭字幕",
                    state: store.selectedLan == nil ? .on : .off
                ) { [weak self] _ in
                    self?.onSelect(nil)
                }
            )
            return UIMenu(title: "字幕", children: actions)
        }
    }
}

/// 字幕轨行：竖屏系统 sheet 使用。
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
