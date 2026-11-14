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

/// Page-owned home top bar.
///
/// Unlike the previous native toolbar implementation, this bar lives inside the
/// home content, so it slides out with the home page on push and slides back on
/// pop instead of being restored by the navigation chrome mid-transition.
struct HomeTopBar: View {
    @Environment(\.homeTopBarActions) private var actions
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var titleState: HomeChromeTitleState
    let modeActions: HomeFeedModeActions
    let scrollActions: HomeFeedScrollActions
    let nativeRefreshActionStore: HomeNativeRefreshActionStore

    private var hiddenTabs: [AppTab] {
        [.dynamic, .live, .mine, .search].filter { !libraryStore.visibleRootTabs.contains($0) }
    }

    var body: some View {
        HStack(spacing: 10) {
            if titleState.progress <= 0.9 {
                HomeTopBarTitle(title: viewModel.mode.title, state: titleState)
            }
            Spacer(minLength: 8)
            HomeTopBarModeMenu(
                mode: viewModel.mode,
                hiddenTabs: hiddenTabs,
                onSelect: switchMode,
                onOpenRootPage: actions.onOpenRootPage
            )
            if hiddenTabs.isEmpty {
                HomeTopBarMessageButton(actions: actions)
            }
            HomeTopBarProfileButton(actions: actions)
        }
        .padding(.horizontal, 16)
        .frame(height: HomeTopBarLayout.controlHeight)
        .frame(maxWidth: .infinity)
    }

    private func switchMode(_ mode: HomeFeedMode) {
        modeActions.switchMode(
            mode,
            viewModel: viewModel,
            scrollActions: scrollActions,
            nativeRefreshActionStore: nativeRefreshActionStore
        )
    }
}

enum HomeTopBarLayout {
    static let controlHeight: CGFloat = 44
}

private struct HomeTopBarTitle: View {
    let title: String
    @ObservedObject var state: HomeChromeTitleState

    var body: some View {
        let progress = state.progress
        Text(title)
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: true, vertical: false)
            .offset(y: -progress * HomeChromeTitleState.slideDistance)
            .opacity(1 - progress)
            .accessibilityIdentifier("home.feed.title")
            .accessibilityAddTraits(.isHeader)
            .allowsHitTesting(false)
    }
}

/// Liquid-glass icon button that opens a native single-selection menu to pick
/// the feed mode. When some root tabs are hidden from the bottom bar, their
/// entries join the same menu as a second group. UIKit's UIMenu keeps the
/// checkmark on the trailing edge and sizes the menu to its content (narrow),
/// which SwiftUI's Menu does not guarantee across OS versions.
private struct HomeTopBarModeMenu: View {
    let mode: HomeFeedMode
    let hiddenTabs: [AppTab]
    let onSelect: (HomeFeedMode) -> Void
    let onOpenRootPage: (AppTab) -> Void

    var body: some View {
        HomeModeMenuButton(
            mode: mode,
            hiddenTabs: hiddenTabs,
            onSelect: onSelect,
            onOpenRootPage: onOpenRootPage
        )
        .frame(width: HomeTopBarLayout.controlHeight, height: HomeTopBarLayout.controlHeight)
        .glassEffect(.regular.interactive(), in: Circle())
    }
}

private struct HomeModeMenuButton: UIViewRepresentable {
    let mode: HomeFeedMode
    let hiddenTabs: [AppTab]
    let onSelect: (HomeFeedMode) -> Void
    let onOpenRootPage: (AppTab) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.tintColor = .label
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.setImage(
            UIImage(systemName: "line.3.horizontal.decrease", withConfiguration: configuration),
            for: .normal
        )
        button.accessibilityIdentifier = "home.feed.modeMenu"
        button.accessibilityLabel = "切换推荐或热门"
        button.menu = makeMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.accessibilityValue = mode.title
        button.menu = makeMenu()
    }

    private func makeMenu() -> UIMenu {
        let modeActions = HomeFeedMode.allCases.map { item in
            UIAction(
                title: item.title,
                state: item == mode ? .on : .off
            ) { _ in
                guard item != mode else { return }
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

private struct HomeTopBarMessageButton: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let actions: HomeTopBarActions

    var body: some View {
        if let viewModel = actions.accountMessageViewModel {
            HomeTopBarMessageButtonWithUnread(viewModel: viewModel, action: actions.onOpenMessages)
        } else {
            HomeTopBarMessageButtonContent(hasUnread: false, action: actions.onOpenMessages)
        }
    }
}

private struct HomeTopBarMessageButtonWithUnread: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    let action: () -> Void

    var body: some View {
        HomeTopBarMessageButtonContent(hasUnread: viewModel.hasUnreadMessages, action: action)
    }
}

private struct HomeTopBarMessageButtonContent: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let hasUnread: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hasUnread ? appTintColor : Color.primary)
                .frame(width: HomeTopBarLayout.controlHeight, height: HomeTopBarLayout.controlHeight)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("账号消息")
        .accessibilityValue(hasUnread ? "有未读消息" : "全部已读")
        .accessibilityIdentifier("home.account.messages")
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
    @EnvironmentObject private var libraryStore: LibraryStore
    let hasUnread: Bool
    let action: () -> Void
    let onOpenMessages: () -> Void

    private var hasHiddenTabs: Bool {
        AppTab.allCases.contains { !libraryStore.visibleRootTabs.contains($0) }
    }

    var body: some View {
        ZStack {
            Group {
                if hasHiddenTabs {
                    Menu {
                        Button("个人空间", systemImage: "person.crop.circle", action: action)
                        Button("账户消息", systemImage: "bell", action: onOpenMessages)
                    } label: { avatar }
                } else {
                    Button(action: action) { avatar }
                }
            }
            .buttonStyle(.plain)
            .frame(width: HomeTopBarLayout.controlHeight, height: HomeTopBarLayout.controlHeight)
            .glassEffect(.regular.interactive(), in: Circle())

            // Keep unread status outside the menu's animated source control.
            Circle().strokeBorder(appTintColor, lineWidth: 2)
                .frame(width: HomeTopBarLayout.controlHeight, height: HomeTopBarLayout.controlHeight)
                .opacity(hasHiddenTabs && sessionStore.isLoggedIn && hasUnread ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
        }
        .accessibilityLabel(hasHiddenTabs ? "个人空间与账户消息" : "个人空间")
        .accessibilityValue(sessionStore.isLoggedIn ? (hasUnread ? "有未读消息" : "全部已读") : "未登录")
        .accessibilityIdentifier("home.account.avatar")
    }

    private var avatar: some View {
        AvatarRemoteImage(urlString: sessionStore.isLoggedIn ? sessionStore.user?.face : nil, pixelSize: 96) {
            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
        }
        .frame(width: HomeTopBarLayout.controlHeight - 4, height: HomeTopBarLayout.controlHeight - 4)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
