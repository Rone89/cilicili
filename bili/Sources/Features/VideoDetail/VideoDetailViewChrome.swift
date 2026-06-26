import SwiftUI

struct VideoDetailViewChrome: ViewModifier {
    let hidesRootTabBar: Bool

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .hideRootTabBarWhenNeeded(hidesRootTabBar)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

extension View {
    func videoDetailViewChrome(hidesRootTabBar: Bool) -> some View {
        modifier(VideoDetailViewChrome(hidesRootTabBar: hidesRootTabBar))
    }
}
