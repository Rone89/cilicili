import SwiftUI

/// A network-free host for production UI components used by XCUITest.
struct UITestFixtureRootView: View {
    let scenario: UITestFixtureScenario

    var body: some View {
        switch scenario {
        case .danmaku:
            UITestDanmakuFixtureView()
        case .fullscreen:
            UITestFullscreenFixtureView()
        }
    }
}

private struct UITestDanmakuFixtureView: View {
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
                Button("Open Danmaku Settings") {
                    isShowingSettings = true
                }
                .accessibilityIdentifier("ui.videoDetail.danmakuSettings")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        var snapshot = VideoDetailDanmakuSettingsRenderSnapshot()
        snapshot.isDanmakuEnabled = !store.isDanmakuEnabled
        snapshot.danmakuSettings = store.danmakuSettings
        store.update(snapshot)
    }

    private func updateDanmakuSettings(_ settings: DanmakuSettings) {
        var snapshot = VideoDetailDanmakuSettingsRenderSnapshot()
        snapshot.isDanmakuEnabled = store.isDanmakuEnabled
        snapshot.danmakuSettings = settings
        store.update(snapshot)
    }
}

private struct UITestFullscreenFixtureView: View {
    @State private var isFullscreen = false

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: $isFullscreen,
            background: .black,
            statusBarStyle: .lightContent
        ) {
            ZStack {
                Color.black
                VStack(spacing: 20) {
                    Text(isFullscreen ? "Fullscreen Active" : "Live Fixture Ready")
                        .accessibilityIdentifier(
                            isFullscreen ? "ui.live.fullscreenSurface" : "ui.live.ready"
                        )
                    if isFullscreen {
                        Button("Exit Fullscreen") {
                            isFullscreen = false
                        }
                        .accessibilityIdentifier("ui.live.player.exitFullscreen")
                    } else {
                        Button("Enter Fullscreen") {
                            isFullscreen = true
                        }
                        .accessibilityIdentifier("ui.live.player.fullscreen")
                    }
                }
                .foregroundStyle(.white)
            }
        }
    }
}
