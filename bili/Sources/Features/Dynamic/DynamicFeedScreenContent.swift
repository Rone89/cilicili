import SwiftUI

struct DynamicInitialFeedContent: View {
    let isLoggedIn: Bool

    var body: some View {
        Group {
            if isLoggedIn {
                DynamicFeedSkeletonScrollContent()
            } else {
                DynamicLoginEmptyState()
            }
        }
        .rootFloatingTabBarContentPadding()
        .background(Color(.systemBackground))
    }
}

struct DynamicFeedScreenContent: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var libraryStore: LibraryStore
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let topUploaderStripViewModel: DynamicViewModel
    let isLoggedIn: Bool
    var selectedUP: VideoOwner? = nil
    var onChooseUP: (() -> Void)? = nil
    var titleState: FeedChromeTitleState? = nil

    var body: some View {
        GeometryReader { proxy in
            let adaptiveEnabled = libraryStore.adaptiveLargeScreenLayoutExperimentEnabled
            let horizontalInset = adaptiveEnabled
                ? AdaptiveLayoutPolicy.horizontalInset(
                    for: proxy.size.width,
                    horizontalSizeClass: horizontalSizeClass,
                    containerHeight: proxy.size.height,
                    adaptiveEnabled: true
                )
                : libraryStore.standardPageHorizontalInset
            let contentWidth = adaptiveEnabled
                ? AdaptiveLayoutPolicy.centeredContentWidth(
                    containerWidth: proxy.size.width,
                    maxContentWidth: AdaptiveLayoutPolicy.readingColumnMaxWidth,
                    horizontalInset: horizontalInset
                )
                : max(floor(proxy.size.width - horizontalInset * 2), 0)

            DynamicFeedScrollContent(
                api: api,
                viewModel: viewModel,
                topUploaderStripViewModel: topUploaderStripViewModel,
                isLoggedIn: isLoggedIn,
                contentWidth: contentWidth,
                horizontalInset: horizontalInset,
                selectedUP: selectedUP, onChooseUP: onChooseUP,
                titleState: titleState
            )
        }
        .background(Color(.systemBackground))
    }
}
