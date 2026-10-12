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
    let topUploaderStripViewModel: DynamicViewModel
    let isLoggedIn: Bool
    var selectedUP: VideoOwner? = nil
    var onChooseUP: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = libraryStore.standardPageHorizontalInset
            let contentWidth = max(floor(proxy.size.width - horizontalInset * 2), 0)

            DynamicFeedScrollContent(
                api: api,
                viewModel: viewModel,
                topUploaderStripViewModel: topUploaderStripViewModel,
                isLoggedIn: isLoggedIn,
                contentWidth: contentWidth,
                horizontalInset: horizontalInset,
                selectedUP: selectedUP, onChooseUP: onChooseUP
            )
        }
        .background(Color(.systemBackground))
    }
}
