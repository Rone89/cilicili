import SwiftUI

enum MineOverlayRoute: Hashable {
    case accountMessages
    case accountManagement
    case history
    case favorites
    case watchLater
    case interfaceSettings
    case homeAndSearchSettings
    case playbackSettings
    case cacheSettings
    case developerDiagnostics
    case contentFilterSettings
    case privacySettings

    var navigationDisplayTitle: String {
        switch self {
        case .accountMessages: "通知"
        case .accountManagement: "账号管理"
        case .history: AccountLibraryKind.history.title
        case .favorites: AccountLibraryKind.favorites.title
        case .watchLater: AccountLibraryKind.watchLater.title
        case .interfaceSettings: "界面设置"
        case .homeAndSearchSettings: "首页与搜索"
        case .playbackSettings: "播放设置"
        case .cacheSettings: "缓存管理"
        case .developerDiagnostics: "开发者诊断"
        case .contentFilterSettings: "内容过滤"
        case .privacySettings: "隐私设置"
        }
    }

    var isSettingsRoute: Bool {
        switch self {
        case .interfaceSettings, .homeAndSearchSettings, .playbackSettings, .contentFilterSettings,
             .privacySettings, .cacheSettings, .developerDiagnostics, .accountManagement:
            true
        case .accountMessages, .history, .favorites, .watchLater:
            false
        }
    }
}

struct MineOverlayNavigationButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(_ action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label()
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }
}
