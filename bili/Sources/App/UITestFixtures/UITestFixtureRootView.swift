import Foundation
import SwiftUI

/// A network-free host for production UI components used by XCUITest.
struct UITestFixtureRootView: View {
    let scenario: UITestFixtureScenario
    @StateObject private var dependencies = AppDependencies()

    var body: some View {
        Group {
            switch scenario {
            case .danmaku:
                UITestDanmakuFixtureView(libraryStore: dependencies.libraryStore)
            #if DEBUG
            case .danmakuBenchmark:
                NavigationStack { DanmakuRendererBenchmarkView() }
            #endif
            case .dynamicDetail:
                UITestDynamicDetailFixtureView(
                    api: dependencies.api
                )
            case .fullscreen:
                UITestPlayerFixtureView()
            case .commentAction:
                UITestCommentActionFixtureView(api: dependencies.api)
            }
        }
        .environmentObject(dependencies)
        .environmentObject(dependencies.libraryStore)
        .environmentObject(dependencies.sessionStore)
    }
}

private struct UITestCommentActionFixtureView: View {
    let api: BiliAPIClient
    @State private var composerTarget: DynamicCommentComposerTarget?
    @State private var draft = RichCommentDraft()

    var body: some View {
        Button("打开评论操作") {
            // Fixture tap stays inert while the long-press action is enabled.
        }
        .accessibilityIdentifier("ui.commentAction.open")
        .commentActionsMenu(
            longPressEnabled: true,
            text: "用于验证评论回复的内容",
            copyTitle: "复制评论",
            replyAction: { composerTarget = .dynamic }
        )
        .background {
            RichCommentComposerPresenter(
                target: $composerTarget,
                draft: { _ in $draft },
                api: api,
                submit: { _, _, _ in }
            )
            .allowsHitTesting(false)
        }
    }
}

private struct UITestDynamicDetailFixtureView: View {
    let api: BiliAPIClient
    @State private var homeNavigationPath = NavigationPath()
    @State private var dynamicNavigationPath = NavigationPath()
    @State private var liveNavigationPath = NavigationPath()
    @State private var searchNavigationPath = NavigationPath()
    @State private var mineNavigationPath = NavigationPath()
    @State private var selectedTab: UITestRootTab = .dynamic
    @State private var searchQuery = ""
    @State private var isSearchFocused = false

    var body: some View {
        ZStack {
            Group {
                if UITestFixtureScenario.usesRootTabShell {
                    rootTabShell
                } else {
                    standaloneNavigationShell
                }
            }

        }
        .task {
            guard UITestFixtureScenario.autoOpensDynamicDetail,
                  activeNavigationPath.wrappedValue.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled,
                  activeNavigationPath.wrappedValue.isEmpty else { return }
            activeNavigationPath.wrappedValue.append(DynamicDetailTarget.loaded(Self.imageItem))
        }
    }

    private var rootTabShell: some View {
        TabView(selection: $selectedTab) {
            ForEach(
                [
                    UITestRootTab.home,
                    .dynamic,
                    .live,
                    .search,
                    .mine,
                ],
                id: \.self
            ) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    rootTabNavigationStack(
                        for: tab,
                        detailPath: navigationPathBinding(for: tab)
                    )
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
    }

    @ViewBuilder
    private func rootTabNavigationStack(
        for tab: UITestRootTab,
        detailPath: Binding<NavigationPath>
    ) -> some View {
        NavigationStack(path: detailPath) {
            rootTabContent(for: tab)
                .nativeNavigationSearch(
                    text: $searchQuery,
                    isPresented: $isSearchFocused,
                    isEnabled: tab == .search
                        && selectedTab == .search
                        && detailPath.wrappedValue.isEmpty,
                    prompt: "搜索",
                    title: "搜索"
                ) {}
                .toolbar {
                    if tab == .home {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("推荐/热门") {}
                                .accessibilityIdentifier("fixture.home.mode")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("账号消息", systemImage: "bell.fill") {}
                                .accessibilityIdentifier("fixture.home.messages")
                        }
                    }
                }
                .navigationTitle(tab.title)
                .toolbarTitleDisplayMode(.inline)
                .dynamicDetailDestinations(
                    path: detailPath,
                    api: api,
                    preloadedOriginalDetails: [Self.originalDetailItem.idStr: Self.originalDetailItem]
                )
                .navigationDestination(for: VideoOwner.self) { owner in
                    UploaderView(owner: owner)
                        .accessibilityIdentifier("fixture.uploader.root")
                }
        }
        .coordinatesRootTabBarTransitions(
            isDetailPresented: !detailPath.wrappedValue.isEmpty
        )
    }

