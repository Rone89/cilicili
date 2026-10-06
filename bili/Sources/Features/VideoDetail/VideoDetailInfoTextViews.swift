import SwiftUI
import UIKit

struct VideoDetailInfoTitleText: View {
    let text: String
    let isExpanded: Bool

    var showsSponsoredBadge = false

    var body: some View {
        if showsSponsoredBadge {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                SponsoredBadge()
                title
            }
        } else {
            title
        }
    }

    private var title: some View {
        PlaybackDetailTitleText(
            text: text,
            lineLimit: isExpanded ? nil : 1
        )
        .accessibilityIdentifier("video.detail.title")
    }
}

/// Ordinary capsule sized by its text line, with no extra vertical padding.
private struct SponsoredBadge: View {
    var body: some View {
        Text("恰饭")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .background(.quaternary, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("video.detail.sponsoredBadge")
    }
}
