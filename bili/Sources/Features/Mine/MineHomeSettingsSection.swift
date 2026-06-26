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

            MineHomeRefreshDistanceControl(libraryStore: libraryStore)
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
