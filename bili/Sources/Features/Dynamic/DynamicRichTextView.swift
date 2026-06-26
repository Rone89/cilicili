import SwiftUI
import UIKit

struct DynamicRichTextView: View {
    let segments: [DynamicTextSegment]
    let font: UIFont
    let textColor: Color
    let emoteSize: CGFloat
    let maxLines: Int?
    let preferredWidth: CGFloat?
    private let textInput: DynamicAttributedTextInput
    @Environment(\.openAppURLAction) private var openAppURL

    init(
        segments: [DynamicTextSegment],
        font: UIFont,
        textColor: Color,
        emoteSize: CGFloat,
        maxLines: Int?,
        preferredWidth: CGFloat? = nil
    ) {
        self.segments = segments
        self.font = font
        self.textColor = textColor
        self.emoteSize = emoteSize
        self.maxLines = maxLines
        self.preferredWidth = preferredWidth

        self.textInput = DynamicAttributedTextInput(
            segments: segments.isEmpty ? [.text(" ")] : segments,
            baseFont: font,
            textColor: UIColor(textColor),
            emoteSize: emoteSize,
            maxLines: maxLines
        )
    }

    init(input: DynamicAttributedTextInput, preferredWidth: CGFloat? = nil) {
        self.segments = input.segments
        self.font = input.baseFont
        self.textColor = Color(input.textColor)
        self.emoteSize = input.emoteSize
        self.maxLines = input.maxLines
        self.preferredWidth = preferredWidth
        self.textInput = input
    }

    var body: some View {
        if let plainText = textInput.nativePlainText {
            Text(textInput.nativeAttributedPlainText(plainText))
                .font(textInput.nativeSwiftUIFont)
                .foregroundStyle(Color(textInput.textColor))
                .lineLimit(textInput.maxLines)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(plainText)
        } else {
            DynamicAttributedTextLabel(
                input: textInput,
                preferredWidth: preferredWidth,
                onURLTap: { url in
                    openAppURL?(url)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
