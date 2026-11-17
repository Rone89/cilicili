import SwiftUI
import UIKit

/// Actions wired by the root tab shell for the home top bar.
struct HomeTopBarActions {
    let accountMessageViewModel: AccountMessageCenterViewModel?
    let onOpenProfile: () -> Void
    let onOpenMessages: () -> Void
    let onOpenRootPage: (AppTab) -> Void

    static let none = HomeTopBarActions(
        accountMessageViewModel: nil,
        onOpenProfile: {},
        onOpenMessages: {},
        onOpenRootPage: { _ in }
    )
}

private struct HomeTopBarActionsKey: EnvironmentKey {
    static let defaultValue = HomeTopBarActions.none
}

extension EnvironmentValues {
    var homeTopBarActions: HomeTopBarActions {
        get { self[HomeTopBarActionsKey.self] }
        set { self[HomeTopBarActionsKey.self] = newValue }
    }
}

struct HomeTopBar: ToolbarContent {
    let selection: HomePageSelection
    let titleState: FeedChromeTitleState
    let hiddenTabs: [AppTab]
    let actions: HomeTopBarActions
    let liveViewModel: LiveViewModel?
    let onSelect: (HomePageSelection) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            FeedToolbarTitle(title: selection.title, state: titleState, accessibilityID: "home.feed.title")
        }
        .sharedBackgroundVisibility(.hidden)

        if let liveViewModel {
            ToolbarItem(placement: .topBarTrailing) {
                LiveRefreshToolbarButton(
                    isLoading: liveViewModel.isRefreshing || (liveViewModel.rooms.isEmpty && liveViewModel.state.isLoading)
                ) {
                    Task { await liveViewModel.refresh() }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: HomeTopBarLayout.capsuleActionSpacing) {
                HomeModeMenuButton(
                    selection: selection,
                    hiddenTabs: hiddenTabs,
                    onSelect: onSelect,
                    onOpenRootPage: actions.onOpenRootPage
                )
                .frame(width: HomeTopBarLayout.controlHeight, height: HomeTopBarLayout.controlHeight)

                HomeTopBarProfileButton(actions: actions)
                    .frame(width: HomeTopBarLayout.controlHeight, height: HomeTopBarLayout.controlHeight)
            }
            .frame(height: HomeTopBarLayout.controlHeight)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

private enum HomeTopBarLayout {
    static let controlHeight: CGFloat = 44
    static let capsuleActionSpacing: CGFloat = 20
}

struct FeedToolbarTitle: View {
    let title: String
    @ObservedObject var state: FeedChromeTitleState
    let accessibilityID: String

    var body: some View {
        let progress = state.progress
        Text(title)
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: true, vertical: false)
            .offset(y: -progress * FeedChromeTitleState.slideDistance)
            .opacity(progress <= 0.9 ? 1 - progress : 0)
            .accessibilityHidden(progress > 0.9)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
    }
}

/// Toolbar-safe variant of `FeedToolbarTitle`: removes the text node from the
/// hosting view once scrolled past `0.9` so UIKit `UIBarButtonItem` does not
/// keep an invisible static text in the accessibility hierarchy.
struct FeedScrolledToolbarTitle: View {
    let title: String
    let accessibilityID: String
    @ObservedObject var state: FeedChromeTitleState

    var body: some View {
        if state.progress <= 0.9 {
            FeedToolbarTitle(title: title, state: state, accessibilityID: accessibilityID)
        } else {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
    }
}

/// Liquid-glass icon button that opens a native single-selection menu to pick
/// the feed mode. When some root tabs are hidden from the bottom bar, their
/// entries join the same menu as a second group. UIKit's UIMenu keeps the
/// checkmark on the trailing edge and sizes the menu to its content (narrow),
/// which SwiftUI's Menu does not guarantee across OS versions.
private struct HomeModeMenuButton: UIViewRepresentable {
    let selection: HomePageSelection
    let hiddenTabs: [AppTab]
    let onSelect: (HomePageSelection) -> Void
    let onOpenRootPage: (AppTab) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.tintColor = .label
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        button.setImage(
            UIImage(systemName: "line.3.horizontal.decrease", withConfiguration: configuration),
            for: .normal
        )
        button.accessibilityIdentifier = "home.feed.modeMenu"
        button.accessibilityLabel = "切换首页页面"
        button.menu = makeMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.accessibilityValue = selection.title
        button.menu = makeMenu()
    }

    private func makeMenu() -> UIMenu {
        let modeActions = HomePageSelection.menuOrder.map { item in
            UIAction(
                title: item.title,
                state: item == selection ? .on : .off
            ) { _ in
                guard item != selection else { return }
                onSelect(item)
            }
        }
        guard !hiddenTabs.isEmpty else {
            return UIMenu(title: "", options: .singleSelection, children: modeActions)
        }
        let modeSection = UIMenu(
            title: "",
            options: [.displayInline, .singleSelection],
            children: modeActions
        )
        let navActions = hiddenTabs.map { tab in
            UIAction(
                title: tab.title,
                image: UIImage(systemName: tab == .mine ? "slider.horizontal.3" : tab.systemImage)
            ) { _ in
                onOpenRootPage(tab)
            }
        }
        let navSection = UIMenu(title: "", options: .displayInline, children: navActions)
        return UIMenu(title: "", children: [modeSection, navSection])
    }
}

private struct HomeTopBarProfileButton: View {
    let actions: HomeTopBarActions

    var body: some View {
        if let viewModel = actions.accountMessageViewModel {
            HomeTopBarProfileButtonWithUnread(
                viewModel: viewModel,
                action: actions.onOpenProfile,
                onOpenMessages: actions.onOpenMessages
            )
        } else {
            HomeTopBarProfileButtonContent(
                hasUnread: false,
                action: actions.onOpenProfile,
                onOpenMessages: actions.onOpenMessages
            )
        }
    }
}

private struct HomeTopBarProfileButtonWithUnread: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    let action: () -> Void
    let onOpenMessages: () -> Void

    var body: some View {
        HomeTopBarProfileButtonContent(
            hasUnread: viewModel.hasUnreadMessages,
            action: action,
            onOpenMessages: onOpenMessages
        )
    }
}

