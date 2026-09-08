import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var holder = LiveViewModelHolder()
    @StateObject private var pullRefreshSettings = PullRefreshRuntimeSettingsStore()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                LiveFeedView(
                    viewModel: viewModel,
                    pullRefreshTriggerDistance: CGFloat(pullRefreshSettings.triggerDistance)
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if libraryStore.scrollableTabHeadersExperimentEnabled {
                            ScrollableTabHeader("直播")
                        }

                        LiveFeedSkeletonList(horizontalPadding: 12, topPadding: 18)
                    }
                }
                .nativeTopScrollEdgeEffect()
                .background(Color(.systemBackground))
                .task {
                    holder.configure(api: dependencies.api)
                }
            }
        }
        .task {
            pullRefreshSettings.bind(dependencies.libraryStore)
        }
    }
}
