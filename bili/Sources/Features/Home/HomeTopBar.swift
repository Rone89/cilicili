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
            HomeModeMenuButton(
                selection: selection,
                hiddenTabs: hiddenTabs,
                onSelect: onSelect,
                onOpenRootPage: actions.onOpenRootPage
            )
        }

        ToolbarItem(placement: .topBarTrailing) {
            HomeTopBarProfileButton(actions: actions)
        }
    }
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

/// Native SwiftUI menu button to pick the home feed mode (and hidden root tabs
/// when tabs are collapsed). Staying pure SwiftUI lets iOS 26/27 Liquid Glass
/// group it with the profile button horizontally on regular screens and
/// vertically inside the right rail on iPhone Duo's cover display.
private struct HomeModeMenuButton: View {
    let selection: HomePageSelection
    let hiddenTabs: [AppTab]
    let onSelect: (HomePageSelection) -> Void
    let onOpenRootPage: (AppTab) -> Void

    private var selectionTitleBinding: Binding<String> {
        Binding(
            get: { selection.title },
            set: { title in
                guard let item = HomePageSelection.menuOrder.first(where: { $0.title == title }),
                      item != selection
                else { return }
                onSelect(item)
            }
        )
    }

    var body: some View {
        Menu {
            Picker("切换首页页面", selection: selectionTitleBinding) {
                ForEach(HomePageSelection.menuOrder, id: \.title) { item in
                    Text(item.title).tag(item.title)
                }
            }

            if !hiddenTabs.isEmpty {
                Section {
                    ForEach(hiddenTabs, id: \.self) { tab in
                        Button {
                            onOpenRootPage(tab)
                        } label: {
                            Label(
                                tab.title,
                                systemImage: tab == .mine ? "slider.horizontal.3" : tab.systemImage
                            )
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        .accessibilityLabel("切换首页页面")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("home.feed.modeMenu")
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
    @State private var usesHorizontalBarOpticalOffset = true
    let hasUnread: Bool
    let action: () -> Void
    let onOpenMessages: () -> Void

    private var horizontalOpticalOffset: CGFloat {
        usesHorizontalBarOpticalOffset ? 5 : 0
    }

    var body: some View {
        let showsUnread = sessionStore.isLoggedIn && hasUnread
        Menu {
            Button("个人空间", systemImage: "person.crop.circle", action: action)
            Button("消息", systemImage: "bubble.left.and.bubble.right", action: onOpenMessages)
        } label: {
            avatar
                .overlay(alignment: .topLeading) { unreadDot(showsUnread: showsUnread) }
                .offset(x: horizontalOpticalOffset)
                .onGeometryChange(for: Bool.self) { proxy in
                    // Regular top navigation bars (iPhone, iPad, Duo inner screen)
                    // place toolbar items near the top edge (minY < 130pt), whereas
                    // iPhone Duo's outer cover screen moves them into a vertical
                    // right rail below the top status area (minY > 180pt) where
                    // the circular avatar is already concentric with the end cap.
                    proxy.frame(in: .global).minY < 130
                } action: { isInTopHorizontalBar in
                    usesHorizontalBarOpticalOffset = isInTopHorizontalBar
                }
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
