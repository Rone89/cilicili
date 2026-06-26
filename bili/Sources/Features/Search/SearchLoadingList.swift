import SwiftUI

struct SearchLoadingList: View {
    var body: some View {
        List {
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    SearchResultSkeletonRow()
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                }
            } header: {
                SearchSectionHeader(title: "搜索", systemImage: "magnifyingglass")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .nativeTopScrollEdgeEffect()
    }
}
