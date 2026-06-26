import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var holder = SearchViewModelHolder()
    @State private var showsAllHotSearches = false

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                SearchContentView(
                    viewModel: viewModel,
                    showsHotSearches: libraryStore.showsHotSearches,
                    showsAllHotSearches: $showsAllHotSearches
                )
            } else {
                SearchLoadingList()
                    .task {
                        holder.configure(api: dependencies.api)
                    }
            }
        }
        .rootNavigationTitle("搜索") {
            if let viewModel = holder.viewModel {
                SearchScopeMenu(viewModel: viewModel)
            }
        }
        .nativeTopNavigationChrome()
    }
}
