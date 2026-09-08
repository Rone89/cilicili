import SwiftUI

struct DynamicFeedTextContent: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let collapsedInput: DynamicAttributedTextInput
    let expandedInput: DynamicAttributedTextInput
    let copyText: String?
    let preferredWidth: CGFloat?
    let showsExpandButton: Bool
    let onOpenDetail: (() -> Void)?
    @Binding var isExpanded: Bool
    @State private var measuredShowsExpandButton = false
    @State private var measuredTextWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DynamicRichTextView(
                input: isExpanded ? expandedInput : collapsedInput,
                preferredWidth: preferredWidth,
                onNonLinkTap: onOpenDetail
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .transaction { transaction in
                transaction.animation = nil
            }
            .dynamicCopyableText(copyText)

            if showsExpandButton || measuredShowsExpandButton {
                Button(action: toggleExpanded) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起" : "展开")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .appTypography(.action, fallback: .footnote.weight(.semibold))
                    .foregroundStyle(appTintColor)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            floor(geometry.size.width)
        } action: { _, viewWidth in
            let textWidth = preferredWidth ?? viewWidth
            measuredTextWidth = textWidth
            updateExpansionVisibility(fittingWidth: textWidth)
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            updateExpansionVisibility(fittingWidth: measuredTextWidth)
        }
    }

    private func toggleExpanded() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isExpanded.toggle()
        }
    }

    private func updateExpansionVisibility(fittingWidth width: CGFloat) {
        let input = collapsedInput.resolvingTypography(
            contentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
        measuredShowsExpandButton = input.exceedsMaximumLineCount(fittingWidth: width)
    }
}