    @ViewBuilder
    private func rootTabContent(for tab: UITestRootTab) -> some View {
        switch tab {
        case .home, .live, .mine:
            Color.clear
        case .dynamic:
            dynamicFeed
        case .search:
            searchRootContent
        }
    }

    private var searchRootContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Button("打开搜索结果详情") {
                    isSearchFocused = false
                    DispatchQueue.main.async {
                        activeNavigationPath.wrappedValue.append(
                            DynamicDetailTarget.loaded(Self.imageItem)
                        )
                    }
                }
                .accessibilityIdentifier("fixture.search.openDetail")

                Text(searchQuery)
                    .accessibilityIdentifier("fixture.search.queryValue")
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var standaloneNavigationShell: some View {
        NavigationStack(path: $dynamicNavigationPath) {
            dynamicFeed
                .dynamicDetailDestinations(
                    path: $dynamicNavigationPath,
                    api: api,
                    preloadedOriginalDetails: [Self.originalDetailItem.idStr: Self.originalDetailItem]
                )
        }
    }

    private var dynamicFeed: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button("打开 UP 个人页") {
                    activeNavigationPath.wrappedValue.append(Self.uploaderOwner)
                }
                .accessibilityIdentifier("fixture.dynamic.openUploader")
                .padding(.vertical, 16)

                Divider()

