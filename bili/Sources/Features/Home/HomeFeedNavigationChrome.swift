import SwiftUI
import UIKit

struct HomeFeedNavigationChrome: ViewModifier {
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var titleState: HomeChromeTitleState
    let modeActions: HomeFeedModeActions
    let scrollActions: HomeFeedScrollActions
    let nativeRefreshActionStore: HomeNativeRefreshActionStore
    let accountMessageViewModel: AccountMessageCenterViewModel?
    let onOpenAccountMessages: () -> Void
    let onOpenProfile: () -> Void
    let onOpenRootPage: ((AppTab) -> Void)?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if titleState.progress <= 0.9 {
                        HomeToolbarTitle(state: titleState)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        HomeToolbarModeButtons(
                            mode: viewModel.mode,
                            onSelect: switchMode
                        )
                        trailingAccessory
                        HomeProfileButton(
                            viewModel: accountMessageViewModel,
                            action: onOpenProfile,
                            onOpenMessages: onOpenAccountMessages
                        )
                        .buttonBorderShape(.circle)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .nativeTopNavigationChrome()
    }

    private var hiddenTabs: [AppTab] {
        [.dynamic, .live, .mine, .search].filter { !libraryStore.visibleRootTabs.contains($0) }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if let onOpenRootPage, !hiddenTabs.isEmpty {
            if hiddenTabs.count == 1, let tab = hiddenTabs.first {
                Button {
                    onOpenRootPage(tab)
                } label: {
                    toolbarIcon(tab == .mine ? "slider.horizontal.3" : tab.systemImage)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            } else {
                Menu {
                    ForEach(hiddenTabs) { tab in
                        Button(tab.title, systemImage: tab == .mine ? "slider.horizontal.3" : tab.systemImage) {
                            onOpenRootPage(tab)
                        }
                    }
                } label: {
                    toolbarIcon("circle.grid.2x2")
                }
                .accessibilityLabel("更多页面")
            }
        } else {
            accountMessageButton
        }
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: HomeToolbarLayout.controlHeight, height: HomeToolbarLayout.controlHeight)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
    }

    @ViewBuilder
    private var accountMessageButton: some View {
        if let accountMessageViewModel {
            HomeAccountMessageButton(
                viewModel: accountMessageViewModel,
                action: onOpenAccountMessages
            )
        } else {
            HomeAccountMessageButtonContent(
                hasUnread: false,
                action: onOpenAccountMessages
            )
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

extension View {
    func homeFeedNavigationChrome(
        viewModel: HomeViewModel,
        titleState: HomeChromeTitleState,
        modeActions: HomeFeedModeActions,
        scrollActions: HomeFeedScrollActions,
        nativeRefreshActionStore: HomeNativeRefreshActionStore,
        accountMessageViewModel: AccountMessageCenterViewModel?,
        onOpenAccountMessages: @escaping () -> Void,
        onOpenRootPage: ((AppTab) -> Void)? = nil,
        onOpenProfile: @escaping () -> Void
    ) -> some View {
        modifier(
            HomeFeedNavigationChrome(
                viewModel: viewModel,
                titleState: titleState,
                modeActions: modeActions,
                scrollActions: scrollActions,
                nativeRefreshActionStore: nativeRefreshActionStore,
                accountMessageViewModel: accountMessageViewModel,
                onOpenAccountMessages: onOpenAccountMessages,
                onOpenProfile: onOpenProfile,
                onOpenRootPage: onOpenRootPage
            )
        )
    }
}

private struct HomeAccountMessageButton: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    let action: () -> Void

    var body: some View {
        HomeAccountMessageButtonContent(hasUnread: viewModel.hasUnreadMessages, action: action)
    }
}

private struct HomeAccountMessageButtonContent: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let hasUnread: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hasUnread ? appTintColor : Color.primary)
                .frame(width: HomeToolbarLayout.controlHeight, height: HomeToolbarLayout.controlHeight)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("账号消息")
        .accessibilityValue(hasUnread ? "有未读消息" : "全部已读")
        .accessibilityIdentifier("home.account.messages")
    }
}

private struct HomeProfileButton: View {
    let viewModel: AccountMessageCenterViewModel?
    let action: () -> Void
    let onOpenMessages: () -> Void

    var body: some View {
        if let viewModel {
            HomeProfileButtonWithUnread(viewModel: viewModel, action: action, onOpenMessages: onOpenMessages)
        } else {
            HomeProfileButtonContent(hasUnread: false, action: action, onOpenMessages: onOpenMessages)
        }
    }
}

private struct HomeProfileButtonWithUnread: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    let action: () -> Void
    let onOpenMessages: () -> Void

    var body: some View {
        HomeProfileButtonContent(hasUnread: viewModel.hasUnreadMessages, action: action, onOpenMessages: onOpenMessages)
    }
}

private struct HomeProfileButtonContent: View {
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
            .frame(width: HomeToolbarLayout.controlHeight, height: HomeToolbarLayout.controlHeight)
            .glassEffect(.regular.interactive(), in: Circle())

            // Keep unread status outside the menu's animated source control.
            // Dismissing the menu must not fade the ring back in with its label.
            Circle().strokeBorder(appTintColor, lineWidth: 2)
                .frame(width: HomeToolbarLayout.controlHeight, height: HomeToolbarLayout.controlHeight)
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
        .frame(width: HomeToolbarLayout.controlHeight - 4, height: HomeToolbarLayout.controlHeight - 4)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private enum HomeToolbarLayout {
    static let controlHeight: CGFloat = 44
}

/// Ibili-style floating root title: large, left aligned, and driven by the
/// home scroll offset instead of a native large-title collapse.
private struct HomeToolbarTitle: View {
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

/// Text mode switch that replaces the centered segmented control so the title
/// can own the leading edge, matching Ibili's feed header.
private struct HomeToolbarModeButtons: View {
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
                        .frame(minWidth: HomeToolbarLayout.controlHeight, minHeight: HomeToolbarLayout.controlHeight)
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
