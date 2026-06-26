import SwiftUI

struct InitialPageMenuPlaceholder: View {
    let pageCount: Int?

    private var title: String {
        pageCount.map { "\($0)P" } ?? "分P"
    }

    var body: some View {
        Button(action: {}) {
            Label(title, systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
