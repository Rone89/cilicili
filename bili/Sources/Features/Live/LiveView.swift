import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var holder = LiveViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                LiveFeedView(viewModel: viewModel)
            } else {
                ScrollView {
                    LiveFeedSkeletonList(horizontalPadding: 12, topPadding: 2)
                }
                .nativeTopScrollEdgeEffect()
                .background(Color(.systemBackground))
                .task {
                    holder.configure(api: dependencies.api)
                }
            }
        }
        .rootNavigationTitle("直播")
        .nativeTopNavigationChrome()
    }
}
