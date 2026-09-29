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
                    LiveFeedSkeletonList()
                        .padding(.horizontal, libraryStore.standardPageHorizontalInset)
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
