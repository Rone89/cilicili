import SwiftUI

struct CommentAvatar: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        let pixelSize = Int(size * 3)
        AvatarRemoteImage(urlString: urlString, pixelSize: pixelSize) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.9))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
