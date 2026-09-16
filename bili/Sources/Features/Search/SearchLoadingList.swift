import SwiftUI

struct SearchLoadingList: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        let horizontalInset = libraryStore.standardPageHorizontalInset

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SearchLoadingContent(scope: .comprehensive)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, 18)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(.systemBackground))
        .nativeTopScrollEdgeEffect()
    }
}
