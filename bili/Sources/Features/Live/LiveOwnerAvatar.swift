import SwiftUI

struct LiveOwnerAvatar: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        let owner = viewModel.anchorOwner
        if owner.mid > 0 {
            NavigationLink(value: owner) {
                LiveOwnerAvatarContent(urlString: owner.face?.normalizedBiliURL())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("打开 \(owner.name) 的主页")
        } else {
            LiveOwnerAvatarContent(urlString: viewModel.anchorFace)
                .opacity(0.58)
                .accessibilityHidden(true)
        }
    }
}

struct LiveOwnerAvatarContent: View {
    let urlString: String?

    var body: some View {
        AvatarRemoteImage(urlString: urlString, pixelSize: 112) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2.2)
        .shadow(color: .black.opacity(0.10), radius: 1.2, x: 0, y: 0.6)
        .frame(width: 32, height: 32)
        .contentShape(Circle())
    }
}
