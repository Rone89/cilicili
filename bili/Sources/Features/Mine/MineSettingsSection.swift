import SwiftUI

struct MineSettingsSection: View {
    @ObservedObject var libraryStore: LibraryStore
    let onOpenRoute: (MineOverlayRoute) -> Void

    @ViewBuilder
    var body: some View {
        groupedSettings
    }

    @ViewBuilder
    private var groupedSettings: some View {
        Section("日常体验") {
            interfaceSettingsLink
            homeAndSearchSettingsLink
            playbackSettingsLink
        }

        Section("内容与隐私") {
            contentFilterSettingsLink
            privacySettingsLink
        }

        Section("存储与诊断") {
            cacheSettingsLink
            developerDiagnosticsLink
        }
    }

    private var interfaceSettingsLink: some View {
        settingsLink(
            route: .interfaceSettings,
            title: "界面显示",
            subtitle: interfaceSettingsSummary,
            systemImage: "paintpalette"
        )
        .accessibilityIdentifier("mine.settings.interface")
    }

    private var homeAndSearchSettingsLink: some View {
        settingsLink(
            route: .homeAndSearchSettings,
            title: "首页与搜索",
            subtitle: homeAndSearchSummary,
            systemImage: "house"
        )
    }

    private var playbackSettingsLink: some View {
        settingsLink(
            route: .playbackSettings,
            title: "播放偏好",
            subtitle: playbackSettingsSummary,
            systemImage: "play.rectangle"
        )
    }

    private var cacheSettingsLink: some View {
        settingsLink(
            route: .cacheSettings,
            title: "缓存空间与清理",
            subtitle: "查看占用空间并清理可重新获取的内容",
            systemImage: "internaldrive"
        )
    }

    private var developerDiagnosticsLink: some View {
        settingsLink(
            route: .developerDiagnostics,
            title: "开发者与诊断",
            subtitle: "诊断、实验和高级播放工具",
            systemImage: "wrench.and.screwdriver"
        )
    }

    private var contentFilterSettingsLink: some View {
        settingsLink(
            route: .contentFilterSettings,
            title: "内容过滤",
            subtitle: contentFilterSummary,
            systemImage: "line.3.horizontal.decrease.circle"
        )
    }

    private var privacySettingsLink: some View {
        settingsLink(
            route: .privacySettings,
            title: "隐私",
            subtitle: privacySummary,
            systemImage: "hand.raised"
        )
    }

    private func settingsLink(
        route: MineOverlayRoute,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        MineOverlayNavigationButton {
            onOpenRoute(route)
        } label: {
            SettingsNavigationRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage
            )
        }
    }

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
