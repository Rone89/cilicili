import SwiftUI
import UIKit

struct VideoDetailInlineQualityMenuControl: View {
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let metrics: PlayerNativeControlMetrics
    let isLandscape: Bool
    let onPress: () -> Void
    let onMenuWillOpen: () -> Void
    let onMenuDidClose: () -> Void
    let selectPlayVariant: (PlayVariant) -> Void

    var body: some View {
        Group {
            if store.hasQualityMenu {
                VideoDetailInlineQualityMenuButton(
                    store: store,
                    title: store.qualityInlineButtonTitle,
                    metrics: metrics,
                    isLandscape: isLandscape,
                    onPress: onPress,
                    onMenuWillOpen: onMenuWillOpen,
                    onMenuDidClose: onMenuDidClose,
                    selectPlayVariant: selectPlayVariant
                )
                .frame(width: metrics.qualityButtonMaxWidth, height: metrics.controlHeight)
                .biliPlayerClearGlass(interactive: true, in: Capsule())
                .biliPlayerExpandedHitTarget(metrics: metrics)
            }
        }
    }
}

/// UIKit owns the control touch so it remains reliable in the hosted player overlay.
private struct VideoDetailInlineQualityMenuButton: UIViewRepresentable {
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let title: String
    let metrics: PlayerNativeControlMetrics
    let isLandscape: Bool
    let onPress: () -> Void
    let onMenuWillOpen: () -> Void
    let onMenuDidClose: () -> Void
    let selectPlayVariant: (PlayVariant) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> VideoDetailQualityMenuUIButton {
        let button = VideoDetailQualityMenuUIButton(type: .system)
        let coordinator = context.coordinator
        button.addAction(coordinator.primaryAction, for: .touchUpInside)
        button.onMenuWillDisplay = { [weak coordinator] in
            coordinator?.onMenuWillOpen()
        }
        button.onMenuDidEnd = { [weak coordinator] in
            coordinator?.onMenuDidClose()
        }
        button.accessibilityLabel = "清晰度"
        button.accessibilityIdentifier = "ui.player.quality.quick"
        button.overrideUserInterfaceStyle = .dark
        button.tintColor = .white
        return button
    }

    func updateUIView(_ button: VideoDetailQualityMenuUIButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.update(
            store: store,
            onPress: onPress,
            onMenuWillOpen: onMenuWillOpen,
            onMenuDidClose: onMenuDidClose,
            selectPlayVariant: selectPlayVariant
        )
        button.configuration = Self.configuration(title: title, metrics: metrics)
        button.accessibilityValue = title
        button.showsMenuAsPrimaryAction = isLandscape && store.hasQualityMenu

        if isLandscape && store.hasQualityMenu {
            if coordinator.cachedMenuItems != store.qualityMenuItems {
                button.menu = coordinator.makeMenu()
                coordinator.cachedMenuItems = store.qualityMenuItems
            }
        } else {
            button.menu = nil
            coordinator.cachedMenuItems = nil
        }
    }

    private static func configuration(
        title: String,
        metrics: PlayerNativeControlMetrics
    ) -> UIButton.Configuration {
        let fontSize = metrics.iconSize
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: metrics.qualityHorizontalPadding,
            bottom: 0,
            trailing: metrics.qualityHorizontalPadding
        )
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            [fontSize] attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: fontSize)
            return updated
        }
        return configuration
    }

    @MainActor
    final class Coordinator {
        var store: VideoDetailQualityControlRenderStore
        var onPress: () -> Void = {}
        var onMenuWillOpen: () -> Void = {}
        var onMenuDidClose: () -> Void = {}
        var selectPlayVariant: (PlayVariant) -> Void = { _ in }
        var cachedMenuItems: [VideoDetailPlaybackQualityMenuItem]?

        lazy var primaryAction = UIAction { [weak self] _ in
            self?.onPress()
        }

        init(store: VideoDetailQualityControlRenderStore) {
            self.store = store
        }

        func update(
            store: VideoDetailQualityControlRenderStore,
            onPress: @escaping () -> Void,
            onMenuWillOpen: @escaping () -> Void,
            onMenuDidClose: @escaping () -> Void,
            selectPlayVariant: @escaping (PlayVariant) -> Void
        ) {
            self.store = store
            self.onPress = onPress
            self.onMenuWillOpen = onMenuWillOpen
            self.onMenuDidClose = onMenuDidClose
            self.selectPlayVariant = selectPlayVariant
        }

        func makeMenu() -> UIMenu {
            let actions = store.qualityMenuItems.map { item in
                UIAction(
                    title: item.title,
                    image: UIImage(systemName: item.systemImage),
                    identifier: UIAction.Identifier("quality-\(item.variant.quality)"),
                    attributes: item.isDisabled ? [.disabled] : [],
                    state: .off
                ) { [weak self] _ in
                    self?.selectQuality(item.id)
                }
            }
            return UIMenu(title: "清晰度", children: actions)
        }

        private func selectQuality(_ itemID: String) {
            guard let item = store.qualityMenuItems.first(where: { $0.id == itemID }),
                  !item.isDisabled
            else { return }
            selectPlayVariant(item.variant)
        }
    }
}

@MainActor
private final class VideoDetailQualityMenuUIButton: UIButton {
    var onMenuWillDisplay: (() -> Void)?
    var onMenuDidEnd: (() -> Void)?

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(
            interaction,
            willDisplayMenuFor: configuration,
            animator: animator
        )
        onMenuWillDisplay?()
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(
            interaction,
            willEndFor: configuration,
            animator: animator
        )
        let notifyClosed: () -> Void = { [weak self] in self?.onMenuDidEnd?() }
        if let animator {
            animator.addCompletion(notifyClosed)
        } else {
            notifyClosed()
        }
    }
}

struct VideoDetailQuickQualitySelectionSheet: View {
    @ObservedObject var store: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.isSwitchingPlayQuality {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("切换中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                }

                ForEach(store.qualityMenuItems) { item in
                    VideoDetailQuickQualitySelectionRow(item: item) {
                        guard let currentItem = store.qualityMenuItems.first(where: { $0.id == item.id }),
                              !currentItem.isDisabled
                        else { return }
                        selectPlayVariant(currentItem.variant)
                        close()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .navigationTitle("清晰度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: close)
                }
            }
        }
        .commentSheetPresentation()
    }
}

private struct VideoDetailQuickQualitySelectionRow: View {
    let item: VideoDetailPlaybackQualityMenuItem
    let action: () -> Void

    private var isSelected: Bool {
        item.systemImage == "largecircle.fill.circle"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.isDisabled ? Color.secondary : isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .foregroundStyle(.primary)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isDisabled)
        .opacity(item.isDisabled ? 0.45 : 1)
        .accessibilityLabel(item.subtitle.map { "\(item.title), \($0)" } ?? item.title)
        .accessibilityIdentifier("ui.player.quality.quick.option.\(item.variant.quality)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
