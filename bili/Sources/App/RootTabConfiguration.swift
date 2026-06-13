import Foundation

enum AppTab: String, CaseIterable, Codable, Identifiable, Hashable {
    case home
    case dynamic
    case live
    case mine
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .dynamic:
            return "动态"
        case .live:
            return "直播"
        case .mine:
            return "我的"
        case .search:
            return "搜索"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .dynamic:
            return "sparkles"
        case .live:
            return "play.tv"
        case .mine:
            return "person.crop.circle"
        case .search:
            return "magnifyingglass"
        }
    }

    var canHideFromRootTabBar: Bool {
        self != .home && self != .mine
    }

    static let defaultVisibleTabs: [AppTab] = [.home, .dynamic, .live, .mine, .search]

    static func normalizedVisibleTabs(_ tabs: [AppTab]) -> [AppTab] {
        var seen = Set<AppTab>()
        var normalized = [AppTab]()
        for tab in tabs where seen.insert(tab).inserted {
            normalized.append(tab)
        }
        if !normalized.contains(.home) {
            normalized.insert(.home, at: 0)
        }
        if !normalized.contains(.mine) {
            normalized.append(.mine)
        }
        return normalized
    }
}
