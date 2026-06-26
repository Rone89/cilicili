import SwiftUI

struct VideoDetailActionStripOwnerAvatar: View {
    let owner: VideoOwner?

    var body: some View {
        if let owner {
            NavigationLink(value: owner) {
                VideoDetailActionStripAvatarImage(urlString: owner.face?.normalizedBiliURL())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("打开 \(owner.name) 的主页")
        } else {
            VideoDetailActionStripAvatarImage(urlString: nil)
                .opacity(0.58)
                .accessibilityHidden(true)
        }
    }
}

private struct VideoDetailActionStripAvatarImage: View {
    let urlString: String?

    var body: some View {
        AvatarRemoteImage(urlString: urlString, pixelSize: VideoDetailActionStrip.Metrics.avatarPixelSize) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: VideoDetailActionStrip.Metrics.avatarImageSide, height: VideoDetailActionStrip.Metrics.avatarImageSide)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2.2)
        .shadow(color: .black.opacity(0.10), radius: 1.2, x: 0, y: 0.6)
        .frame(width: VideoDetailActionStrip.Metrics.avatarSide, height: VideoDetailActionStrip.Metrics.avatarSide)
        .contentShape(Circle())
    }
}
