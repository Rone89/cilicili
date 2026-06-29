import SwiftUI

struct VideoCardElevatedBody<Cover: View>: View {
    let display: VideoCardDisplayModel
    let cover: Cover
    let showsPublishTimeInAuthorRow: Bool
    let showsAuthorIdentity: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover

            VideoCardTextStack(
                display: display,
                showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow,
                showsAuthorIdentity: showsAuthorIdentity
            )
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .mediaShadow(.subtle)
    }
}

struct VideoCardBlendedBody<Cover: View>: View {
    let display: VideoCardDisplayModel
    let cover: Cover
    let showsPublishTimeInAuthorRow: Bool
    let showsAuthorIdentity: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .videoCoverSurface(cornerRadius: 15, shadowLevel: .control)

            VideoCardTextStack(
                display: display,
                showsPublishTimeInAuthorRow: showsPublishTimeInAuthorRow,
                showsAuthorIdentity: showsAuthorIdentity
            )
            .padding(.horizontal, 2)
        }
    }
}
