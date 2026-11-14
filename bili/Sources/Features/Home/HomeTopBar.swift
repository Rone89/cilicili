import SwiftUI

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
                HomeTopBarTitle(state: titleState)
            }
            Spacer(minLength: 8)
            HomeTopBarModeButtons(mode: viewModel.mode, onSelect: switchMode)
            HomeTopBarAccessory(hiddenTabs: hiddenTabs, actions: actions)
            HomeTopBarProfileButton(actions: actions)
        }
        .padding(.horizontal, 16)
        .frame(height: HomeTopBarLayout.controlHeight)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            HomeTopEdgeBackground()
        }
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

/// Soft top edge matching Ibili: a compositor-backed material masked by a
/// top-to-bottom gradient so the chrome melts into the feed instead of ending
/// in a hard line. Extends below the bar row and up under the status bar.
private struct HomeTopEdgeBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.9), location: 0.62),
                            .init(color: .black.opacity(0.35), location: 0.85),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.20), location: 0),
                    .init(color: Color.black.opacity(0.08), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: HomeTopBarLayout.edgeBackgroundHeight)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

private enum HomeTopBarLayout {
    static let controlHeight: CGFloat = 44
    static let edgeBackgroundHeight: CGFloat = 126
}

private struct HomeTopBarTitle: View {
    @ObservedObject var state: HomeChromeTitleState

    var body: some View {
        let progress = state.progress
        Text(AppTab.home.title)
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

private struct HomeTopBarModeButtons: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let mode: HomeFeedMode
    let onSelect: (HomeFeedMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HomeFeedMode.allCases) { item in
                Button {
                    guard item != mode else { return }
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(.body.weight(item == mode ? .semibold : .regular))
                        .foregroundStyle(item == mode ? libraryStore.appTintColor : Color.primary.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(minWidth: HomeTopBarLayout.controlHeight, minHeight: HomeTopBarLayout.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == mode ? .isSelected : [])
                .accessibilityIdentifier("home.feed.mode.\(item.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.feed.modePicker")
    }
}

private struct HomeTopBarAccessory: View {
    let hiddenTabs: [AppTab]
    let actions: HomeTopBarActions

    var body: some View {
        if !hiddenTabs.isEmpty {
            if hiddenTabs.count == 1, let tab = hiddenTabs.first {
                Button {
                    actions.onOpenRootPage(tab)
                } label: {
                    accessoryIcon(tab == .mine ? "slider.horizontal.3" : tab.systemImage)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            } else {
                Menu {
                    ForEach(hiddenTabs) { tab in
                        Button(tab.title, systemImage: tab == .mine ? "slider.horizontal.3" : tab.systemImage) {
                            actions.onOpenRootPage(tab)
                        }
                    }
                } label: {
                    accessoryIcon("circle.grid.2x2")
                }
                .accessibilityLabel("更多页面")
            }
        } else {
            HomeTopBarMessageButton(actions: actions)
        }
    }

    private func accessoryIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: HomeTopBarLayout.controlHeight, height: HomeTopBarLayout.controlHeight)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
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
