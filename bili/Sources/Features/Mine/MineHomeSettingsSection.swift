import SwiftUI

struct MineHomeSettingsSection: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("首页") {
            Picker(selection: Binding(
                get: { libraryStore.homeFeedLayout },
                set: { libraryStore.setHomeFeedLayout($0) }
            )) {
                ForEach(HomeFeedLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            } label: {
                Label("首页布局", systemImage: "rectangle.grid.1x2")
            }

            Picker(selection: Binding(
                get: { libraryStore.homeRecommendFeedSourcePreference },
                set: { libraryStore.setHomeRecommendFeedSourcePreference($0) }
            )) {
                ForEach(HomeRecommendFeedSourcePreference.allCases) { source in
                    Text(source.title).tag(source)
                }
            } label: {
                Label("首页推荐内容来源", systemImage: "sparkles.tv")
            }
            .pickerStyle(.navigationLink)

            Text(recommendSourceHint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            MineHomeRefreshDistanceControl(libraryStore: libraryStore)
        }
    }

    private var recommendSourceHint: String {
        switch libraryStore.homeRecommendFeedSourcePreference {
        case .web:
            return "网页端更稳定；App 端更接近 B 站 App 的推荐。"
        case .app:
            if libraryStore.guestModeEnabled {
                return "当前是 App 端游客推荐：隐私里的游客推荐模式已开启，不会使用你的账号画像。"
            }
            if sessionStore.appAccessKey() != nil {
                return "当前是 App 端账号推荐：已带移动端凭证，更接近官方客户端推荐。"
            }
            switch sessionStore.loginCredentialKind {
            case .web:
                return "当前是网页登录：App 端推荐缺少 access_key，建议改用 App 短信验证码登录。"
            case .appQRCodeTV:
                return "当前是扫码登录：如 App 推荐不准，建议改用 App 短信验证码登录。"
            case .appSMS:
                return "当前是短信登录，但缺少 access_key；可重新登录后再刷新首页。"
            case .unknown:
                return "当前 App 端推荐缺少 access_key，可能不是完整账号推荐。"
            }
        }
    }
}

private struct MineHomeRefreshDistanceControl: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下拉刷新距离", systemImage: "arrow.down.circle")
                Spacer()
                Text("\(Int(libraryStore.homeRefreshTriggerDistance)) pt")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { libraryStore.homeRefreshTriggerDistance },
                    set: { libraryStore.setHomeRefreshTriggerDistance($0) }
                ),
                in: LibraryStore.homeRefreshDistanceRange,
                step: 5
            ) {
                Text("首页下拉刷新距离")
            } minimumValueLabel: {
                Text("近")
            } maximumValueLabel: {
                Text("远")
            }

            HStack {
                Text("下拉达到设定距离后会刷新推荐内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("默认") {
                    libraryStore.setHomeRefreshTriggerDistance(
                        LibraryStore.defaultHomeRefreshTriggerDistance
                    )
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
