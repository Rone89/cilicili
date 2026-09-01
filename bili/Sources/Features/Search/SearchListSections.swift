import SwiftUI

struct SearchSortHeaderButton: View {
    @ObservedObject var viewModel: SearchViewModel
    var showsContainer = true

    var body: some View {
        Menu {
            ForEach(SearchSortOrder.allCases) { order in
                Button {
                    Task { await viewModel.selectOrder(order) }
                } label: {
                    Label(order.title, systemImage: order == viewModel.selectedOrder ? "checkmark" : "arrow.up.arrow.down")
                }
            }
        } label: {
            sortLabel
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.selectedScope.supportsOrder)
        .opacity(viewModel.selectedScope.supportsOrder ? 1 : 0.42)
        .animation(.smooth(duration: 0.22), value: viewModel.selectedScope.supportsOrder)
        .accessibilityLabel("搜索结果排序")
        .accessibilityValue(viewModel.selectedOrder.title)
    }

    @ViewBuilder
    private var sortLabel: some View {
        let label = Label(sortTitle, systemImage: "arrow.up.arrow.down")
            .font(.subheadline.weight(.medium))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(viewModel.selectedScope.supportsOrder ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 40)

        if showsContainer {
            label
                .biliBottomTabGlassEffect(interactive: false, in: Capsule())
        } else {
            label
        }
    }

    private var sortTitle: String {
        viewModel.selectedScope.supportsOrder ? viewModel.selectedOrder.title : "排序"
    }
}
