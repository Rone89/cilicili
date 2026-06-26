import SwiftUI

struct VideoDetailPlayerSurfaceBackButtonHost: View {
    let action: () -> Void

    var body: some View {
        VideoDetailPlayerBackButton(action: action)
    }
}
