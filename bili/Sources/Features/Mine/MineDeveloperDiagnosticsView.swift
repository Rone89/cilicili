import SwiftUI

struct MineDeveloperDiagnosticsView: View {
    @AppStorage(PlaybackRecoveryTestSettings.showsPlayerMenuEntryKey) private var showsRecoveryTestEntry = false
    @ObservedObject var libraryStore: LibraryStore
    let api: BiliAPIClient

    var body: some View {
        Form {
            diagnosticsSection
            experimentsSection
            cacheSection

            Section {
                Text("这些选项主要用于问题定位和新功能验证。普通使用时建议保持关闭，并让 App 使用自动策略。")
                    .appTypography(.settingsSubtitle, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .standardPageHorizontalContentMargins(libraryStore.standardPageHorizontalInset)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }

    private var diagnosticsSection: some View {
        Section("诊断") {
            Toggle(isOn: $showsRecoveryTestEntry) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("显示自动恢复测试入口", systemImage: "testtube.2")
                    Text("在视频的更多播放设置中显示自动恢复测试。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("mine.diagnostics.recoveryTestEntry")

            Toggle(
                isOn: Binding(
                    get: { libraryStore.remoteImageDiagnosticsEnabled },
                    set: { libraryStore.setRemoteImageDiagnosticsEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("记录图片加载诊断", systemImage: "chart.bar.xaxis")
                    Text("只记录缓存、滚动和 CDN 的汇总数字，不记录图片、链接、账号或 Cookie。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            NavigationLink {
                RemoteImageDiagnosticsView(libraryStore: libraryStore)
            } label: {
                PlainSettingsNavigationRow(
                    title: "图片加载诊断",
                    subtitle: "缓存命中、CDN 节点和最近加载事件"
                )
            }

            NavigationLink {
                MineHomeRecommendDiagnosticsView()
            } label: {
                PlainSettingsNavigationRow(
                    title: "首页推荐诊断",
                    subtitle: "推荐来源、请求状态和快照"
                )
            }

            NavigationLink {
                MinePlaybackSettingsView(libraryStore: libraryStore, api: api, mode: .developer)
            } label: {
                PlainSettingsNavigationRow(
                    title: "播放与网络诊断",
                    subtitle: "播放性能、网络线路、导航时延和性能日志"
                )
            }

            NavigationLink {
                ResourceLoadingDiagnosticsView(libraryStore: libraryStore)
            } label: {
                PlainSettingsNavigationRow(
                    title: "资源加载诊断",
                    subtitle: "资源命中、耗时和最近加载事件"
                )
            }
        }
    }

    private var experimentsSection: some View {
        Section("实验开关") {
            Toggle(isOn: Binding(
                get: { libraryStore.metalDanmakuRendererExperimentEnabled },
                set: { libraryStore.setMetalDanmakuRendererExperimentEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("Metal 弹幕渲染实验", systemImage: "sparkles.tv")
                    Text("用 GPU 批量绘制普通文字弹幕。关闭后使用 DanmakuKit；图片表情暂以文字显示。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("mine.experiments.metalDanmaku")

            Toggle(isOn: Binding(
                get: { libraryStore.aiSubtitleExperimentEnabled },
                set: { libraryStore.setAiSubtitleExperimentEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("AI 字幕实验", systemImage: "text.bubble")
                    Text("解析播放详情接口的字幕轨（含 AI 生成），在播放器底部渲染。开关在下次进入视频详情时生效。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("mine.experiments.aiSubtitle")

            Toggle(isOn: Binding(
                get: { libraryStore.videoDetailCompactPageSelectorExperimentEnabled },
                set: { libraryStore.setVideoDetailCompactPageSelectorExperimentEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("分P紧凑选择实验", systemImage: "rectangle.stack")
                    Text("视频详情页的分P改为单行显示当前分P名称和总数，点按以弹窗查看全部分P。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("mine.experiments.compactPageSelector")

            Toggle(
                isOn: Binding(
                    get: { libraryStore.dynamicCommentHitAreaVisualizationExperimentEnabled },
                    set: { libraryStore.setDynamicCommentHitAreaVisualizationExperimentEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("动态评论点击区域可视化", systemImage: "hand.tap")
                    Text("用半透明色块标示动态详情和评论弹窗中的回复与独立操作区域。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.resourceLoadingResumePacketWarmupEnabled },
                    set: { libraryStore.setResourceLoadingResumePacketWarmupEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("断点续播预热", systemImage: "goforward")
                    Text("从上次进度继续播放时，提前准备目标片段。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.playbackPlayableFallbackDeadlineExperimentEnabled },
                    set: { libraryStore.setPlaybackPlayableFallbackDeadlineExperimentEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("可播放降级限时实验", systemImage: "timer")
                    Text("已有可播放低档位后，完整取流最多再等待 650ms。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
    }

    private var cacheSection: some View {
        Section("缓存与资源") {
            NavigationLink {
                ResourceCacheManagementView(mode: .developer)
            } label: {
                PlainSettingsNavigationRow(
                    title: "资源缓存实现",
                    subtitle: "详细占用、缓存上限和分类清理"
                )
            }
        }
    }
}
