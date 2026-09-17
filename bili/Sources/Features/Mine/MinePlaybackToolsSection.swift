import SwiftUI

struct MinePlaybackToolsSection: View {
    let mode: MinePlaybackSettingsView.Mode
    @ObservedObject var libraryStore: LibraryStore
    @State private var av1HardwareDecodeProbe = PlaybackCodecPolicy.av1HardwareDecodeProbe
    @State private var isShowingAV1HardwareDecodeResult = false

    var body: some View {
        if mode == .user {
            userSection
        } else {
            developerSection
        }
    }

    private var userSection: some View {
        Section("播放工具") {
            Toggle(
                isOn: Binding(
                    get: { libraryStore.sponsorBlockEnabled },
                    set: { libraryStore.setSponsorBlockEnabled($0) }
                )
            ) {
                MineSettingsLabel("空降助手", systemImage: "forward.end")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.showsVideoDetailPinnedProgressBar },
                    set: { libraryStore.setShowsVideoDetailPinnedProgressBar($0) }
                )
            ) {
                MineSettingsLabel("视频窗口底部进度条", systemImage: "line.3.horizontal.decrease")
            }

            Picker(
                selection: Binding(
                    get: { libraryStore.videoListenPlaylistSortOrder },
                    set: { libraryStore.setVideoListenPlaylistSortOrder($0) }
                )
            ) {
                ForEach(VideoListenPlaylistSortOrder.allCases) { order in
                    MineSettingsLabel(order.title, systemImage: order.systemImage)
                        .tag(order)
                }
            } label: {
                MineSettingsLabel("听视频列表排序", systemImage: libraryStore.videoListenPlaylistSortOrder.systemImage)
            }
            .pickerStyle(.menu)
        }
    }

    private var developerSection: some View {
        Section("播放与网络诊断") {
            Toggle(
                isOn: Binding(
                    get: { libraryStore.playerPerformanceOverlayEnabled },
                    set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                )
            ) {
                MineSettingsLabel("播放性能诊断", systemImage: "waveform.path.ecg.rectangle")
            }

            Button {
                av1HardwareDecodeProbe = PlaybackCodecPolicy.av1HardwareDecodeProbe
                isShowingAV1HardwareDecodeResult = true
            } label: {
                HStack(spacing: 8) {
                    MineSettingsLabel("检测 AV1 硬解", systemImage: "cpu")
                    Spacer(minLength: 8)
                    Text(av1HardwareDecodeProbe.settingsStatusTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .alert("AV1 硬解检测", isPresented: $isShowingAV1HardwareDecodeResult) {
                Button("好", role: .cancel) {}
            } message: {
                Text(av1HardwareDecodeProbe.detail)
            }

            NavigationLink {
                PlayerPerformanceLogView()
            } label: {
                PlainSettingsNavigationRow(
                    title: "启动链路性能日志",
                    subtitle: "首帧、准备和缓冲",
                )
            }

            ForEach(Array(PlaybackPerformanceTestVideo.fixedSamples.enumerated()), id: \.element.id) { index, video in
                NavigationLink {
                    PlaybackPerformanceTestVideoView(testVideo: video)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        MineSettingsLabel("测试视频 \(index + 1)", systemImage: "play.rectangle")
                        Text(video.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.videoRotationFrameReportOverlayEnabled },
                    set: { libraryStore.setVideoRotationFrameReportOverlayEnabled($0) }
                )
            ) {
                MineSettingsLabel("旋转帧报告", systemImage: "rotate.right")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled },
                    set: { isEnabled in
                        if isEnabled {
                            PlaybackDetailPerformanceMonitor.shared.clear()
                        }
                        libraryStore.setVideoDetailNavigationLatencyDiagnosticsEnabled(isEnabled)
                    }
                )
            ) {
                MineSettingsLabel("视频详情导航时延诊断", systemImage: "stopwatch")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.playerControlEdgeScrimEnabled },
                    set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                )
            ) {
                MineSettingsLabel("播放控件边缘遮罩", systemImage: "rectangle.dashed")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.showsVideoDetailNetworkDiagnosticsButton },
                    set: { libraryStore.setShowsVideoDetailNetworkDiagnosticsButton($0) }
                )
            ) {
                MineSettingsLabel("视频详情网络诊断", systemImage: "stethoscope")
            }

        }
    }
}
