import SwiftUI

struct NativeLoadingIndicator: View {
    var body: some View {
        DelayedLoadingContent {
            ProgressView()
                .progressViewStyle(.circular)
        }
    }
}
