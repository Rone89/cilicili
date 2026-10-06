#if DEBUG
import SwiftUI

/// Network-free acceptance checks using the actual resolved detail title and experiment flag.
struct UITestVideoSponsoredBadgeFixtureView: View {
    @ObservedObject var libraryStore: LibraryStore
    @StateObject private var store = VideoDetailDescriptionRenderStore()
    @State private var isSponsored = false
    @State private var hasAttribute = true
    @State private var usesLongTitle = false
    @State private var isExpanded = false
    @State private var usesDarkMode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VideoDetailResolvedInfoContent(store: store, isExpanded: $isExpanded)
                Toggle("实验开启", isOn: Binding(
                    get: { libraryStore.videoDetailSponsoredBadgeExperimentEnabled },
                    set: { libraryStore.setVideoDetailSponsoredBadgeExperimentEnabled($0) }
                )).accessibilityIdentifier("fixture.badge.enabled")
                Toggle("恰饭视频", isOn: $isSponsored).accessibilityIdentifier("fixture.badge.sponsored")
                Toggle("包含 attribute", isOn: $hasAttribute).accessibilityIdentifier("fixture.badge.attribute")
                Toggle("长标题", isOn: $usesLongTitle).accessibilityIdentifier("fixture.badge.longTitle")
                Toggle("展开标题", isOn: $isExpanded).accessibilityIdentifier("fixture.badge.expanded")
                Toggle("深色模式", isOn: $usesDarkMode).accessibilityIdentifier("fixture.badge.dark")
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .preferredColorScheme(usesDarkMode ? .dark : .light)
        .onAppear { libraryStore.setVideoDetailSponsoredBadgeExperimentEnabled(false) }
        .onChange(of: payload, initial: true) { _, payload in
            // These fixed JSON fixtures use the same VideoItem decoder as /x/web-interface/view.
            guard let video = try? JSONDecoder().decode(VideoItem.self, from: Data(payload.utf8)) else { return }
            var snapshot = VideoDetailDescriptionRenderSnapshot()
            snapshot.titleText = video.title
            snapshot.isSponsored = video.isSponsored
            snapshot.hasResolvedDetailMetadata = true
            store.update(snapshot)
        }
    }

    private var payload: String {
        let title = usesLongTitle
            ? "这是一个非常非常长的视频标题，用来验证恰饭标识位于第一行，并且展开之后所有文字仍然能够正常换行显示，直到标题的最后一句话。"
            : "这是一个视频标题"
        let attribute = hasAttribute ? ",\"attribute\":\(isSponsored ? 4096 : 0)" : ""
        return "{\"bvid\":\"BV1fixture\",\"title\":\"\(title)\"\(attribute)}"
    }
}
#endif
