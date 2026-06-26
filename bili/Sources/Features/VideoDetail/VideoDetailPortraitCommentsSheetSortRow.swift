import SwiftUI

struct PortraitCommentsSheetSortRow: View {
    let selectedSort: CommentSort
    let selectSort: (CommentSort) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(CommentSort.allCases) { sort in
                    Button {
                        selectSort(sort)
                    } label: {
                        Text(sort.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedSort == sort ? .primary : .secondary)
                    .commentPlayerGlassCapsule()
                    .opacity(selectedSort == sort ? 1 : 0.72)
                    .accessibilityLabel(sort.title)
                    .accessibilityValue(selectedSort == sort ? "已选中" : "")
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
