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
            case .fullscreen:
                UITestPlayerFixtureView()
            }
        }
        .environmentObject(dependencies)
        .environmentObject(dependencies.libraryStore)
    }
}

private struct UITestDanmakuFixtureView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var isShowingSettings = false
    @StateObject private var store = VideoDetailDanmakuSettingsRenderStore()

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: .constant(false),
            background: .black,
            statusBarStyle: .lightContent
        ) {
            VStack(spacing: 20) {
                Text("UI Test Video Detail")
                    .accessibilityIdentifier("ui.videoDetail.ready")
                Text(libraryStore.danmakuSettings.displayArea.rawValue)
                    .accessibilityIdentifier("ui.videoDetail.danmakuSettings.persistedValue")
                Button("Open Danmaku Settings") {
                    isShowingSettings = true
                }
                .accessibilityIdentifier("ui.videoDetail.danmakuSettings")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if UITestFixtureScenario.resetsPersistedState {
                libraryStore.setDanmakuEnabled(true)
                libraryStore.setDanmakuSettings(.default)
            }
            synchronizeRenderStore()
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
