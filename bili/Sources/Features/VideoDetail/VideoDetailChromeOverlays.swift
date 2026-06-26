import SwiftUI
import UIKit

struct VideoDetailChromeStatusBarStyleBridge: View {
    let style: UIStatusBarStyle
    let isHidden: Bool

    var body: some View {
        StatusBarStyleBridge(style: style, isHidden: isHidden)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }
}
