import SwiftUI

struct DynamicView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        DynamicContentRoot(
            api: dependencies.api,
            libraryStore: libraryStore,
            sessionStore: dependencies.sessionStore
        )
    }
}

private struct DynamicContentRoot: View {
    @Environment(\.rootNavigationTitleHidden) private var rootNavigationTitleHidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let api: BiliAPIClient
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var holder: DynamicViewModelHolder
    @State private var selectedFeed: DynamicFeedKind = .all
    @State private var hidesNavigationChrome = false
    @State private var selectedUP: VideoOwner?
    @State private var showsUPSelector = false

    private var categoriesEnabled: Bool { libraryStore.dynamicFeedCategoriesExperimentEnabled }

    init(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        self.api = api
        self.libraryStore = libraryStore
        self.sessionStore = sessionStore
        _holder = StateObject(
            wrappedValue: DynamicViewModelHolder(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore
            )
        )
    }

    var body: some View {
        Group {
            if categoriesEnabled, selectedFeed == .up, selectedUP == nil {
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
                .nativeTopScrollEdgeEffect()
                .task { holder.topUploaderStripViewModel?.loadTopUploaderStripIfNeeded() }
            } else if let viewModel = holder.viewModel {
                DynamicFeedScreenContent(
                    api: api,
                    viewModel: viewModel,
                    topUploaderStripViewModel: holder.topUploaderStripViewModel ?? viewModel,
                    isLoggedIn: sessionStore.isLoggedIn,
                    selectedUP: categoriesEnabled && selectedFeed == .up ? selectedUP : nil,
                    onChooseUP: { showsUPSelector = true }
                )
                .id(categoriesEnabled ? ObjectIdentifier(viewModel) : ObjectIdentifier(holder))
            } else {
                DynamicInitialFeedContent(isLoggedIn: sessionStore.isLoggedIn)
            }
        }
        .environment(\.rootNavigationTitleHidden, navigationChromeVisibility)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("动态内容", selection: $selectedFeed) {
                    ForEach(categoriesEnabled ? DynamicFeedKind.allCases : [.all, .video], id: \.self) { kind in
                        Text(!categoriesEnabled && kind == .video ? "视频" : kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: categoriesEnabled ? nil : 180)
                .frame(maxWidth: categoriesEnabled ? 340 : nil)
                .accessibilityIdentifier("dynamic.feedPicker")
                .opacity(hidesNavigationChrome ? 0 : 1)
                .disabled(hidesNavigationChrome)
                .accessibilityHidden(hidesNavigationChrome)
                .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: hidesNavigationChrome)
            }
            .sharedBackgroundVisibility(hidesNavigationChrome ? .hidden : .automatic)
        }
        .onChange(of: selectedFeed) { _, kind in
            hidesNavigationChrome = false
            if kind == .up, selectedUP == nil {
                if sessionStore.isLoggedIn { showsUPSelector = true }
            } else {
                selectFeed(kind)
            }
        }
        .onChange(of: categoriesEnabled) { _, _ in resetFeeds() }
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
                selectFeed(.up)
                hidesNavigationChrome = false
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
        selectedFeed = .all
        hidesNavigationChrome = false
        holder.reconfigure(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }

    private var navigationChromeVisibility: Binding<Bool> {
        Binding(
            get: { hidesNavigationChrome },
            set: { isHidden in
                // Keep a local signal for dynamic pages pushed from Home, where
                // the root title binding intentionally ignores destination scrolls.
                hidesNavigationChrome = isHidden
                rootNavigationTitleHidden.wrappedValue = isHidden
            }
        )
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
