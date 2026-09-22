import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var holder = LiveViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                LiveFeedView(
                    viewModel: viewModel
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        DelayedLoadingContent {
                            LiveFeedSkeletonList(
                                horizontalPadding: libraryStore.standardPageHorizontalInset,
                                topPadding: 18
                            )
                        }
                    }
                }
                .nativeTopScrollEdgeEffect()
                .background(Color(.systemBackground))
                .task {
                    holder.configure(api: dependencies.api)
                }
            }
        }
    }
}
