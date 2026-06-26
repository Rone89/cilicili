import SwiftUI

struct VideoDetailChromeStatusBarBackdrop: View {
    let isHidden: Bool

    var body: some View {
        VideoDetailStatusBarBackdrop(isHidden: isHidden)
    }
}
