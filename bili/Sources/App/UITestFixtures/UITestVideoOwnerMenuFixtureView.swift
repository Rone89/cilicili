#if DEBUG
import SwiftUI

/// Exercises the actual action strip and native menu without account or network dependencies.
struct UITestVideoOwnerMenuFixtureView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var isFollowing = false
    @State private var isMutatingFollow = false
    @State private var usesGlassButtons = false
    @State private var showsSpace = false
    @State private var hasOwner = true

    private let owner = VideoOwner(mid: 42, name: "测试 UP", face: nil)

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 32) {
                    Toggle("液态玻璃按钮", isOn: $usesGlassButtons)
                        .accessibilityIdentifier("fixture.owner.glass")
                    Toggle("正在处理关注请求", isOn: $isMutatingFollow)
                        .accessibilityIdentifier("fixture.owner.mutating")
                    Toggle("UP 信息可用", isOn: $hasOwner)
                        .accessibilityIdentifier("fixture.owner.available")

                    VideoDetailActionStrip(
                        model: model(width: max(geometry.size.width - 40, 1)),
                        onFollow: { isFollowing.toggle() },
                        onLike: {}, onCoin: {}, onFavorite: {}, onShareTap: {}
                    )
                    .equatable()
                    .environment(\.videoDetailActionButtonStyle, usesGlassButtons ? .liquidGlass : .plain)
                    .environment(\.openVideoOwnerRouteAction, { _ in showsSpace = true })
                    Spacer()
                }
                .padding(20)
            }
            .navigationDestination(isPresented: $showsSpace) {
                Text("测试 UP 的个人空间")
                    .accessibilityIdentifier("fixture.owner.space")
            }
        }
        .environment(\.appThemeTintColor, libraryStore.appTintColor)
    }

    private func model(width: CGFloat) -> VideoDetailActionStripModel {
        VideoDetailActionStripModel(
            owner: hasOwner ? owner : nil, canFavorite: true, shareURL: URL(string: "https://example.invalid/video"),
            shareSubject: "测试视频", shareMessage: "测试视频", contentWidth: width,
            isFollowing: isFollowing, isLiked: false, isCoined: false, isFavorited: false,
            coinCount: 0, isMutatingLike: false, isMutatingCoin: false, isMutatingFavorite: false,
            isMutatingFollow: isMutatingFollow
        )
    }
}
#endif