private struct HomeTopBarProfileButtonContent: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @EnvironmentObject private var sessionStore: SessionStore
    let hasUnread: Bool
    let action: () -> Void
    let onOpenMessages: () -> Void

    var body: some View {
        let showsUnread = sessionStore.isLoggedIn && hasUnread
        Menu {
            Button("个人空间", systemImage: "person.crop.circle", action: action)
            Button("消息", systemImage: "bubble.left.and.bubble.right", action: onOpenMessages)
        } label: {
            avatar
                .overlay(alignment: .topLeading) { unreadDot(showsUnread: showsUnread) }
                .frame(width: HomeTopBarLayout.controlHeight, height: HomeTopBarLayout.controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("个人空间与消息")
        .accessibilityValue(sessionStore.isLoggedIn ? (hasUnread ? "有未读消息" : "全部已读") : "未登录")
        .accessibilityIdentifier("home.account.avatar")
    }

    /// Unread badge overlaid on the avatar view itself so its position rides
    /// with whatever transform the toolbar/Menu applies to the label content —
    /// as a ZStack sibling it drifted away from the photo on device (193).
    /// The center sits on the photo circle's upper-left edge (45° diagonal).
    private func unreadDot(showsUnread: Bool) -> some View {
        Circle()
            .fill(appTintColor)
            .frame(width: 8, height: 8)
            .offset(x: 1, y: 1)
            .opacity(showsUnread ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
    }

    private var avatar: some View {
        AvatarRemoteImage(urlString: sessionStore.isLoggedIn ? sessionStore.user?.face : nil, pixelSize: 96) {
            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
