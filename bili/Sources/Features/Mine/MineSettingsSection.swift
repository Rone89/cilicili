import SwiftUI

struct MineSettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore
    let onOpenRoute: (MineOverlayRoute) -> Void

    var body: some View {
        Section("设置") {
            MineOverlayNavigationButton {
                onOpenRoute(.interfaceSettings)
            } label: {
                SettingsNavigationRow(
                    title: "界面显示",
                    subtitle: interfaceSettingsSummary,
                    systemImage: "paintpalette"
                )
            }
            .accessibilityIdentifier("mine.settings.interface")

            MineOverlayNavigationButton {
                onOpenRoute(.homeAndSearchSettings)
            } label: {
                SettingsNavigationRow(
                    title: "首页与搜索",
                    subtitle: homeAndSearchSummary,
                    systemImage: "house"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.playbackSettings)
            } label: {
                SettingsNavigationRow(
                    title: "播放偏好",
                    subtitle: playbackSettingsSummary,
                    systemImage: "play.rectangle"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.cacheSettings)
            } label: {
                SettingsNavigationRow(
                    title: "缓存空间与清理",
                    subtitle: "查看占用空间并清理可重新获取的内容",
                    systemImage: "internaldrive"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.developerDiagnostics)
            } label: {
                SettingsNavigationRow(
                    title: "开发者与诊断",
                    subtitle: "诊断、实验和高级播放工具",
                    systemImage: "wrench.and.screwdriver"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.contentFilterSettings)
            } label: {
                SettingsNavigationRow(
                    title: "内容过滤",
                    subtitle: contentFilterSummary,
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }

            MineOverlayNavigationButton {
                onOpenRoute(.privacySettings)
            } label: {
                SettingsNavigationRow(
                    title: "隐私",
                    subtitle: privacySummary,
                    systemImage: "hand.raised"
                )
            }

        }

        Section("评论") {
            Toggle(isOn: $commentLongPressActionsEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    MineSettingsLabel("长按评论显示操作", systemImage: "hand.point.up.left")
                    Text("开启后，轻点评论不会打开输入框；长按可选择“复制评论”或“回复”。")
                        .appTypography(.settingsSubtitle, fallback: .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @AppStorage(CommentInteractionSettings.longPressActionsEnabledKey)
    private var commentLongPressActionsEnabled = false

    private var interfaceSettingsSummary: String {
        let tabs = libraryStore.visibleRootTabs
            .filter(\.participatesInRootTabVisibilitySettings)
            .map(\.title)
            .joined(separator: "、")
        var parts = [libraryStore.appearanceMode.title, tabs]
        if libraryStore.force120HzScrollingEnabled {
            parts.append("120Hz")
        }
        if libraryStore.minimizesTabBarOnScroll {
            parts.append("滚动最小化 TabBar")
        }
        if !libraryStore.followsSystemFontSize {
            parts.append("固定字号：\(libraryStore.manualFontSize.title)")
        }
        parts.append("底部栏：\(libraryStore.videoDetailSegmentedPickerGlassStyle.title)")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var homeAndSearchSummary: String {
        let hotSearch = libraryStore.showsHotSearches ? "热搜开启" : "热搜关闭"
        return "\(libraryStore.homeFeedLayout.title) · \(libraryStore.homeRecommendFeedSourcePreference.title) · \(hotSearch)"
    }

    private var privacySummary: String {
        var enabled = [String]()
        if libraryStore.incognitoModeEnabled {
            enabled.append("无痕")
        }
        if libraryStore.guestModeEnabled {
            enabled.append("游客")
        }
        return enabled.isEmpty ? "默认" : enabled.joined(separator: "、")
    }

    private var contentFilterSummary: String {
        var parts = ["动态 \(libraryStore.blockedDynamicKeywords.count) 个关键词"]
        if libraryStore.videoRecommendationFilterConfiguration.isActive {
            parts.append("推荐过滤开启")
        }
        return parts.joined(separator: "，")
    }

    private var playbackSettingsSummary: String {
        var parts = [
            libraryStore.playbackAutoOptimizationMode.title,
            libraryStore.videoDetailAutoplayEnabled ? "详情自动播放" : "详情手动播放",
            libraryStore.videoCodecPreference.title,
            libraryStore.dolbyVisionRenderingPolicy.title
        ]
        if libraryStore.forceHardwareDecodeEnabled {
            parts.append("硬解优先")
        }
        return parts.joined(separator: " · ")
    }
}
