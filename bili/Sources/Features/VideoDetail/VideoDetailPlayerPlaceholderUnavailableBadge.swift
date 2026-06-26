import SwiftUI

struct VideoDetailPlayerPlaceholderUnavailableBadge: View {
    var body: some View {
        Label("当前档位暂不可播放", systemImage: "lock.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.48))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}
