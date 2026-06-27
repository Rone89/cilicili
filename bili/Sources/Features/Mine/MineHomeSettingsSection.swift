import SwiftUI

struct MineHomeSettingsSection: View {
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
            return "当前是 App 端账号推荐：会带登录状态请求移动端推荐，更接近你的账号推荐。"
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
