import SwiftUI
import UIKit

/// Custom title row used when the root toolbar is hidden (one visible kind)
/// and on pushed pages. Multi-kind root pages render the same title and menu
/// in the native navigation toolbar instead.
struct DynamicTopBar: View {
    @ObservedObject var titleState: FeedChromeTitleState
    let kinds: [DynamicFeedKind]
    let currentKind: DynamicFeedKind
    let onSelect: (DynamicFeedKind) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if titleState.progress <= 0.9 {
                DynamicTopBarTitle(state: titleState)
            }
            Spacer(minLength: 8)
            if kinds.count > 1 {
                DynamicFeedKindMenu(kinds: kinds, current: currentKind, onSelect: onSelect)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: DynamicTopBarLayout.controlHeight)
        .frame(maxWidth: .infinity)
    }
}

enum DynamicTopBarLayout {
    static let controlHeight: CGFloat = 44
}

struct DynamicTopBarTitle: View {
    @ObservedObject var state: FeedChromeTitleState

    var body: some View {
        let progress = state.progress
        Text(AppTab.dynamic.title)
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: true, vertical: false)
            .offset(y: -progress * FeedChromeTitleState.slideDistance)
            .opacity(1 - progress)
            .accessibilityIdentifier("dynamic.feed.title")
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
    }
}

/// Liquid-glass capsule showing the current feed kind; tapping opens a native
/// menu whose selected kind carries a trailing checkmark.
private struct DynamicFeedKindMenu: View {
    let kinds: [DynamicFeedKind]
    let current: DynamicFeedKind
    let onSelect: (DynamicFeedKind) -> Void

    var body: some View {
        DynamicFeedKindMenuButton(kinds: kinds, current: current, onSelect: onSelect)
            .frame(height: DynamicTopBarLayout.controlHeight)
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}

struct DynamicFeedKindMenuButton: UIViewRepresentable {
    let kinds: [DynamicFeedKind]
    let current: DynamicFeedKind
    let onSelect: (DynamicFeedKind) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.tintColor = .label
        button.accessibilityIdentifier = "dynamic.feedPicker"
        button.accessibilityLabel = "切换动态选项"
        applyConfiguration(to: button)
        button.menu = makeMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        applyConfiguration(to: button)
        button.accessibilityValue = current.title
        button.menu = makeMenu()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        // Size the capsule to its text + chevron rather than stretching to the
        // proposed width, so the control hugs the current option's label.
        let fitting = uiView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: ceil(fitting.width), height: DynamicTopBarLayout.controlHeight)
    }

    private func applyConfiguration(to button: UIButton) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = current.title
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 11,
            weight: .semibold
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 5
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12)
        button.configuration = configuration
    }

    private func makeMenu() -> UIMenu {
        let actions = kinds.map { kind in
            UIAction(
                title: kind.title,
                state: kind == current ? .on : .off
            ) { _ in
                guard kind != current else { return }
                onSelect(kind)
            }
        }
        return UIMenu(title: "", options: .singleSelection, children: actions)
    }
}
