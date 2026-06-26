import SwiftUI
import UIKit

struct VideoDetailInfoTitleText: View {
    let text: String
    let isExpanded: Bool

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .lineSpacing(1.5)
            .foregroundStyle(.primary)
            .lineLimit(isExpanded ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
