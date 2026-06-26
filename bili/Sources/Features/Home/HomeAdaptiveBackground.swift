import SwiftUI

extension Color {
    static let homeAdaptiveBackground = Color(uiColor: UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return .systemGroupedBackground
        }
        return UIColor(red: 0.965, green: 0.973, blue: 0.984, alpha: 1)
    })
}
