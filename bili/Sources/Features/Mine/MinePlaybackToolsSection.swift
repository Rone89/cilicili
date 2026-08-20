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
                get: { libraryStore.diagnosticsBackgroundProcessingExperimentEnabled },
                set: { libraryStore.setDiagnosticsBackgroundProcessingExperimentEnabled($0) }
            )) {
                Label("播放诊断后台化实验", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
            }

            NavigationLink {
                ResourceLoadingExperimentSettingsView(libraryStore: libraryStore)
            } label: {
                SettingsNavigationRow(
                    title: "资源加载调度",
                    subtitle: "已启用，可分别调整 5 项加载策略",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }

            Toggle(isOn: Binding(
                get: { libraryStore.playerPerformanceOverlayEnabled },
                set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
            )) {
                Label("播放性能诊断", systemImage: "waveform.path.ecg.rectangle")
            }

            NavigationLink {
                PlayerPerformanceLogView()
            } label: {
                SettingsNavigationRow(
                    title: "启动链路性能日志",
                    subtitle: "首帧、准备和缓冲",
                    systemImage: "speedometer"
                )
            }

            ForEach(Array(PlaybackPerformanceTestVideo.fixedSamples.enumerated()), id: \.element.id) { index, video in
                NavigationLink {
                    PlaybackPerformanceTestVideoView(testVideo: video)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("测试视频 \(index + 1)", systemImage: "play.rectangle")
                        Text(video.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { libraryStore.videoRotationFrameReportOverlayEnabled },
                set: { libraryStore.setVideoRotationFrameReportOverlayEnabled($0) }
            )) {
                Label("旋转帧报告", systemImage: "rotate.right")
            }

            Toggle(isOn: Binding(
                get: { libraryStore.videoRotationOptimizationExperimentEnabled },
                set: { libraryStore.setVideoRotationOptimizationExperimentEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("视频旋转优化实验", systemImage: "rectangle.landscape.rotate")
                    Text("关闭后立即恢复 1.0.21 的稳定旋转方案")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { libraryStore.playerControlEdgeScrimEnabled },
                set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
            )) {
                Label("播放控件边缘遮罩", systemImage: "rectangle.dashed")
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

            Picker(selection: Binding(
                get: { libraryStore.videoListenPlaylistSortOrder },
                set: { libraryStore.setVideoListenPlaylistSortOrder($0) }
            )) {
                ForEach(VideoListenPlaylistSortOrder.allCases) { order in
                    Label(order.title, systemImage: order.systemImage)
                        .tag(order)
                }
            } label: {
                Label("听视频列表排序", systemImage: libraryStore.videoListenPlaylistSortOrder.systemImage)
            }
            .pickerStyle(.navigationLink)

            NavigationLink {
                ResourceCacheManagementView()
            } label: {
                SettingsNavigationRow(
                    title: "资源缓存",
                    subtitle: "图片、接口、视频分片缓存",
                    systemImage: "internaldrive"
                )
            }
        }
    }
}
