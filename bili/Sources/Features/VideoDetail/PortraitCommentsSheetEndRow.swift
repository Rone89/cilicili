import SwiftUI

struct PortraitCommentsSheetEndRow: View {
    var body: some View {
        Text("没有更多评论了")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
