import SwiftUI

struct DynamicFeedTextContent: View {
    let collapsedInput: DynamicAttributedTextInput
    let expandedInput: DynamicAttributedTextInput
    let preferredWidth: CGFloat?
    let showsExpandButton: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DynamicRichTextView(
                input: isExpanded ? expandedInput : collapsedInput,
                preferredWidth: preferredWidth
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transaction { transaction in
                transaction.animation = nil
            }

            if showsExpandButton {
                Button(action: toggleExpanded) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起" : "展开")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleExpanded() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isExpanded.toggle()
        }
    }
}
