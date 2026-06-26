import SwiftUI

struct MinePlaybackToolsSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("播放工具") {
            Toggle(isOn: Binding(
                get: { libraryStore.sponsorBlockEnabled },
                set: { libraryStore.setSponsorBlockEnabled($0) }
            )) {
                Label("空降助手", systemImage: "forward.end")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.playerPerformanceOverlayEnabled },
                set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
            )) {
                Label("播放性能浮层", systemImage: "waveform.path.ecg.rectangle")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.showsVideoDetailNetworkDiagnosticsButton },
                set: { libraryStore.setShowsVideoDetailNetworkDiagnosticsButton($0) }
            )) {
                Label("视频详情网络诊断", systemImage: "stethoscope")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.showsVideoDetailPinnedProgressBar },
                set: { libraryStore.setShowsVideoDetailPinnedProgressBar($0) }
            )) {
                Label("视频窗口底部进度条", systemImage: "line.3.horizontal.decrease")
            }

            NavigationLink {
                PlayerPerformanceLogView()
            } label: {
                Label("播放性能日志", systemImage: "speedometer")
            }

            NavigationLink {
                ResourceCacheManagementView()
            } label: {
                Label("资源缓存", systemImage: "internaldrive")
            }
        }
    }
}
