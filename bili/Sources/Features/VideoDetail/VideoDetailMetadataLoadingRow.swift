import SwiftUI

struct VideoDetailMetadataLoadingRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("UP主  1.2万观看  刚刚发布")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 24, alignment: .center)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
