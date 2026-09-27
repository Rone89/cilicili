import Foundation

enum MineSearchSection: CaseIterable, Identifiable {
    case account
    case settings
    case diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .account:
            return "账号"
        case .settings:
            return "设置"
        case .diagnostics:
            return "诊断与实验"
        }
    }
}

struct MineSearchItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let section: MineSearchSection
    let route: MineOverlayRoute
    let keywords: [String]

    var searchableText: String {
        ([title, subtitle] + keywords).joined(separator: " ")
    }
}

enum MineSearchCatalog {
    static let items: [MineSearchItem] = [
        MineSearchItem(
            id: "account-management",
            title: "账号管理",
            subtitle: "切换账号、添加账号和分配账号用途",
            systemImage: "person.2",
            section: .account,
            route: .accountManagement,
            keywords: ["多账号", "主账号", "切换账号", "添加账号", "账号用途", "视频取流", "动态取流", "互动账号"]
        ),
        MineSearchItem(
            id: "account-messages",
            title: "账号消息",
            subtitle: "查看回复、点赞和系统通知",
            systemImage: "bell.badge",
            section: .account,
            route: .accountMessages,
            keywords: ["通知", "消息", "私信"]
        ),
        MineSearchItem(
            id: "history",
            title: "观看记录",
            subtitle: "查看已观看的视频",
            systemImage: "clock.arrow.circlepath",
            section: .account,
            route: .history,
            keywords: ["历史", "播放记录"]
        ),
        MineSearchItem(
            id: "favorites",
            title: "账号收藏",
            subtitle: "查看收藏夹和已收藏内容",
            systemImage: "star",
            section: .account,
            route: .favorites,
            keywords: ["收藏夹", "收藏"]
        ),
        MineSearchItem(
            id: "watch-later",
            title: "稍后再看",
            subtitle: "查看暂存的视频",
            systemImage: "clock.badge.checkmark",
            section: .account,
            route: .watchLater,
            keywords: ["稍后", "待看"]
        ),
        MineSearchItem(
            id: "interface-settings",
            title: "界面显示",
            subtitle: "外观、字号、主题色和页面显示",
            systemImage: "paintpalette",
            section: .settings,
            route: .interfaceSettings,
            keywords: [
                "外观", "深色模式", "浅色模式", "应用图标", "主色调", "主题色", "使用系统字号",
                "固定 App 字号", "固定字号", "图片质量", "显示视频封面时长", "封面时长",
                "滚动时最小化 TabBar", "底部栏 Liquid Glass 材质", "液态玻璃",
                "操作按钮样式", "详情页操作按钮样式", "普通按钮", "强制 120Hz 滚动", "高刷新率"
            ]
        ),
        MineSearchItem(
            id: "home-search-settings",
            title: "首页与搜索",
            subtitle: "首页布局、推荐来源和搜索选项",
            systemImage: "house",
            section: .settings,
            route: .homeAndSearchSettings,
            keywords: [
                "首页布局", "首页推荐内容来源", "推荐来源", "原生下拉刷新", "下拉刷新距离",
                "显示热门搜索", "热门搜索", "热搜", "搜索"
            ]
        ),
        MineSearchItem(
            id: "playback-settings",
            title: "播放偏好",
            subtitle: "视频画质、解码、自动播放和播放工具",
            systemImage: "play.rectangle",
            section: .settings,
            route: .playbackSettings,
            keywords: [
                "智能播放加速", "进入详情自动播放", "画中画播放", "观看记录同步门槛", "默认画质",
                "蜂窝网络画质", "视频编码", "硬解优先", "杜比视界渲染", "默认倍速", "空降助手",
                "视频窗口底部进度条", "听视频列表排序", "播放", "画质", "解码", "自动播放", "画中画", "弹幕"
            ]
        ),
        MineSearchItem(
            id: "cache-settings",
            title: "缓存空间与清理",
            subtitle: "查看缓存占用并清理可重新获取的内容",
            systemImage: "internaldrive",
            section: .settings,
            route: .cacheSettings,
            keywords: ["缓存", "清理", "磁盘", "空间"]
        ),
        MineSearchItem(
            id: "content-filter-settings",
            title: "内容过滤",
            subtitle: "过滤动态、推荐视频和评论内容",
            systemImage: "line.3.horizontal.decrease.circle",
            section: .settings,
            route: .contentFilterSettings,
            keywords: [
                "屏蔽广告动态", "屏蔽带货动态", "屏蔽带货评论", "自定义动态关键词", "推荐过滤",
                "最短时长", "最低播放量", "最低点赞率", "标题关键词", "应用到相关推荐", "过滤", "屏蔽", "关键词", "广告"
            ]
        ),
        MineSearchItem(
            id: "privacy-settings",
            title: "隐私",
            subtitle: "无痕模式和游客推荐模式",
            systemImage: "hand.raised",
            section: .settings,
            route: .privacySettings,
            keywords: ["无痕模式", "游客推荐模式", "隐私", "无痕", "游客"]
        ),
        MineSearchItem(
            id: "developer-diagnostics",
            title: "开发者与诊断",
            subtitle: "诊断、实验和高级播放工具",
            systemImage: "wrench.and.screwdriver",
            section: .diagnostics,
            route: .developerDiagnostics,
            keywords: [
                "图片加载诊断", "播放性能诊断", "网络诊断", "页面导航耗时",
                "资源加载诊断", "首页推荐诊断", "点击区域", "性能日志", "资源命中统计", "缓存上限", "实验开关"
            ]
        )
    ]

    static func search(_ query: String) -> [MineSearchItem] {
        let compactQuery = compact(query)
        guard !compactQuery.isEmpty else { return [] }
        let queryTerms = terms(in: query)

        return items.filter { item in
            let searchableText = compact(item.searchableText)
            return searchableText.contains(compactQuery)
                || queryTerms.allSatisfy(searchableText.contains)
        }
    }

    private static func compact(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: searchSeparators)
            .joined()
    }

    private static func terms(in query: String) -> [String] {
        query
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: searchSeparators)
            .map(compact)
            .filter { !$0.isEmpty }
    }

    private static let searchSeparators = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
}
