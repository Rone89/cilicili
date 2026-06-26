import SwiftUI

extension View {
    @ViewBuilder
    func hideRootTabBarWhenNeeded(_ isHidden: Bool) -> some View {
        if isHidden {
            hidesRootTabBarOnPush()
        } else {
            self
        }
    }
}
