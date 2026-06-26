import SwiftUI
import UIKit

enum FeedTypography {
    static let primaryTextSize: CGFloat = 15
    static let bodyLineSpacing: CGFloat = 2

    static let bodyFont: Font = .system(size: primaryTextSize, weight: .regular)
    static let titleFont: Font = .system(size: primaryTextSize, weight: .semibold)

    static let bodyUIFont = UIFont.systemFont(ofSize: primaryTextSize, weight: .regular)
    static let titleUIFont = UIFont.systemFont(ofSize: primaryTextSize, weight: .semibold)
}
