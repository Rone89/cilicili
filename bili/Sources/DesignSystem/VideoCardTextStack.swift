import SwiftUI

struct VideoCardTextStack: View {
    let display: VideoCardDisplayModel
    let showsPublishTimeInAuthorRow: Bool
    let showsAuthorIdentity: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLabel
            authorRow
        }
    }

    private var titleLabel: some View {
        StableVideoTitleText(display.title, style: .compactCard)
            .frame(minHeight: 36, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorRow: some View {
        HStack(spacing: 4) {
            if showsAuthorIdentity {
                AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 48) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 14, height: 14)
                .clipShape(Circle())
                .mediaShadow(.subtle)

                Text(display.authorName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showsPublishTimeInAuthorRow {
                if showsAuthorIdentity {
                    Spacer(minLength: 6)
                }

                Text(display.publishTimeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
