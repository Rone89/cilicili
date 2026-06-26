import SwiftUI

struct LiveRoomCardMetadataRow: View {
    let room: LiveRoom
    let title: String
    let metadataText: String

    private static let avatarSide: CGFloat = 34

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            AvatarRemoteImage(urlString: room.face, pixelSize: 56) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: Self.avatarSide, height: Self.avatarSide)
            .clipShape(Circle())
            .mediaShadow(.subtle)

            VStack(alignment: .leading, spacing: 1) {
                StableVideoTitleText(title, style: .feedHeadline, lineLimit: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(metadataText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.avatarSide, alignment: .center)
        }
        .frame(height: Self.avatarSide)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
