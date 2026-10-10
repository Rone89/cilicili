import SwiftUI
import UIKit

struct HomeFeedNavigationChrome: ViewModifier {
    @Environment(\.rootNavigationTitleHidden) private var rootNavigationTitleHidden
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var viewModel: HomeViewModel
    let modeActions: HomeFeedModeActions
    let scrollActions: HomeFeedScrollActions
    let nativeRefreshActionStore: HomeNativeRefreshActionStore
    let accountMessageViewModel: AccountMessageCenterViewModel?
    let isDetailPresented: Bool
    let onOpenAccountMessages: () -> Void
    let onOpenProfile: (() -> Void)?
    let onOpenRootPage: ((AppTab) -> Void)?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Group {
                        if usesAvatarToolbar {
                            HomeToolbarModePicker(mode: viewModel.mode, onSelectMode: switchMode)
                                .frame(width: 140, height: HomeToolbarLayout.pickerHeight)
                            .accessibilityIdentifier("home.feed.modePicker")
                        } else {
                            navigationTitle
                        }
                    }
                    .font(.headline)
                    .opacity(navigationChromeOpacity)
                    .disabled(hidesNavigationChrome)
                    .accessibilityHidden(hidesNavigationChrome)
                    .animation(.smooth(duration: 0.18), value: hidesNavigationChrome)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Group {
                        if usesAvatarToolbar, let onOpenProfile {
                            HomeProfileButton(viewModel: accountMessageViewModel, action: onOpenProfile, onOpenMessages: onOpenAccountMessages)
                                .buttonBorderShape(.circle)
                        } else {
                            HomeFeedModeMenu(currentMode: viewModel.mode, onSelectMode: switchMode)
                        }
                    }
                    .opacity(navigationChromeOpacity)
                    .disabled(hidesNavigationChrome)
                    .accessibilityHidden(hidesNavigationChrome)
                    .animation(.smooth(duration: 0.18), value: hidesNavigationChrome)
                }
                .sharedBackgroundVisibility(usesAvatarToolbar ? .hidden : toolbarItemBackgroundVisibility)
                ToolbarItem(placement: .topBarTrailing) {
                    Group {
                        if let onOpenRootPage, !hiddenTabs.isEmpty {
                            if hiddenTabs.count == 1, let tab = hiddenTabs.first {
                                Button(tab.title, systemImage: tab == .mine ? "gearshape" : tab.systemImage) {
                                    onOpenRootPage(tab)
                                }
                            } else {
                                Menu {
                                    ForEach(hiddenTabs) { tab in
                                        Button(tab.title, systemImage: tab == .mine ? "gearshape" : tab.systemImage) {
                                            onOpenRootPage(tab)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "circle.grid.2x2")
                                        .foregroundStyle(.primary)
                                }
                                .tint(.primary)
                                .accessibilityLabel("更多页面")
                            }
                        } else {
                            accountMessageButton
                        }
                    }
                    .opacity(navigationChromeOpacity)
                    .disabled(hidesNavigationChrome)
                    .accessibilityHidden(hidesNavigationChrome)
                    .animation(.smooth(duration: 0.18), value: hidesNavigationChrome)
                }
                .sharedBackgroundVisibility(toolbarItemBackgroundVisibility)
            }
            .nativeTopNavigationChrome()
    }

    private var hiddenTabs: [AppTab] {
        [.dynamic, .live, .mine, .search].filter { !libraryStore.visibleRootTabs.contains($0) }
    }

    private var usesAvatarToolbar: Bool {
        libraryStore.homeAvatarNavigationExperimentEnabled && onOpenProfile != nil
    }

    @ViewBuilder
    private var navigationTitle: some View {
        ZStack {
            if viewModel.mode == .recommend {
                modeTitle(.recommend, transitionEdge: .leading)
            } else {
                modeTitle(.popular, transitionEdge: .trailing)
            }
        }
        .frame(width: 64, height: 24)
        .clipped()
        .animation(.smooth(duration: 0.28), value: viewModel.mode)
    }

    private func modeTitle(_ mode: HomeFeedMode, transitionEdge: Edge) -> some View {
        Text(mode.title)
            .frame(width: 64, height: 24)
            .transition(.move(edge: transitionEdge))
    }

    private var hidesNavigationChrome: Bool {
        isDetailPresented || rootNavigationTitleHidden.wrappedValue
    }

    private var navigationChromeOpacity: Double {
        hidesNavigationChrome ? 0 : 1
    }

    private var toolbarItemBackgroundVisibility: Visibility {
        hidesNavigationChrome ? .hidden : .automatic
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
        modeActions: HomeFeedModeActions,
        scrollActions: HomeFeedScrollActions,
        nativeRefreshActionStore: HomeNativeRefreshActionStore,
        accountMessageViewModel: AccountMessageCenterViewModel?,
        isDetailPresented: Bool = false,
        onOpenAccountMessages: @escaping () -> Void,
        onOpenRootPage: ((AppTab) -> Void)? = nil,
        onOpenProfile: (() -> Void)? = nil
    ) -> some View {
        modifier(
            HomeFeedNavigationChrome(
                viewModel: viewModel,
                modeActions: modeActions,
                scrollActions: scrollActions,
                nativeRefreshActionStore: nativeRefreshActionStore,
                accountMessageViewModel: accountMessageViewModel,
                isDetailPresented: isDetailPresented,
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
        }
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

    private var mineIsHidden: Bool { !libraryStore.visibleRootTabs.contains(.mine) }

    var body: some View {
        Group {
            if mineIsHidden {
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
        .overlay {
            if mineIsHidden && sessionStore.isLoggedIn && hasUnread {
                Circle().strokeBorder(appTintColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(mineIsHidden ? "个人空间与账户消息" : "个人空间")
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
    static let pickerHeight: CGFloat = 36
}

/// Keep the native segmented control compact within the navigation toolbar.
private struct HomeToolbarModePicker: UIViewRepresentable {
    let mode: HomeFeedMode
    let onSelectMode: (HomeFeedMode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectMode: onSelectMode)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: HomeFeedMode.allCases.map(\.title))
        control.addTarget(context.coordinator, action: #selector(Coordinator.selectionChanged(_:)), for: .valueChanged)
        control.accessibilityLabel = "首页内容"
        control.accessibilityIdentifier = "home.feed.modePicker"
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.onSelectMode = onSelectMode
        control.selectedSegmentIndex = HomeFeedMode.allCases.firstIndex(of: mode) ?? 0
        control.isEnabled = context.environment.isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: HomeToolbarLayout.pickerHeight)
    }

    final class Coordinator: NSObject {
        var onSelectMode: (HomeFeedMode) -> Void

        init(onSelectMode: @escaping (HomeFeedMode) -> Void) {
            self.onSelectMode = onSelectMode
        }

        @objc func selectionChanged(_ control: UISegmentedControl) {
            guard HomeFeedMode.allCases.indices.contains(control.selectedSegmentIndex) else { return }
            onSelectMode(HomeFeedMode.allCases[control.selectedSegmentIndex])
        }
    }
}
