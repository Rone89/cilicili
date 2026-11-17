import SwiftUI

struct DynamicView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        GeometryReader { proxy in
            DynamicContentRoot(
                api: dependencies.api,
                libraryStore: libraryStore,
                sessionStore: dependencies.sessionStore,
                pageWidth: proxy.size.width
            )
        }
    }
}

struct DynamicContentRoot: View {
    @Environment(\.isRootTabContent) private var isRootTabContent
    @Environment(\.showsHiddenRootPageSwitcher) private var showsHiddenRootPageSwitcher
    let api: BiliAPIClient
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    let pageWidth: CGFloat
    @StateObject private var holder: DynamicViewModelHolder
    @StateObject private var titleState = FeedChromeTitleState()
    @State private var selectedFeed: DynamicFeedKind
    @State private var selectedUP: VideoOwner?
    @State private var showsUPSelector = false

    init(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore, pageWidth: CGFloat) {
        self.api = api
        self.libraryStore = libraryStore
        self.sessionStore = sessionStore
        self.pageWidth = pageWidth
        _holder = StateObject(
            wrappedValue: DynamicViewModelHolder(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore
            )
        )
        _selectedFeed = State(initialValue: libraryStore.visibleDynamicFeedKinds.first ?? .all)
    }

    private var visibleFeedKinds: [DynamicFeedKind] {
        libraryStore.visibleDynamicFeedKinds
    }

    private var usesRootNavigationToolbar: Bool {
        isRootTabContent && (visibleFeedKinds.count > 1 || showsHiddenRootPageSwitcher)
    }

    var body: some View {
        Group {
            if selectedFeed == .up, selectedUP == nil {
                ScrollView {
                    if let strip = holder.topUploaderStripViewModel {
                        FollowedLiveStrip(items: strip.topUploaderStripItems, isLoading: strip.isTopUploaderStripLoading)
                            .padding(.horizontal, libraryStore.standardPageHorizontalInset)
                    }
                    ContentUnavailableView {
                        Label("选择 UP 主", systemImage: "person.crop.circle")
                    } description: {
                        Text(sessionStore.isLoggedIn ? "选择一个 UP 主，查看 TA 的动态。" : "登录后可选择 UP 主查看动态。")
                    } actions: {
                        Button("选择 UP 主") { showsUPSelector = true }
                            .disabled(!sessionStore.isLoggedIn)
                    }
                }
                .rootFloatingTabBarContentPadding()
                .nativeTopScrollEdgeEffect(hidesRootNavigationTitle: false)
                .task { holder.topUploaderStripViewModel?.loadTopUploaderStripIfNeeded() }
            } else if let viewModel = holder.viewModel {
                DynamicFeedScreenContent(
                    api: api,
                    viewModel: viewModel,
                    topUploaderStripViewModel: holder.topUploaderStripViewModel ?? viewModel,
                    isLoggedIn: sessionStore.isLoggedIn,
                    selectedUP: selectedFeed == .up ? selectedUP : nil,
                    onChooseUP: { showsUPSelector = true },
                    titleState: titleState
                )
            } else {
                DynamicInitialFeedContent(isLoggedIn: sessionStore.isLoggedIn)
            }
        }
        .contentMargins(.top, usesRootNavigationToolbar ? 12 : 0, for: .scrollContent)
        .safeAreaInset(edge: .top, spacing: usesRootNavigationToolbar ? 0 : 12) {
            if !usesRootNavigationToolbar {
                DynamicTopBar(
                    titleState: titleState,
                    kinds: visibleFeedKinds,
                    currentKind: selectedFeed,
                    onSelect: { selectedFeed = $0 }
                )
            }
        }
        .toolbarVisibility(
            usesRootNavigationToolbar ? .visible : (isRootTabContent ? .hidden : .visible),
            for: .navigationBar
        )
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if usesRootNavigationToolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DynamicTopBarTitle(state: titleState)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            if usesRootNavigationToolbar && visibleFeedKinds.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    DynamicFeedKindMenuButton(
                        kinds: visibleFeedKinds,
                        current: selectedFeed,
                        onSelect: { selectedFeed = $0 }
                    )
                }
            }
        }
        .onChange(of: selectedFeed) { _, kind in
            titleState.reset()
            if kind == .up, selectedUP == nil {
                if sessionStore.isLoggedIn { showsUPSelector = true }
            }
        }
        .onChange(of: libraryStore.visibleDynamicFeedKinds) { _, kinds in
            guard !kinds.contains(selectedFeed) else { return }
            showsUPSelector = false
            selectedUP = nil
            selectedFeed = kinds.first ?? .all
        }
        .onAppear {
            // With a single configured kind there is no segment tap to enter the
            // UP selection, so offer the sheet once when the page appears.
            guard visibleFeedKinds.count <= 1, selectedFeed == .up, selectedUP == nil,
                  sessionStore.isLoggedIn else { return }
            showsUPSelector = true
        }
        .task(id: DynamicFeedQuery(kind: selectedFeed, hostMID: selectedUP?.mid)) {
            // Commit the control's selection before updating the feed subtree.
            // A newer selection cancels this activation without a fixed delay.
            await Task.yield()
            guard !Task.isCancelled, selectedFeed != .up || selectedUP != nil else { return }
            selectFeed(selectedFeed)
        }
        .onChange(of: DynamicFeedAccountContext(
            mainCredentialVersion: sessionStore.playbackCredentialVersion,
            dynamicFeedCredentialVersion: sessionStore.dynamicFeedAccountCredentialVersion,
            multiAccountEnabled: libraryStore.multiAccountEnabled
        )) { _, _ in
            resetFeeds()
        }
        .sheet(isPresented: $showsUPSelector) {
            DynamicUPSelector(api: api, recentOwners: holder.topUploaderStripViewModel?.topUploaderStripItems.map(\.owner) ?? []) { owner in
                selectedUP = owner
            }
        }
    }

    private func selectFeed(_ kind: DynamicFeedKind) {
        holder.selectFeed(kind, hostMID: kind == .up ? selectedUP?.mid : nil,
                          api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }

    private func resetFeeds() {
        showsUPSelector = false
        selectedUP = nil
        selectedFeed = visibleFeedKinds.first ?? .all
        holder.reconfigure(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }
}

private struct DynamicFeedAccountContext: Equatable {
    let mainCredentialVersion: Int
    let dynamicFeedCredentialVersion: Int
    let multiAccountEnabled: Bool
}

extension View {
    @ViewBuilder
    func dynamicLoadMoreTask<ID: Equatable>(
        if condition: Bool,
        id: ID,
        action: @escaping () async -> Void
    ) -> some View {
        if condition {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}
