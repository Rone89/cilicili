import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var holder = LiveViewModelHolder()
    @StateObject private var titleState = FeedChromeTitleState()

    private var isLoading: Bool {
        guard let viewModel = holder.viewModel else { return false }
        return viewModel.isRefreshing || (viewModel.rooms.isEmpty && viewModel.state.isLoading)
    }

    var body: some View {
        LiveFeedScreenContent(holder: holder)
        .environment(\.feedChromeTitleState, titleState)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 12).accessibilityHidden(true)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                FeedToolbarTitle(title: AppTab.live.title, state: titleState, accessibilityID: "live.feed.title")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .topBarTrailing) {
                LiveRefreshToolbarButton(isLoading: isLoading, onRefresh: refresh)
            }
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("")
    }

    private func refresh() {
        if holder.viewModel == nil {
            holder.configure(api: dependencies.api)
        }
        guard let viewModel = holder.viewModel else { return }
        Task { await viewModel.refresh() }
    }
}

struct LiveFeedScreenContent: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var holder: LiveViewModelHolder

    var body: some View {
        if let viewModel = holder.viewModel {
            LiveFeedView(viewModel: viewModel, showsNativeRefreshButton: false)
        } else {
            ScrollView {
                LiveFeedSkeletonList()
                    .padding(.horizontal, libraryStore.standardPageHorizontalInset)
            }
            .rootFloatingTabBarContentPadding()
            .nativeTopScrollEdgeEffect(hidesRootNavigationTitle: false)
            .background(Color(.systemBackground))
            .task { holder.configure(api: dependencies.api) }
        }
    }
}
