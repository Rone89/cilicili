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
    @EnvironmentObject private var libraryStore: LibraryStore
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool
    let pullRefreshTriggerDistance: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = libraryStore.standardPageHorizontalInset
            let contentWidth = max(floor(proxy.size.width - horizontalInset * 2), 0)

            DynamicFeedScrollContent(
                api: api,
                viewModel: viewModel,
                isLoggedIn: isLoggedIn,
                contentWidth: contentWidth,
                horizontalInset: horizontalInset,
                pullRefreshTriggerDistance: pullRefreshTriggerDistance
            )
        }
        .background(Color(.systemBackground))
    }
}