                ForEach(Self.items) { item in
                    DynamicFeedCard(item: item, api: api)
                        .padding(.vertical, 16)

                    Divider()
                }
            }
        }
        .accessibilityIdentifier("dynamic.feed.scroll")
        .nativeTopScrollEdgeEffect()
    }

    private static let items = [imageItem, pureTextItem, forwardItem]
    private static let uploaderOwner = VideoOwner(mid: 1001, name: "动态测试用户", face: nil)

    private var activeNavigationPath: Binding<NavigationPath> {
        navigationPathBinding(for: selectedTab)
    }

    private func navigationPathBinding(for tab: UITestRootTab) -> Binding<NavigationPath> {
        switch tab {
        case .home:
            return $homeNavigationPath
        case .dynamic:
            return $dynamicNavigationPath
        case .live:
            return $liveNavigationPath
        case .search:
            return $searchNavigationPath
        case .mine:
            return $mineNavigationPath
        }
    }

    private static let imageItem: DynamicFeedItem = {
        let data = Data(
            #"""
            {
              "id_str": "123456789",
              "type": "DYNAMIC_TYPE_DRAW",
              "basic": {
                "comment_id_str": "123456789",
                "comment_type": 17
              },
              "modules": {
                "module_author": {
                  "mid": 1001,
                  "name": "动态测试用户",
                  "face": "https://example.com/avatar.jpg",
                  "pub_time": "刚刚"
                },
                "module_dynamic": {
                  "desc": {
                    "text": "图文动态测试内容"
                  },
                  "major": {
                    "draw": {
                      "items": [
                        {
                          "src": "https://example.com/dynamic-image.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-2.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-3.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-4.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-5.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-6.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-7.jpg",
                          "width": 1200,
                          "height": 800
                        },
                        {
                          "src": "https://example.com/dynamic-image-8.jpg",
                          "width": 1200,
                          "height": 800
                        }
                      ]
                    }
                  }
                },
                "module_stat": {
                  "comment": { "count": 2 },
                  "forward": { "count": 1 },
                  "like": { "count": 3, "status": false }
                }
              }
            }
            """#.utf8
        )
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: data)
    }()

    private static let pureTextItem: DynamicFeedItem = {
        let data = Data(
            #"""
            {
              "id_str": "223456789",
              "type": "DYNAMIC_TYPE_WORD",
              "basic": {
                "comment_id_str": "223456789",
                "comment_type": 17
              },
              "modules": {
                "module_author": {
                  "mid": 1002,
                  "name": "纯文本测试用户",
                  "face": "https://example.com/avatar-2.jpg",
                  "pub_time": "1分钟前"
                },
                "module_dynamic": {
                  "desc": {
                    "text": "纯文本动态测试内容"
                  }
                },
                "module_stat": {
                  "comment": { "count": 4 },
                  "forward": { "count": 0 },
                  "like": { "count": 5, "status": false }
                }
              }
            }
            """#.utf8
        )
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: data)
    }()

    private static let forwardItem: DynamicFeedItem = {
        let data = Data(
            #"""
            {
              "id_str": "323456789",
              "type": "DYNAMIC_TYPE_FORWARD",
              "basic": {
                "comment_id_str": "323456789",
                "comment_type": 17
              },
              "modules": {
                "module_author": {
                  "mid": 1003,
                  "name": "转发测试用户",
                  "face": "https://example.com/avatar-3.jpg",
                  "pub_time": "2分钟前"
                },
                "module_dynamic": {
                  "desc": {
                    "text": "转发动态测试内容"
                  }
                },
                "module_stat": {
                  "comment": { "count": 6 },
                  "forward": { "count": 7 },
                  "like": { "count": 8, "status": false }
                }
              },
              "orig": {
                "id_str": "423456789",
                "type": "DYNAMIC_TYPE_WORD",
                "visible": true,
                "modules": {
                  "module_author": {
                    "mid": 1004,
                    "name": "原动态测试用户",
                    "face": "https://example.com/avatar-4.jpg"
                  },
                  "module_dynamic": {
                    "desc": {
                      "text": "被转发的原动态内容"
                    }
                  }
                }
              }
            }
            """#.utf8
        )
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: data)
    }()

    private static let originalDetailItem: DynamicFeedItem = {
        let data = Data(
            #"""
            {
              "id_str": "423456789",
              "type": "DYNAMIC_TYPE_WORD",
              "basic": {
                "comment_id_str": "423456789",
                "comment_type": 17
              },
              "modules": {
                "module_author": {
                  "mid": 1004,
                  "name": "原动态测试用户",
                  "face": "https://example.com/avatar-4.jpg",
                  "pub_time": "3分钟前"
                },
                "module_dynamic": {
                  "desc": {
                    "text": "被转发的原动态内容"
                  }
                },
                "module_stat": {
                  "comment": { "count": 9 },
                  "forward": { "count": 10 },
                  "like": { "count": 11, "status": false }
                }
              }
            }
            """#.utf8
        )
        return try! JSONDecoder.bili.decode(DynamicFeedItem.self, from: data)
    }()
}

private enum UITestRootTab: Hashable {
    case home
    case dynamic
    case live
    case search
    case mine

    var title: String {
        switch self {
        case .home: "首页"
        case .dynamic: "动态"
        case .live: "直播"
        case .search: "搜索"
        case .mine: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .dynamic: "bolt.horizontal"
        case .live: "play.tv"
        case .search: "magnifyingglass"
        case .mine: "person"
        }
    }
}

private struct UITestDanmakuFixtureView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var isShowingSettings = false
    @State private var fixturePlaybackTime: TimeInterval = 0
    @StateObject private var store = VideoDetailDanmakuSettingsRenderStore()

    private let fixtureSettings = DanmakuSettings(
        loadFactor: 1.0,
        hidesInPortrait: false,
        danmakuKit: DanmakuKitRenderSettings(
            displayArea: .full,
            fontScale: 1.0,
            fontWeight: .semibold,
            opacity: 0.95
        )
    )

    private var fixtureItems: [DanmakuItem] {
        [
            DanmakuItem(
                id: "fixture-scroll-1",
                time: 0,
                mode: 1,
                fontSize: 25,
                color: 0xFFFFFF,
                text: "你好 DanmakuKit 🚀"
            ),
            DanmakuItem(
                id: "fixture-top-1",
                time: 0.45,
                mode: 5,
                fontSize: 23,
                color: 0x55D6FF,
                text: "顶部固定 · SDF 字体"
            ),
            DanmakuItem(
                id: "fixture-bottom-1",
                time: 0.9,
                mode: 4,
                fontSize: 23,
                color: 0xFFE36E,
                text: "底部固定 · GPU canvas"
            ),
            DanmakuItem(
                id: "fixture-scroll-2",
                time: 1.35,
                mode: 1,
                fontSize: 25,
                color: 0xFF8BD1,
                text: "横竖屏切换保持时间连续"
            ),
            DanmakuItem(
                id: "fixture-scroll-3",
                time: 2.2,
                mode: 2,
                fontSize: 24,
                color: 0xB7FF8A,
                text: "emoji 🐶 中文 English"
            ),
        ]
    }

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: .constant(false),
            background: .black,
            statusBarStyle: .lightContent
        ) {
            ZStack {
                VStack(spacing: 20) {
                    Text("UI Test Video Detail")
                        .accessibilityIdentifier("ui.videoDetail.ready")
                    Text(libraryStore.danmakuSettings.danmakuKit.displayArea.title)
                        .accessibilityIdentifier("ui.videoDetail.danmakuSettings.persistedValue")
                    Button("Open Danmaku Settings") {
                        isShowingSettings = true
                    }
                    .accessibilityIdentifier("ui.videoDetail.danmakuSettings")
                }
                .foregroundStyle(.white)

                DanmakuOverlayView(
                    items: fixtureItems,
                    itemsRevision: fixtureItems.count,
                    currentTime: fixturePlaybackTime,
                    isPlaying: true,
                    playbackRate: 1,
                    isEnabled: true,
                    hasPresentedPlayback: true,
                    settings: fixtureSettings,
                    topInset: 48,
                    bottomInset: 72,
                    isLayoutTransitioning: false,
                    playbackClock: nil,
                    onPlaybackTime: nil
                )
                .accessibilityIdentifier("ui.videoDetail.danmakuOverlay")
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if UITestFixtureScenario.resetsPersistedState {
                libraryStore.setDanmakuEnabled(true)
                libraryStore.setDanmakuSettings(.default)
            }
            synchronizeRenderStore()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                fixturePlaybackTime += 0.05
                if fixturePlaybackTime >= 12 {
                    fixturePlaybackTime = 0
                }
            }
        }
        .onAppear {
            // The network-free fixture is also the renderer's rotation
            // regression surface. Production routes keep their own
            // orientation policy; this opt-in fixture allows XCTest to drive
            // both viewport sizes without opening a real player.
            AppOrientationLock.update(to: .allButUpsideDown, in: nil)
        }
        .onDisappear {
            AppOrientationLock.restorePortrait()
        }
        .sheet(isPresented: $isShowingSettings) {
            DanmakuSettingsSheet(
                store: store,
                toggleDanmaku: toggleDanmaku,
                updateDanmakuSettings: updateDanmakuSettings
            )
            .presentationDetents([.medium])
        }
    }

    private func toggleDanmaku() {
        libraryStore.setDanmakuEnabled(!store.isDanmakuEnabled)
        synchronizeRenderStore()
    }

    private func updateDanmakuSettings(_ settings: DanmakuSettings) {
        libraryStore.setDanmakuSettings(settings)
        synchronizeRenderStore()
    }

    private func synchronizeRenderStore() {
        var snapshot = VideoDetailDanmakuSettingsRenderSnapshot()
        snapshot.isDanmakuEnabled = libraryStore.danmakuEnabled
        snapshot.danmakuSettings = libraryStore.danmakuSettings
        store.update(snapshot)
    }
}

private struct UITestPlayerFixtureView: View {
    @StateObject private var fixture = UITestPlayerFixtureController()
    @State private var isFullscreen = false
    @State private var hidesSystemChrome = false
    @State private var isShowingPlayer = true

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: $hidesSystemChrome,
            background: .black,
            statusBarStyle: .lightContent
        ) {
            if isShowingPlayer {
                VStack(spacing: 16) {
                    ZStack {
                        BiliPlayerView(
                            viewModel: fixture.player,
                            presentation: isFullscreen ? .fullScreen : .embedded,
                            showsNavigationChrome: false,
                            showsStartupLoadingIndicator: false,
                            pausesOnDisappear: true,
                            isSecondaryControlsPresented: true,
                            embeddedAspectRatio: 16 / 9,
                            ignoresContainerSafeArea: isFullscreen,
                            keepsPlayerSurfaceStable: true,
                            fullscreenMode: isFullscreen ? .landscape(.landscapeRight) : nil,
                            showsRotationTransitionSnapshot: false,
                            onRequestFullscreen: {
                                isFullscreen = true
                                hidesSystemChrome = true
                            },
                            onExitFullscreen: {
                                isFullscreen = false
                                hidesSystemChrome = false
                            }
                        )
                    }

                    Text(isFullscreen ? "Fullscreen Player" : "Player Ready")
                        .font(.caption2)
                        .accessibilityIdentifier(
                            isFullscreen ? "ui.player.fullscreenSurface" : "ui.player.ready"
                        )

                    if !isFullscreen {
                        Text(fixture.player.isTerminated ? "terminated" : "active")
                            .accessibilityIdentifier("ui.player.lifecycleState")
                        HStack {
                            Button("Simulate Failure") {
                                fixture.simulateFailure()
                            }
                            .accessibilityIdentifier("ui.player.simulateFailure")

                            Button("Retry") {
                                fixture.retry()
                            }
                            .accessibilityIdentifier("ui.player.retry")

                            Button("Close Player") {
                                isShowingPlayer = false
                            }
                            .accessibilityIdentifier("ui.player.close")
                        }
                    }
                }
                .foregroundStyle(.white)
            } else {
                VStack(spacing: 12) {
                    Text("Player Closed")
                        .accessibilityIdentifier("ui.player.navigationReturned")
                    Text(fixture.didSuspendForNavigation ? "suspended" : "pending")
                        .accessibilityIdentifier("ui.player.navigationState")
                }
                .foregroundStyle(.white)
            }
        }
    }
}
