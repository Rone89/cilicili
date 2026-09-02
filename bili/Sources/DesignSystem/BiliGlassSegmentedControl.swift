import SwiftUI

struct BiliGlassSegmentedControl<Option: Identifiable & Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    let options: [Option]
    let selected: Option
    let title: (Option) -> String
    let select: (Option) -> Void
    var showsContainer = true
    var animation: Animation = .smooth(duration: 0.28)

    private var activeAnimation: Animation? {
        reduceMotion ? nil : animation
    }

    @ViewBuilder
    var body: some View {
        if showsContainer {
            controlContent
                .biliBottomTabGlassEffect(interactive: false, in: Capsule())
        } else {
            controlContent
        }
    }

    private var controlContent: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segmentButton(for: option)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .frame(height: 40)
        .accessibilityElement(children: .contain)
    }

    private var selectedFill: Color {
        Color.primary.opacity(0.12)
    }

    private func segmentButton(for option: Option) -> some View {
        let isSelected = option == selected

        return Button {
            guard !isSelected else { return }
            withAnimation(activeAnimation) {
                select(option)
            }
        } label: {
            Text(title(option))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(Color.primary.opacity(isSelected ? 1 : 0.72))
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(selectedFill)
                            .matchedGeometryEffect(id: "selected", in: selectionNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(height: 40)
        .accessibilityLabel(title(option))
        .accessibilityValue(isSelected ? "已选中" : "")
    }
}
