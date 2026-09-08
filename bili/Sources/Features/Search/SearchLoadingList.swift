import SwiftUI

struct SearchLoadingList: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if libraryStore.scrollableTabHeadersExperimentEnabled {
                    ScrollableTabHeader("搜索")
                        .padding(.horizontal, -16)
                }

                SearchLoadingContent(scope: .comprehensive)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(.systemBackground))
        .nativeTopScrollEdgeEffect()
    }
}
